import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/audit_log.dart';
import 'audit_service.dart';

class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static final UpdateService instance = UpdateService();

  final Dio _dio;

  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) {
      return null;
    }

    if (AppConfig.supabaseAnonKey.isEmpty) {
      return null;
    }

    final localBuildNumber = await _localBuildNumber();
    debugPrint('UpdateService.checkForUpdate: localBuildNumber = $localBuildNumber');

    try {
      final data = await Supabase.instance.client
          .from('versions_dollap')
          .select('build_number, version_name, download_url, is_mandatory, changelog')
          .order('build_number', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        debugPrint('UpdateService.checkForUpdate: no version row found in versions_dollap');
        return null;
      }

      final remoteVersion = UpdateInfo.fromJson(data);
      debugPrint('UpdateService.checkForUpdate: remote buildNumber = ${remoteVersion.buildNumber}, downloadUrl = ${remoteVersion.downloadUrl}');

      if (remoteVersion.downloadUrl.isEmpty || remoteVersion.buildNumber <= localBuildNumber) {
        debugPrint('UpdateService.checkForUpdate: no update needed');
        return null;
      }

      debugPrint('UpdateService.checkForUpdate: update available');
      return remoteVersion;
    } catch (error, stackTrace) {
      debugPrint('UpdateService.checkForUpdate failed: $error');
      await _logAudit(
        accion: 'UPDATE_CHECK_FAILED',
        mensaje: error.toString(),
        codigo: error.runtimeType.toString(),
        metadatos: {
          'localBuildNumber': localBuildNumber,
          'stackTrace': stackTrace.toString(),
        },
      );
      return null;
    }
  }

  Future<int> _localBuildNumber() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return int.tryParse(packageInfo.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<File> downloadApk(
    String downloadUrl,
    void Function(double progress) onProgress, {
    CancelToken? cancelToken,
  }) async {
    final directory = await getTemporaryDirectory();
    final apkFile = File('${directory.path}/dollapp_update.apk');

    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    await _dio.download(
      downloadUrl,
      apkFile.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress(received / total);
        }
      },
      options: Options(responseType: ResponseType.bytes, followRedirects: true),
      cancelToken: cancelToken,
    );

    return apkFile;
  }

  Future<void> installApk(File apkFile) async {
    try {
      final result = await OpenFile.open(apkFile.path);
      if (result.type != ResultType.done) {
        throw Exception('No se pudo abrir el instalador: ${result.message}');
      }
    } catch (error, stackTrace) {
      await _logAudit(
        accion: 'UPDATE_INSTALL_FAILED',
        mensaje: error.toString(),
        codigo: error.runtimeType.toString(),
        metadatos: {
          'apkPath': apkFile.path,
          'stackTrace': stackTrace.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _logAudit({
    required String accion,
    required String mensaje,
    required String codigo,
    Map<String, dynamic>? metadatos,
  }) async {
    try {
      await AuditService.instance.logError(
        AuditLog(
          accion: accion,
          mensaje: mensaje,
          codigo: codigo,
          metadatos: metadatos,
        ),
      );
    } catch (_) {
      // No bloquear la app si falla auditoría.
    }
  }
}

class UpdateInfo {
  UpdateInfo({
    required this.buildNumber,
    required this.versionName,
    required this.downloadUrl,
    required this.isMandatory,
    required this.changelog,
  });

  final int buildNumber;
  final String versionName;
  final String downloadUrl;
  final bool isMandatory;
  final String changelog;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      buildNumber: json['build_number'] is int
          ? json['build_number'] as int
          : int.tryParse(json['build_number']?.toString() ?? '') ?? 0,
      versionName: json['version_name']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      isMandatory: json['is_mandatory'] == true || json['is_mandatory']?.toString() == 'true',
      changelog: json['changelog']?.toString() ?? '',
    );
  }
}
