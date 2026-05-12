import 'exchange_rate.dart';

class ExchangeRateSnapshot {
  const ExchangeRateSnapshot({
    required this.rates,
    required this.updatedAt,
    required this.usedFallback,
  });

  final List<ExchangeRate> rates;
  final DateTime updatedAt;
  final bool usedFallback;

  ExchangeRate byCode(String code) {
    return rates.firstWhere((rate) => rate.code == code);
  }

  ExchangeRate? tryByCode(String code) {
    for (final rate in rates) {
      if (rate.code == code) {
        return rate;
      }
    }
    return null;
  }

  ExchangeRateSnapshot copyWith({
    List<ExchangeRate>? rates,
    DateTime? updatedAt,
    bool? usedFallback,
  }) {
    return ExchangeRateSnapshot(
      rates: rates ?? this.rates,
      updatedAt: updatedAt ?? this.updatedAt,
      usedFallback: usedFallback ?? this.usedFallback,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rates': rates.map((rate) => rate.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
      'usedFallback': usedFallback,
    };
  }

  factory ExchangeRateSnapshot.fromJson(Map<String, dynamic> json) {
    return ExchangeRateSnapshot(
      rates: (json['rates'] as List<dynamic>)
          .map((rate) => ExchangeRate.fromJson(rate as Map<String, dynamic>))
          .toList(),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      usedFallback: json['usedFallback'] as bool? ?? false,
    );
  }
}
