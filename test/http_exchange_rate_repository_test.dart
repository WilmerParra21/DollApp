import 'dart:convert';

import 'package:dollapp/features/rates/data/http_exchange_rate_repository.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString: '''
SUPABASE_PROJECT_REF=test-project
SUPABASE_ANON_KEY=test-key
''',
    );
  });

  tearDown(dotenv.clean);

  test('parses nombre, moneda, monto and conver from the API format', () async {
    final repository = HttpExchangeRateRepository(
      client: MockClient((request) async {
        expect(request.url.host, 'test-project.supabase.co');
        if (request.url.path.endsWith('/get-tasas-historico')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'Promedio USDT': [
                  {'fecha': '2026-04-29', 'monto': 643.42, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 641.15, 'moneda': 'Bs'},
                  {'fecha': '2026-04-27', 'monto': 639.50, 'moneda': 'Bs'},
                ],
                'Dólar BCV': [
                  {'fecha': '2026-04-29', 'monto': 485.22, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 484.10, 'moneda': 'Bs'},
                  {'fecha': '2026-04-27', 'monto': 483.95, 'moneda': 'Bs'},
                ],
                'Peso Colombiano': [
                  {'fecha': '2026-04-29', 'monto': 3633.76, 'moneda': 'COP'},
                  {'fecha': '2026-04-28', 'monto': 3630, 'moneda': 'COP'},
                  {'fecha': '2026-04-27', 'monto': 3628.5, 'moneda': 'COP'},
                ],
                'Euro BCV': [
                  {'fecha': '2026-04-29', 'monto': 569.29, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 567.80, 'moneda': 'Bs'},
                  {'fecha': '2026-04-27', 'monto': 566.12, 'moneda': 'Bs'},
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'fecha': '2026-04-29',
              'tasas': [
                {
                  'nombre': 'Dolar BCV',
                  'moneda': 'Bs',
                  'conver': 'usd',
                  'monto': '485,22',
                  'fechaActualizacion': '28/04/2026',
                },
                {
                  'nombre': 'Euro BCV',
                  'moneda': 'Bs',
                  'conver': 'eur',
                  'monto': '569,29',
                  'fechaActualizacion': '28/04/2026',
                },
                {
                  'nombre': 'Peso Colombiano',
                  'moneda': 'COP',
                  'conver': 'usd',
                  'monto': '3633.76',
                  'create_date': '28/04/2026',
                },
                {
                  'nombre': 'Promedio USDT',
                  'moneda': 'Bs',
                  'monto': '643,42',
                  'conver': 'usd',
                  'fechaActualizacion': '28/04/2026',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final snapshot = await repository.getRates(forceRefresh: true);
    final usd = snapshot.byCode('USD');
    final eur = snapshot.byCode('EUR');
    final cop = snapshot.byCode('COP');
    final usdt = snapshot.byCode('USDT');

    expect(usd.name, 'Dolar BCV');
    expect(usd.value, 485.22);
    expect(usd.displayCurrencyCode, 'Bs');
    expect(usd.conversionCode, 'USD');
    expect(usd.sparklineValues, [483.95, 484.10, 485.22]);
    expect(usd.changePercent, closeTo(0.231, 0.001));

    expect(eur.name, 'Euro BCV');
    expect(eur.value, 569.29);
    expect(eur.displayCurrencyCode, 'Bs');
    expect(eur.conversionCode, 'EUR');
    expect(eur.sparklineValues, [566.12, 567.80, 569.29]);
    expect(eur.changePercent, closeTo(0.262, 0.001));

    expect(cop.name, 'Peso Colombiano');
    expect(cop.value, 3633.76);
    expect(cop.displayValue, 3633.76);
    expect(cop.displayCurrencyCode, 'COP');
    expect(cop.conversionCode, 'USD');
    expect(cop.sourceUpdatedAtLabel, '28/04/2026');
    expect(cop.sparklineValues, [3628.50, 3630, 3633.76]);
    expect(cop.changePercent, closeTo(0.104, 0.001));

    expect(usdt.name, 'Promedio USDT');
    expect(usdt.value, 643.42);
    expect(usdt.displayValue, 643.42);
    expect(usdt.displayCurrencyCode, 'Bs');
    expect(usdt.conversionCode, 'USD');
    expect(usdt.sourceUpdatedAtLabel, '28/04/2026');
    expect(usdt.sparklineValues, [639.50, 641.15, 643.42]);
    expect(usdt.changePercent, closeTo(0.354, 0.001));
  });

  test(
    'keeps previous rate when API returns 0,00 and preserves last update date label',
    () async {
      var rateRequestCount = 0;
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/get-tasas-historico')) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'Promedio USDT': [
                    {'fecha': '2026-04-29', 'monto': 643.42, 'moneda': 'Bs'},
                    {'fecha': '2026-04-28', 'monto': 641.15, 'moneda': 'Bs'},
                  ],
                  'Dólar BCV': [
                    {'fecha': '2026-04-29', 'monto': 485.22, 'moneda': 'Bs'},
                    {'fecha': '2026-04-28', 'monto': 484.10, 'moneda': 'Bs'},
                  ],
                }),
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.path.endsWith('/functions/v1/tasas-divisas')) {
            rateRequestCount += 1;
            if (rateRequestCount == 1) {
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'fecha': '2026-04-29',
                    'tasas': [
                      {
                        'nombre': 'Dolar BCV',
                        'moneda': 'Bs',
                        'conver': 'usd',
                        'monto': '485,22',
                        'fechaActualizacion': '28/04/2026',
                      },
                    ],
                  }),
                ),
                200,
                headers: {'content-type': 'application/json'},
              );
            }

            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'fecha': '2026-04-30',
                  'tasas': [
                    {
                      'nombre': 'Dolar BCV',
                      'moneda': 'Bs',
                      'conver': 'usd',
                      'monto': '0,00',
                      'fechaActualizacion': '29/04/2026',
                    },
                  ],
                }),
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response('Unexpected request', 500);
        }),
      );

      final firstSnapshot = await repository.getRates(forceRefresh: true);
      final usdFirst = firstSnapshot.byCode('USD');
      expect(usdFirst.value, 485.22);
      expect(usdFirst.updatedAt, DateTime.parse('2026-04-29T00:00:00.000'));
      expect(usdFirst.sourceUpdatedAtLabel, '28/04/2026');

      final secondSnapshot = await repository.getRates(forceRefresh: true);
      final usdSecond = secondSnapshot.byCode('USD');

      expect(usdSecond.keptPreviousValue, isTrue);
      expect(usdSecond.value, 485.22);
      expect(usdSecond.updatedAt, usdFirst.updatedAt);
      expect(usdSecond.sourceUpdatedAtLabel, '28/04/2026');
    },
  );

  test(
    'does not show mock rates when the API fails without saved data',
    () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          return http.Response('Server error', 500);
        }),
      );

      await expectLater(
        repository.getRates(forceRefresh: true),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
