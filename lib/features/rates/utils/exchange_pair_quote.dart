import '../models/exchange_rate.dart';
import '../models/exchange_rate_snapshot.dart';

/// Normaliza códigos de moneda conocidos como alias (p. ej. BS → VES).
String canonicalCurrencyCode(String raw) {
  final t = raw.trim().toUpperCase();
  if (t == 'BS' || t == 'BS.') return 'VES';
  return t;
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

  final conv = rate.conversionCode?.trim();
  if (conv != null && conv.isNotEmpty) {
    return ParsedQuote(
      row: rate,
      anchor: canonicalCurrencyCode(conv),
      counter: canonicalCurrencyCode(
        rate.displayCurrencyCode ?? rate.code,
      ),
      unitsPerAnchor: qty,
    );
  }

  return ParsedQuote(
    row: rate,
    anchor: canonicalCurrencyCode(rate.code),
    counter: canonicalCurrencyCode(rate.displayCurrencyCode ?? 'VES'),
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
