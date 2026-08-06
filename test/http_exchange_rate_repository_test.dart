import 'dart:convert';

import 'package:dollapp/features/rates/data/http_exchange_rate_repository.dart';
import 'package:dollapp/features/rates/models/exchange_rate.dart';
import 'package:dollapp/features/rates/models/exchange_rate_snapshot.dart';
import 'package:dollapp/features/rates/utils/exchange_pair_quote.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dbPath = await getDatabasesPath();
    await deleteDatabase(path.join(dbPath, 'dollapp_snapshot.db'));
    dotenv.loadFromString(
      envString: '''
SUPABASE_PROJECT_REF=test-project
SUPABASE_ANON_KEY=test-key
''',
    );
  });

  tearDown(dotenv.clean);

  ExchangeRate rowByName(ExchangeRateSnapshot snapshot, String name) =>
      snapshot.rates.firstWhere((rate) => rate.name == name);

  test('parses nombre, moneda, monto and conver from the API format', () async {
    final repository = HttpExchangeRateRepository(
      client: MockClient((request) async {
        expect(request.url.host, 'test-project.supabase.co');
        if (request.url.path.endsWith('/get-tasas-historico')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
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
                'Promedio USDT': [
                  {'fecha': '2026-04-29', 'monto': 643.42, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 641.15, 'moneda': 'Bs'},
                  {'fecha': '2026-04-27', 'monto': 639.50, 'moneda': 'Bs'},
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
                  'conver': 'usdt',
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
    final usd = rowByName(snapshot, 'Dolar BCV');
    final eur = rowByName(snapshot, 'Euro BCV');
    final cop = rowByName(snapshot, 'Peso Colombiano');
    final usdt = rowByName(snapshot, 'Promedio USDT');

    expect(usd.name, 'Dolar BCV');
    expect(usd.id, 'USD-USD-Dolar BCV-BS');
    expect(usd.value, 485.22);
    expect(usd.moneyType, 'BS');
    expect(usd.conversionCode, 'USD');
    expect(usd.sparklineValues, [483.95, 484.10, 485.22]);
    expect(usd.changePercent, closeTo(0.231, 0.001));

    expect(eur.name, 'Euro BCV');
    expect(eur.value, 569.29);
    expect(eur.moneyType, 'BS');
    expect(eur.conversionCode, 'EUR');
    expect(eur.sparklineValues, [566.12, 567.80, 569.29]);
    expect(eur.changePercent, closeTo(0.262, 0.001));

    expect(cop.name, 'Peso Colombiano');
    expect(cop.id, 'USD-USD-Peso Colombiano-COP');
    expect(cop.value, 3633.76);
    expect(cop.displayValue, 3633.76);
    expect(cop.moneyType, 'COP');
    expect(cop.conversionCode, 'USD');
    expect(cop.sourceUpdatedAtLabel, '28/04/2026');
    expect(cop.sparklineValues, [3628.50, 3630, 3633.76]);
    expect(cop.changePercent, closeTo(0.104, 0.001));

    expect(usdt.name, 'Promedio USDT');
    expect(usdt.value, 643.42);
    expect(usdt.displayValue, 643.42);
    expect(usdt.moneyType, 'BS');
    expect(usdt.conversionCode, 'USDT');
    expect(usdt.sourceUpdatedAtLabel, '28/04/2026');
expect(usdt.sparklineValues, [639.50, 641.15, 643.42]);
    expect(usdt.changePercent, closeTo(0.354, 0.001));
  });

  test('hides identical duplicate API entries when the same rate appears twice', () async {
    final repository = HttpExchangeRateRepository(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/get-tasas-historico')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'Dólar BCV': [
                  {'fecha': '2026-04-29', 'monto': 485.22, 'moneda': 'Bs'},
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
      }),
    );

    final snapshot = await repository.getRates(forceRefresh: true);
    final usdRates = snapshot.rates.where((rate) => rate.code == 'USD');

    expect(usdRates.length, 1);
    expect(snapshot.rates.map((rate) => rate.id).toSet().length,
        snapshot.rates.length);
  });

  test('marks a rate as favorite and preserves it in local snapshot', () async {
    final repository = HttpExchangeRateRepository(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/get-tasas-historico')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'Dólar BCV': [
                  {'fecha': '2026-04-29', 'monto': 485.22, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 484.10, 'moneda': 'Bs'},
                ],
                'Euro BCV': [
                  {'fecha': '2026-04-29', 'monto': 569.29, 'moneda': 'Bs'},
                  {'fecha': '2026-04-28', 'monto': 567.80, 'moneda': 'Bs'},
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
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await repository.getRates(forceRefresh: true);
    final firstSnapshot = await repository.loadSavedSnapshot();
    expect(firstSnapshot, isNotNull);

    await repository.setFavorite(rowByName(firstSnapshot!, 'Euro BCV').id, true);

    final snapshot = await repository.loadSavedSnapshot();
    expect(snapshot, isNotNull);
    expect(snapshot!.rates.first.name, 'Euro BCV');
    expect(rowByName(snapshot, 'Euro BCV').isFavorite, isTrue);
  });

  test(
    'preserves favorites when the API order changes even if the generated id changes',
    () async {
      var rateRequestCount = 0;
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/get-tasas-historico')) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'DÃ³lar BCV': [
                    {'fecha': '2026-04-29', 'monto': 485.22, 'moneda': 'Bs'},
                  ],
                  'Euro BCV': [
                    {'fecha': '2026-04-29', 'monto': 569.29, 'moneda': 'Bs'},
                  ],
                }),
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          rateRequestCount += 1;
          final tasas = rateRequestCount == 1
              ? [
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
                ]
              : [
                  {
                    'nombre': 'Euro BCV',
                    'moneda': 'Bs',
                    'conver': 'eur',
                    'monto': '569,29',
                    'fechaActualizacion': '28/04/2026',
                  },
                  {
                    'nombre': 'Dolar BCV',
                    'moneda': 'Bs',
                    'conver': 'usd',
                    'monto': '485,22',
                    'fechaActualizacion': '28/04/2026',
                  },
                ];

          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'fecha': '2026-04-29',
                'tasas': tasas,
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final initialSnapshot = await repository.getRates(forceRefresh: true);
      final eurId = rowByName(initialSnapshot, 'Euro BCV').id;

      await repository.setFavorite(eurId, true);

final refreshedSnapshot = await repository.getRates(forceRefresh: true);
       expect(rowByName(refreshedSnapshot, 'Euro BCV').id, eurId);
       expect(rowByName(refreshedSnapshot, 'Euro BCV').isFavorite, isTrue);
      expect(refreshedSnapshot.rates.first.name, 'Euro BCV');
    },
  );

  test(
    'keeps EUR to VES and EUR to USD as different pairs without collisions',
    () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/get-tasas-historico')) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'Euro BCV': [
                    {'fecha': '2026-05-15', 'monto': 48.30, 'moneda': 'Bs'},
                  ],
                  'Euro a Dolar': [
                    {'fecha': '2026-05-15', 'monto': 1.08, 'moneda': 'USD'},
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
                'fecha': '2026-05-15',
                'tasas': [
                  {
                    'nombre': 'Euro BCV',
                    'moneda': 'Bs',
                    'conver': 'eur',
                    'monto': '48,30',
                    'fechaActualizacion': '15/05/2026',
                  },
                  {
                    'nombre': 'Euro a Dolar',
                    'moneda': 'USD',
                    'conver': 'eur',
                    'monto': '1,08',
                    'fechaActualizacion': '15/05/2026',
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

      final eurToVes = findQuoteForCurrencyPair(snapshot, 'EUR', 'VES');
      final eurToUsd = findQuoteForCurrencyPair(snapshot, 'EUR', 'USD');

      expect(snapshot.rates.length, 2);
      expect(eurToVes, isNotNull);
      expect(eurToUsd, isNotNull);
      expect(eurToVes!.row.id, isNot(eurToUsd!.row.id));
      expect(eurToVes.convert(1, 'EUR', 'VES'), closeTo(48.30, 0.001));
      expect(eurToUsd.convert(1, 'EUR', 'USD'), closeTo(1.08, 0.001));
    },
  );

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

  group('fetchHistoricalRate', () {
    test('returns the historical rate value on success', () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/functions/v1/tasas-historicos');

          final body = jsonDecode(request.body);
          expect(body['nombre'], 'Dolar BCV');
          expect(body['fecha'], '2024-05-15');

          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'fecha': '2024-05-15',
                'info': 'datos_desde_db',
                'tasa': {
                  'nombre': 'Dolar BCV',
                  'moneda': 'Bs',
                  'conver': 'usd',
                  'simbolo': 'Bs',
                  'monto': '36,58',
                  'fechaActualizacion': '15/05/2024',
                },
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final value = await repository.fetchHistoricalRate(
        nombre: 'Dolar BCV',
        fecha: DateTime(2024, 5, 15),
      );

      expect(value, closeTo(36.58, 0.001));
    });

    test('throws FormatException on 400 with error message', () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': "El nombre 'Dólar Desconocido' no es válido.",
              }),
            ),
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        repository.fetchHistoricalRate(
          nombre: 'Dólar Desconocido',
          fecha: DateTime(2024, 5, 15),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            "El nombre 'Dólar Desconocido' no es válido.",
          ),
        ),
      );
    });

    test('throws FormatException on 404 with error message', () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': "No se encontró tasa para 'Dólar BCV' en la fecha 2020-01-01.",
              }),
            ),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        repository.fetchHistoricalRate(
          nombre: 'Dólar BCV',
          fecha: DateTime(2020, 1, 1),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            "No se encontró tasa para 'Dólar BCV' en la fecha 2020-01-01.",
          ),
        ),
      );
    });

    test('throws FormatException when response has no tasa field', () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'fecha': '2024-05-15',
                'info': 'datos_desde_db',
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        repository.fetchHistoricalRate(
          nombre: 'Dolar BCV',
          fecha: DateTime(2024, 5, 15),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'No se encontró la tasa en la respuesta',
          ),
        ),
      );
    });

    test('throws FormatException on server error without error body', () async {
      final repository = HttpExchangeRateRepository(
        client: MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        }),
      );

      await expectLater(
        repository.fetchHistoricalRate(
          nombre: 'Dolar BCV',
          fecha: DateTime(2024, 5, 15),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Error al consultar tasa histórica (500)',
          ),
        ),
      );
    });
  });
}
