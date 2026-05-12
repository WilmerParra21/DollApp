import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/audit_log.dart';

class AuditService {
  AuditService();

  static final AuditService instance = AuditService();

  Future<void> logError(AuditLog log) async {
    if (AppConfig.supabaseAnonKey.isEmpty) {
      debugPrint('AuditService: Supabase anon key not configured, skipping audit log');
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('audi_dollap')
          .insert(log.toJson());

      if (response.error != null) {
        debugPrint(
          'AuditService: Failed to log error: ${response.error!.statusCode} ${response.error!.message}',
        );
      } else {
        debugPrint('AuditService: Error logged successfully');
      }
    } catch (error, stackTrace) {
      debugPrint('AuditService: Exception while logging error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}