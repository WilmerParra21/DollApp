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
  static String moneyRate(
    double value,
    String code, {
    bool fullPrecision = false,
  }) {
    final normalizedCode = code.toUpperCase();
    final formattedValue = rateValue(value, fullPrecision: fullPrecision);

    return switch (normalizedCode) {
      'VES' || 'Bs' || 'BS.' => 'Bs. $formattedValue',
      'USD' || 'usd' => '\$ $formattedValue',
      'EUR' || 'eur' => '€ $formattedValue',
      'COP' || 'cop' => 'COP $formattedValue',
      _ => '$normalizedCode $formattedValue',
    };
  }

  static String rateValue(double value, {bool fullPrecision = false}) {
    final decimals = fullPrecision ? _precisionDigits(value) : 2;
    return formatNumber(value, decimals);
  }

  static String bolivarScaled(double value, int decimals) =>
      'Bs. ${formatNumber(value, decimals)}';

  /// Formats a value for copying with two decimals without rounding.
  ///
  /// The clipboard must truncate values such as `0.865` to `0.86` instead of
  /// changing them to `0.87`.
  static String decimal(double value) {
    if (!value.isFinite) return value.toString();

    final truncated = (value.abs() * 100).truncateToDouble() / 100 * value.sign;
    return formatNumber(truncated, 2);
  }

  static String fullPrecision(double value) {
    if (!value.isFinite) return value.toString();

    final fixed = value.toStringAsFixed(8);
    final decimalPart = fixed.split('.').last.replaceFirst(RegExp(r'0+$'), '');
    final decimals = decimalPart.isEmpty ? 2 : decimalPart.length.clamp(2, 8);
    return formatNumber(value, decimals);
  }

  static String percent(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  static int _precisionDigits(double value) {
    if (!value.isFinite || value == 0) return 2;
    final fixed = value.abs().toStringAsFixed(8);
    final decimalPart = fixed.split('.').last.replaceFirst(RegExp(r'0+$'), '');
    return decimalPart.isEmpty ? 2 : decimalPart.length.clamp(2, 8);
  }

  static String formatNumber(double value, [int decimals = 2]) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final integer = parts.first;
    final decimalDigits = parts.last;
    return '${_groupInteger(integer)},$decimalDigits';
  }

  static String _groupInteger(String integer) {
    final buffer = StringBuffer();
    for (var i = 0; i < integer.length; i++) {
      final positionFromEnd = integer.length - i;
      buffer.write(integer[i]);
      if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }
}
