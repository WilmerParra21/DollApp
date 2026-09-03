import 'package:dollapp/core/utils/currency_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decimal truncates copied results without rounding', () {
    expect(CurrencyFormatter.decimal(0.865), '0,86');
  });

  test('decimal keeps two decimals and thousands grouping', () {
    expect(CurrencyFormatter.decimal(1234.5678), '1.234,56');
  });

  test(
    'rate uses two decimals by default and preserves full precision on demand',
    () {
      expect(CurrencyFormatter.moneyRate(485.2345, 'VES'), 'Bs. 485,23');
      expect(
        CurrencyFormatter.moneyRate(485.2345, 'VES', fullPrecision: true),
        'Bs. 485,2345',
      );
    },
  );

  test('full precision supports up to eight decimals', () {
    expect(CurrencyFormatter.fullPrecision(0.12345678), '0,12345678');
  });
}
