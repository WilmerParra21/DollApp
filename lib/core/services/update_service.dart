import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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

    final packageInfo = await PackageInfo.fromPlatform();
    final localBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
    final localVersionName = packageInfo.version;

    try {
      final fields = AppConfig.updateChannel == UpdateChannel.apk
          ? 'build_number, version_name, download_url, is_mandatory, news'
          : 'build_number, version_name, is_mandatory, news';

      final data = await Supabase.instance.client
          .from('versions_dollap')
          .select(fields)
          .order('build_number', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        return null;
      }

      final remoteVersion = UpdateInfo.fromJson(data);

      final noUpdateNeeded =
          remoteVersion.buildNumber > 0
              ? remoteVersion.buildNumber <= localBuildNumber
              : remoteVersion.versionName == localVersionName;

      if (noUpdateNeeded) {
        return null;
      }

      return remoteVersion;
    } catch (error, stackTrace) {
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

  bool get hasPlayStoreLink {
    return AppConfig.hasPlayStoreConfig;
  }

  Future<void> openPlayStore() async {
    if (!Platform.isAndroid || !hasPlayStoreLink) return;

    final packageInfo = await PackageInfo.fromPlatform();
    final packageName = AppConfig.playStorePackageName.isNotEmpty
        ? AppConfig.playStorePackageName
        : packageInfo.packageName;

    final storeUrl = AppConfig.playStoreUrl.isNotEmpty
        ? AppConfig.playStoreUrl
        : 'https://play.google.com/store/apps/details?id=$packageName';

    final marketUri = 'market://details?id=$packageName';

    try {
      final intent = AndroidIntent(action: 'action_view', data: marketUri);
      await intent.launch();
    } catch (error, stackTrace) {
      await _logAudit(
        accion: 'UPDATE_OPEN_PLAY_STORE_FAILED',
        mensaje: error.toString(),
        codigo: error.runtimeType.toString(),
        metadatos: {
          'packageName': packageName,
          'storeUrl': storeUrl,
          'stackTrace': stackTrace.toString(),
        },
      );
      final fallbackIntent = AndroidIntent(
        action: 'action_view',
        data: storeUrl,
      );
      await fallbackIntent.launch();
    }
  }

  Future<bool> isPlayStoreAvailable() async {
    if (!Platform.isAndroid ||
        !hasPlayStoreLink ||
        AppConfig.playStoreUrl.isEmpty) {
      return false;
    }

    try {
      final response = await _dio.get(
        AppConfig.playStoreUrl,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Mobile Safari/537.36',
          },
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
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
        final errorMessage = result.message;
        if (errorMessage.contains('REQUEST_INSTALL_PACKAGES') ||
            errorMessage.contains('Permission denied')) {
          throw InstallPermissionDeniedException(errorMessage);
        }
        throw Exception('No se pudo abrir el instalador: $errorMessage');
      }
    } catch (error, stackTrace) {
      final message = error.toString();
      final isPermissionError =
          message.contains('REQUEST_INSTALL_PACKAGES') ||
          message.contains('Permission denied');

      await _logAudit(
        accion: isPermissionError
            ? 'UPDATE_INSTALL_PERMISSION_DENIED'
            : 'UPDATE_INSTALL_FAILED',
        mensaje: message,
        codigo: error.runtimeType.toString(),
        metadatos: {
          'apkPath': apkFile.path,
          'stackTrace': stackTrace.toString(),
        },
      );

      if (isPermissionError) {
        throw InstallPermissionDeniedException(message);
      }
      rethrow;
    }
  }

  Future<bool> canInstallFromUnknownSources() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final result = await const MethodChannel(
        'com.devsparra.dollapp/update_service',
      ).invokeMethod<bool>('canRequestPackageInstalls');
      return result == true;
    } on PlatformException {
      return true;
    }
  }

  Future<void> openInstallUnknownAppsSettings() async {
    if (!Platform.isAndroid) return;

    final packageInfo = await PackageInfo.fromPlatform();
    final intent = AndroidIntent(
      action: 'android.settings.MANAGE_UNKNOWN_APP_SOURCES',
      data: 'package:${packageInfo.packageName}',
    );
    await intent.launch();
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

class InstallPermissionDeniedException implements Exception {
  InstallPermissionDeniedException([this.message = '']);

  final String message;

  @override
  String toString() => 'InstallPermissionDeniedException: $message';
}

class UpdateInfo {
  UpdateInfo({
    required this.buildNumber,
    required this.versionName,
    required this.downloadUrl,
    required this.isMandatory,
    required this.news,
  });

  final int buildNumber;
  final String versionName;
  final String downloadUrl;
  final bool isMandatory;
  final String news;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      buildNumber: json['build_number'] is int
          ? json['build_number'] as int
          : int.tryParse(json['build_number']?.toString() ?? '') ?? 0,
      versionName: json['version_name']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      isMandatory:
          json['is_mandatory'] == true ||
          json['is_mandatory']?.toString() == 'true',
      news: json['news']?.toString() ?? '',
    );
  }
}
