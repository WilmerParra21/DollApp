import 'package:flutter_test/flutter_test.dart';

import 'package:dollapp/core/utils/currency_formatter.dart';

void main() {
  test('decimal truncates copied results without rounding', () {
    expect(CurrencyFormatter.decimal(0.865), '0,86');
  });

  test('decimal keeps two decimals and thousands grouping', () {
    expect(CurrencyFormatter.decimal(1234.5678), '1.234,56');
  });
}
