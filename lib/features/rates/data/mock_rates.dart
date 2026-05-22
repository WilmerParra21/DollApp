import '../models/exchange_rate.dart';

class MockRates {
  const MockRates._();

  static final DateTime lastUpdated = DateTime(2026, 5, 18, 8, 45);

  static final List<ExchangeRate> rates = [
    ExchangeRate(
      id: 'USD',
      code: 'USD',
      name: 'Dólar BCV',
      value: 98.45,
      displayValue: 98.45,
      symbol: r'$',
      moneyType: 'VES',
      updatedAt: lastUpdated,
      isOfficial: true,
      changePercent: -0.18,
      sparklineValues: const [98.80, 98.70, 98.62, 98.71, 98.52, 98.45],
      historyPoints: const [],
    ),
    ExchangeRate(
      id: 'EUR',
      code: 'EUR',
      name: 'Euro BCV',
      value: 107.80,
      displayValue: 107.80,
      symbol: '€',
      moneyType: 'VES',
      updatedAt: lastUpdated,
      isOfficial: true,
      changePercent: 0.12,
      sparklineValues: const [107.20, 107.35, 107.40, 107.62, 107.70, 107.80],
      historyPoints: const [],
    ),
    ExchangeRate(
      id: 'COP',
      code: 'COP',
      name: 'Peso colombiano',
      value: 0.024,
      displayValue: 0.024,
      symbol: r'$',
      moneyType: 'COP',
      updatedAt: lastUpdated,
      isOfficial: true,
      changePercent: 0.08,
      sparklineValues: const [0.0237, 0.0238, 0.0239, 0.0240, 0.0241, 0.024],
      historyPoints: const [],
    ),
  ];

  static ExchangeRate byCode(String code) {
    return rates.firstWhere((rate) => rate.code == code);
  }

  static ExchangeRate? tryByCode(String code) {
    for (final rate in rates) {
      if (rate.code == code) {
        return rate;
      }
    }
    return null;
  }
}
