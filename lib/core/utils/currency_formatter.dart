class CurrencyFormatter {
  const CurrencyFormatter._();

  static String bolivar(double value) => 'Bs. ${formatNumber(value)}';

  static String money(double value, String code) {
    final normalizedCode = code.toUpperCase();
    return switch (normalizedCode) {
      'VES' || 'Bs' || 'BS.' => bolivar(value),
      'USD' || 'usd' => '\$ ${formatNumber(value)}',
      'EUR' || 'eur' => '€ ${formatNumber(value)}',
      'COP' || 'cop' => 'COP ${formatNumber(value)}',
      _ => '$normalizedCode ${formatNumber(value)}',
    };
  }

  static String moneyWithCode(double value, String code) {
    final normalizedCode = code.toUpperCase();
    return '$normalizedCode ${formatNumber(value)}';
  }

  /// Cotizaciones muy pequeñas (reciprocas) para no ver `0,00` con sólo dos decimales.
  static String moneyRate(double value, String code) {
    final normalizedCode = code.toUpperCase();
    final decimals = _fractionDigitsForRate(value);

    return switch (normalizedCode) {
      'VES' || 'Bs' || 'BS.' => bolivarScaled(value, decimals),
      'USD' || 'usd' => '\$ ${formatNumber(value, decimals)}',
      'EUR' || 'eur' => '€ ${formatNumber(value, decimals)}',
      'COP' || 'cop' => 'COP ${formatNumber(value, decimals)}',
      _ => '$normalizedCode ${formatNumber(value, decimals)}',
    };
  }

  static String bolivarScaled(double value, int decimals) =>
      'Bs. ${formatNumber(value, decimals)}';

  static String decimal(double value) => formatNumber(value);

  static String percent(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  static int _fractionDigitsForRate(double value) {
    final a = value.abs();
    if (!a.isFinite || a == 0) return 2;
    if (a >= 1) return 2;
    if (a >= 0.01) return 4;
    return 6;
  }

  static String formatNumber(double value, [int decimals = 2]) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final integer = parts.first;
    final decimalDigits = parts.last;
    final buffer = StringBuffer();

    for (var i = 0; i < integer.length; i++) {
      final positionFromEnd = integer.length - i;
      buffer.write(integer[i]);
      if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${buffer.toString()},$decimalDigits';
  }
}
