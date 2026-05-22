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
          fixedRateId: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).fixedRateId
              : null,
          fixedRateCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).fixedRateCode
              : null,
          initialFromCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).fromCode
              : null,
          initialToCode: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).toCode
              : null,
          closeAppOnBack: settings.arguments is CalculatorRouteArgs
              ? (settings.arguments! as CalculatorRouteArgs).closeAppOnBack
              : false,
        ),
        about => const AppVersionScreen(),
        _ => HomeScreen(
          themeMode: themeMode,
          onToggleTheme: onToggleTheme,
          skipPinnedRedirect: settings.arguments is HomeRouteArgs
              ? (settings.arguments! as HomeRouteArgs).skipPinnedRedirect
              : false,
        ),
      },
    );
  }
}

class CalculatorRouteArgs {
  const CalculatorRouteArgs({
    this.fixedRateId,
    this.fixedRateCode,
    this.fromCode,
    this.toCode,
    this.closeAppOnBack = false,
  });

  final String? fixedRateId;
  final String? fixedRateCode;
  final String? fromCode;
  final String? toCode;
  final bool closeAppOnBack;
}

class HomeRouteArgs {
  const HomeRouteArgs({this.skipPinnedRedirect = false});

  final bool skipPinnedRedirect;
}
