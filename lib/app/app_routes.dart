import 'package:flutter/material.dart';

import '../features/rates/presentation/pages/app_version_screen.dart';
import '../features/rates/presentation/pages/calculator_screen.dart';
import '../features/rates/presentation/pages/home_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String calculator = '/calculator';
  static const String about = '/about';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    required ThemeMode themeMode,
    required VoidCallback onToggleTheme,
  }) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => switch (settings.name) {
        calculator => CalculatorScreen(
          fixedRateCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).fixedRateCode
              : null,
          initialFromCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).fromCode
              : null,
          initialToCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).toCode
              : null,
        ),
        about => const AppVersionScreen(),
        _ => HomeScreen(themeMode: themeMode, onToggleTheme: onToggleTheme),
      },
    );
  }
}

class CalculatorRouteArgs {
  const CalculatorRouteArgs({this.fixedRateCode, this.fromCode, this.toCode});

  final String? fixedRateCode;
  final String? fromCode;
  final String? toCode;
}
