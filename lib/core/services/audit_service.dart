import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/audit_log.dart';

class AuditService {
  AuditService();

  static final AuditService instance = AuditService();

  static const _tableName = 'audi_dollap';
  static const _maxPendingLogs = 50;

  final List<AuditLog> _pendingLogs = <AuditLog>[];
  PackageInfo? _packageInfo;
  bool _supabaseReady = false;
  bool _isFlushing = false;

  /// Debe llamarse inmediatamente después de Supabase.initialize().
  Future<void> markSupabaseReady() async {
    _supabaseReady = true;
    await _flushPendingLogs();
  }

  Future<void> logError(AuditLog log) async {
    if (!_supabaseReady || AppConfig.supabaseAnonKey.isEmpty) {
      if (_pendingLogs.length < _maxPendingLogs) {
        _pendingLogs.add(log);
      }
      return;
    }

    await _insert(log);
  }

  Future<void> _flushPendingLogs() async {
    if (!_supabaseReady || _isFlushing || _pendingLogs.isEmpty) return;

    _isFlushing = true;
    try {
      final pending = List<AuditLog>.from(_pendingLogs);
      _pendingLogs.clear();
      for (final log in pending) {
        await _insert(log);
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _insert(AuditLog log) async {
    try {
      final info = await _getPackageInfo();
      final nowUtc = DateTime.now().toUtc();
      final venezuelaTime = nowUtc.subtract(const Duration(hours: 4));
      final metadata = <String, dynamic>{
        ...?log.metadatos,
        'appVersion': info.version,
        'appBuildNumber': info.buildNumber,
        'platform': Platform.operatingSystem,
        'timestampUtc': nowUtc.toIso8601String(),
        'timestampVenezuela': '${venezuelaTime.toIso8601String()}-04:00',
      };

      await Supabase.instance.client.from(_tableName).insert({
        'accion': log.accion,
        'mensaje': log.mensaje,
        'codigo': log.codigo,
        'metadatos': metadata,
      });
    } catch (error, stackTrace) {
      // La auditorÃ­a no debe provocar otro error, pero tampoco ocultar que
      // el envÃ­o fallÃ³: queda visible en los logs de la aplicaciÃ³n.
      if (error.toString().contains('SocketException') ||
          error.toString().contains('Failed host lookup')) {
        debugPrint('AuditService: evento pendiente; no hay conexión.');
        return;
      }
      debugPrint('AuditService: no se pudo guardar el evento: $error');
      debugPrint(stackTrace.toString());
    }
  }

  Future<PackageInfo> _getPackageInfo() async {
    final cached = _packageInfo;
    if (cached != null) return cached;

    final loaded = await PackageInfo.fromPlatform();
    _packageInfo = loaded;
    return loaded;
  }
}
