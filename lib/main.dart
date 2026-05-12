import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/doll_app.dart';
import 'core/config/app_config.dart';
import 'core/models/audit_log.dart';
import 'core/services/audit_service.dart';

Future<void> main() async {
  // Configurar manejadores globales de errores primero
  _setupErrorHandlers();

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await dotenv.load(fileName: '.env');

      await Supabase.initialize(
        url: 'https://${AppConfig.supabaseProjectRef}.supabase.co',
        anonKey: AppConfig.supabaseAnonKey,
      );

      runApp(const DollApp());
    },
    (error, stackTrace) {
      // Capturar errores no manejados en la zona
      _handleUncaughtError(error, stackTrace, 'UNCAUGHT_ERROR');
    },
  );
}

void _setupErrorHandlers() {
  // Manejar errores de Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    _handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
      'FLUTTER_ERROR',
      metadatos: {
        'library': details.library,
        'context': details.context?.toString(),
        'informationCollector': details.informationCollector?.toString(),
        'silent': details.silent,
      },
    );
  };

  // Manejar errores de plataforma
  PlatformDispatcher.instance.onError = (error, stack) {
    _handleUncaughtError(error, stack, 'PLATFORM_ERROR');
    return true; // Prevenir que se propague
  };
}

void _handleUncaughtError(
  Object error,
  StackTrace stackTrace,
  String accion, {
  Map<String, dynamic>? metadatos,
}) {
  // Log del error
  debugPrint('Uncaught error: $error');
  debugPrintStack(stackTrace: stackTrace);

  // Enviar a auditoría (de forma completamente asíncrona para no bloquear)
  Future.microtask(() async {
    try {
      await AuditService.instance.logError(
        AuditLog(
          accion: accion,
          mensaje: error.toString(),
          codigo: error.runtimeType.toString(),
          metadatos: {
            'stackTrace': stackTrace.toString(),
            'timestamp': DateTime.now().toIso8601String(),
            ...?metadatos,
          },
        ),
      );
    } catch (auditError) {
      // Si la auditoría falla, solo logueamos, no queremos loops de error
      debugPrint('Failed to send audit log: $auditError');
    }
  });
}
