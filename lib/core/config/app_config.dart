import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig._();

  static String get supabaseProjectRef {
    return _envValue('SUPABASE_PROJECT_REF') ??
        const String.fromEnvironment(
          'SUPABASE_PROJECT_REF',
          defaultValue: 'omozwoiykohxnvlcivra',
        );
  }

  static String get supabaseAnonKey {
    return _envValue('SUPABASE_ANON_KEY') ??
        const String.fromEnvironment('SUPABASE_ANON_KEY');
  }

  static String get playStorePackageName {
    return _envValue('PLAY_STORE_PACKAGE_NAME') ??
        const String.fromEnvironment(
          'PLAY_STORE_PACKAGE_NAME',
          defaultValue: '',
        );
  }

  static String get playStoreUrl {
    return _envValue('PLAY_STORE_URL') ??
        const String.fromEnvironment('PLAY_STORE_URL', defaultValue: '');
  }

  static bool get hasPlayStoreConfig {
    return playStorePackageName.isNotEmpty || playStoreUrl.isNotEmpty;
  }

  static UpdateChannel get updateChannel {
    final value = _envValue('UPDATE_CHANNEL') ??
        const String.fromEnvironment(
          'UPDATE_CHANNEL',
          defaultValue: 'play_store',
        );
    return switch (value.toLowerCase()) {
      'apk' => UpdateChannel.apk,
      _ => UpdateChannel.playStore,
    };
  }

  static String? _envValue(String key) {
    return dotenv.isInitialized ? dotenv.env[key] : null;
  }
}

enum UpdateChannel {
  playStore,
  apk,
}
