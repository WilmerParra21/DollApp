import 'dart:convert';

import 'package:dollapp/app/doll_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'exchange_rate_snapshot_v5': jsonEncode(_savedRealRatesSnapshot),
    });
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('DollApp renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DollApp());
    await _pumpApp(tester);

    expect(find.text('DollApp'), findsOneWidget);
    expect(find.text('Tus tasas al día'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.textContaining('Actualizado:'), findsOneWidget);
  });

  testWidgets('Home adapts to common Android screen sizes', (
    WidgetTester tester,
  ) async {
    for (final size in _androidViewports) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _setViewport(tester, size);
      await tester.pumpWidget(const DollApp());
      await _pumpApp(tester);

      expect(find.text('DollApp'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
    }
  });

  testWidgets('Calculator adapts to common Android screen sizes', (
    WidgetTester tester,
  ) async {
    for (final size in _androidViewports) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _setViewport(tester, size);
      await tester.pumpWidget(const DollApp());
      await _pumpApp(tester);

      final calculateButton = find.text('Calcular').first;
      await tester.ensureVisible(calculateButton);
      await tester.tap(calculateButton);
      await _pumpApp(tester);

      expect(find.byTooltip('Volver'), findsOneWidget);
      expect(find.text('Monto'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
    }
  });
}

final _savedRealRatesSnapshot = {
  'updatedAt': '2026-04-29T00:00:00.000',
  'usedFallback': false,
  'rates': [
    {
      'code': 'USD',
      'name': 'Dolar BCV',
      'source': 'Banco Central de Venezuela',
      'value': 485.23,
      'symbol': r'$',
      'updatedAt': '2026-04-29T00:00:00.000',
      'isOfficial': true,
      'changePercent': 0,
      'sparklineValues': <double>[],
      'historyPoints': <Map<String, Object>>[],
      'moneyType': null,
      'sourceUpdatedAtLabel': '28/04/2026',
      'keptPreviousValue': false,
      'displayValue': 485.23,
      'displayCurrencyCode': 'Bs',
      'conversionCode': 'USD',
    },
    {
      'code': 'EUR',
      'name': 'Euro BCV',
      'source': 'Banco Central de Venezuela',
      'value': 569.30,
      'symbol': 'EUR',
      'updatedAt': '2026-04-29T00:00:00.000',
      'isOfficial': true,
      'changePercent': 0,
      'sparklineValues': <double>[],
      'historyPoints': <Map<String, Object>>[],
      'moneyType': null,
      'sourceUpdatedAtLabel': '28/04/2026',
      'keptPreviousValue': false,
      'displayValue': 569.30,
      'displayCurrencyCode': 'Bs',
      'conversionCode': 'EUR',
    },
    {
      'code': 'COP',
      'name': 'COP -> USD',
      'source': 'TRM Colombia',
      'value': 3633.76,
      'symbol': r'$',
      'updatedAt': '2026-04-29T00:00:00.000',
      'isOfficial': true,
      'changePercent': 0,
      'sparklineValues': <double>[],
      'historyPoints': <Map<String, Object>>[],
      'moneyType': null,
      'sourceUpdatedAtLabel': '29/04/2026',
      'keptPreviousValue': false,
      'displayValue': 3633.76,
      'displayCurrencyCode': 'COP',
      'conversionCode': 'USD',
    },
  ],
};

Future<void> _pumpApp(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _androidViewports = <Size>[
  Size(360, 640),
  Size(393, 851),
  Size(412, 915),
  Size(600, 960),
];

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
