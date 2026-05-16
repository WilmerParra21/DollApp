import '../models/exchange_rate.dart';
import '../models/exchange_rate_snapshot.dart';

/// Normaliza códigos de moneda conocidos como alias (p. ej. BS → VES).
String canonicalCurrencyCode(String raw) {
  final upper = raw.trim().toUpperCase();
  if (upper == 'BS') return 'VES';
  return upper;
}

/// Interpretación de una fila [ExchangeRate]: [anchor] cotiza contra [counter]
/// con **1 anchor = unitsPerAnchor en counter**.
class ParsedQuote {
  ParsedQuote({
    required this.row,
    required this.anchor,
    required this.counter,
    required this.unitsPerAnchor,
  });

  final ExchangeRate row;
  final String anchor;
  final String counter;
  final double unitsPerAnchor;

  double convert(double amount, String from, String to) {
    final f = canonicalCurrencyCode(from);
    final t = canonicalCurrencyCode(to);
    if (f == t) return amount;

    final a = anchor;
    final c = counter;

    if (f == a && t == c) return amount * unitsPerAnchor;
    if (f == c && t == a) return amount / unitsPerAnchor;

    throw ArgumentError('Conversion fuera del par ${_pairKey(a, c)}: $from → $to');
  }
}

String _pairKey(String a, String b) =>
    '${canonicalCurrencyCode(a)}/${canonicalCurrencyCode(b)}';

ParsedQuote? tryParseQuote(ExchangeRate rate) {
  final qty = rate.displayValue ?? rate.value;
  if (!qty.isFinite || qty <= 0) return null;

  final rawAnchor = rate.conversionCode?.trim() ?? rate.displayCurrencyCode?.trim();
  final rawCounter = rate.moneyType?.trim();
  final anchor = rawAnchor != null && rawAnchor.isNotEmpty
      ? canonicalCurrencyCode(rawAnchor)
      : canonicalCurrencyCode(rate.code);
  final counter = rawCounter != null && rawCounter.isNotEmpty
      ? canonicalCurrencyCode(rawCounter)
      : canonicalCurrencyCode(rate.code);

  if (anchor == counter) {
    // Evitar tasas inválidas donde la moneda base y la moneda contra son la misma.
    return null;
  }

  return ParsedQuote(
    row: rate,
    anchor: anchor,
    counter: counter,
    unitsPerAnchor: qty,
  );
}

ParsedQuote? findQuoteForCurrencyPair(
  ExchangeRateSnapshot snapshot,
  String a,
  String b,
) {
  final ca = canonicalCurrencyCode(a);
  final cb = canonicalCurrencyCode(b);
  for (final rate in snapshot.rates) {
    final p = tryParseQuote(rate);
    if (p == null) continue;
    if ((ca == p.anchor && cb == p.counter) ||
        (cb == p.anchor && ca == p.counter)) {
      return p;
    }
  }
  return null;
}
