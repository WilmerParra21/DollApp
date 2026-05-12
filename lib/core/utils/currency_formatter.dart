class CurrencyFormatter {
  const CurrencyFormatter._();

  static String bolivar(double value) => 'Bs. ${_formatNumber(value)}';

  static String money(double value, String code) {
    final normalizedCode = code.toUpperCase();
    return switch (normalizedCode) {
      'VES' || 'Bs' || 'BS.' => bolivar(value),
      'USD' || 'usd' => '\$ ${_formatNumber(value)}',
      'EUR' || 'eur' => '€ ${_formatNumber(value)}',
      'COP' || 'cop' => 'COP ${_formatNumber(value)}',
      _ => '$normalizedCode ${_formatNumber(value)}',
    };
  }

  /// Cotizaciones muy pequeñas (reciprocas) para no ver `0,00` con sólo dos decimales.
  static String moneyRate(double value, String code) {
    final normalizedCode = code.toUpperCase();
    final decimals = _fractionDigitsForRate(value);

    return switch (normalizedCode) {
      'VES' || 'Bs' || 'BS.' => bolivarScaled(value, decimals),
      'USD' || 'usd' => '\$ ${_formatNumber(value, decimals)}',
      'EUR' || 'eur' => '€ ${_formatNumber(value, decimals)}',
      'COP' || 'cop' => 'COP ${_formatNumber(value, decimals)}',
      _ => '$normalizedCode ${_formatNumber(value, decimals)}',
    };
  }

  static String bolivarScaled(double value, int decimals) =>
      'Bs. ${_formatNumber(value, decimals)}';

  static String decimal(double value) => _formatNumber(value);

  static String percent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  static int _fractionDigitsForRate(double value) {
    final a = value.abs();
    if (!a.isFinite || a == 0) return 2;
    if (a >= 1) return 2;
    if (a >= 0.01) return 4;
    return 6;
  }

  static String _formatNumber(double value, [int decimals = 2]) {
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
