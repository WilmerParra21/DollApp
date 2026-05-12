class ExchangeRate {
  const ExchangeRate({
    required this.code,
    required this.name,
    required this.source,
    required this.value,
    required this.symbol,
    required this.updatedAt,
    required this.isOfficial,
    required this.changePercent,
    required this.sparklineValues,
    required this.historyPoints,
    this.moneyType,
    this.sourceUpdatedAtLabel,
    this.keptPreviousValue = false,
    this.displayValue,
    this.displayCurrencyCode,
    this.conversionCode,
  });

  final String code;
  final String name;
  final String source;
  final double value;
  final String symbol;
  final DateTime updatedAt;
  final bool isOfficial;
  final double changePercent;
  final List<double> sparklineValues;
  final List<ExchangeRateHistoryPoint> historyPoints;
  final String? moneyType;
  final String? sourceUpdatedAtLabel;
  final bool keptPreviousValue;
  final double? displayValue;
  final String? displayCurrencyCode;
  final String? conversionCode;

  bool get isUp => changePercent >= 0;
  bool get hasTrend => sparklineValues.length >= 2 && changePercent.abs() > 0.01;

  ExchangeRate copyWith({
    double? changePercent,
    List<double>? sparklineValues,
    List<ExchangeRateHistoryPoint>? historyPoints,
    bool? keptPreviousValue,
  }) {
    return ExchangeRate(
      code: code,
      name: name,
      source: source,
      value: value,
      symbol: symbol,
      updatedAt: updatedAt,
      isOfficial: isOfficial,
      changePercent: changePercent ?? this.changePercent,
      sparklineValues: sparklineValues ?? this.sparklineValues,
      historyPoints: historyPoints ?? this.historyPoints,
      moneyType: moneyType,
      sourceUpdatedAtLabel: sourceUpdatedAtLabel,
      keptPreviousValue: keptPreviousValue ?? this.keptPreviousValue,
      displayValue: displayValue,
      displayCurrencyCode: displayCurrencyCode,
      conversionCode: conversionCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'source': source,
      'value': value,
      'symbol': symbol,
      'updatedAt': updatedAt.toIso8601String(),
      'isOfficial': isOfficial,
      'changePercent': changePercent,
      'sparklineValues': sparklineValues,
      'historyPoints': historyPoints.map((point) => point.toJson()).toList(),
      'moneyType': moneyType,
      'sourceUpdatedAtLabel': sourceUpdatedAtLabel,
      'keptPreviousValue': keptPreviousValue,
      'displayValue': displayValue,
      'displayCurrencyCode': displayCurrencyCode,
      'conversionCode': conversionCode,
    };
  }

  factory ExchangeRate.fromJson(Map<String, dynamic> json) {
    return ExchangeRate(
      code: json['code'] as String,
      name: json['name'] as String,
      source: json['source'] as String,
      value: (json['value'] as num).toDouble(),
      symbol: json['symbol'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isOfficial: json['isOfficial'] as bool,
      changePercent: (json['changePercent'] as num).toDouble(),
      sparklineValues: (json['sparklineValues'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList(),
      historyPoints: (json['historyPoints'] as List<dynamic>? ?? const [])
          .map(
            (point) => ExchangeRateHistoryPoint.fromJson(
              point as Map<String, dynamic>,
            ),
          )
          .toList(),
      moneyType: json['moneyType'] as String?,
      sourceUpdatedAtLabel: json['sourceUpdatedAtLabel'] as String?,
      keptPreviousValue: json['keptPreviousValue'] as bool? ?? false,
      displayValue: (json['displayValue'] as num?)?.toDouble(),
      displayCurrencyCode: json['displayCurrencyCode'] as String?,
      conversionCode: json['conversionCode'] as String?,
    );
  }
}

class ExchangeRateHistoryPoint {
  const ExchangeRateHistoryPoint({
    required this.date,
    required this.value,
    required this.currencyCode,
  });

  final DateTime date;
  final double value;
  final String currencyCode;

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'value': value,
      'currencyCode': currencyCode,
    };
  }

  factory ExchangeRateHistoryPoint.fromJson(Map<String, dynamic> json) {
    return ExchangeRateHistoryPoint(
      date: DateTime.parse(json['date'] as String),
      value: (json['value'] as num).toDouble(),
      currencyCode: json['currencyCode'] as String,
    );
  }
}
