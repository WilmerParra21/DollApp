package com.devsparra.dollapp

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "com.devsparra.dollapp/update_service",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "canRequestPackageInstalls" -> {
          val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
          } else {
            true
          }
          result.success(canInstall)
        }
        else -> result.notImplemented()
      }
    }
  }
}
