import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/audit_log.dart';

class AuditService {
  AuditService();

  static final AuditService instance = AuditService();

  Future<void> logError(AuditLog log) async {
    if (AppConfig.supabaseAnonKey.isEmpty) {
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('audi_dollap')
          .insert(log.toJson());

      if (response.error != null) {
        // Failed to log error
      }
    } catch (error) {
      // Silent fail
    }
  }
}