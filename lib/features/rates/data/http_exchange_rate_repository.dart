import 'dart:convert';

import 'package:dollapp/core/config/app_config.dart';
import 'package:dollapp/core/models/audit_log.dart';
import 'package:dollapp/core/services/audit_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/exchange_rate.dart';
import '../models/exchange_rate_snapshot.dart';
import 'exchange_rate_repository.dart';
import 'mock_rates.dart';

class HttpExchangeRateRepository implements ExchangeRateRepository {
  HttpExchangeRateRepository({http.Client? client})
    : _client = client ?? http.Client();

  static final HttpExchangeRateRepository instance =
      HttpExchangeRateRepository();

  static const _historyCacheKey = 'exchange_rate_history_v2';
  static const _historyCacheExpiryKey = 'exchange_rate_history_expiry';
  static const _historyCacheTtlHours = 24;
  static const _snapshotTable = 'snapshot';

  final http.Client _client;
  ExchangeRateSnapshot? _cachedSnapshot;
  Map<String, List<ExchangeRateHistoryPoint>>? _cachedHistory;
  Database? _snapshotDb;
  ValueNotifier<ExchangeRateSnapshot?> snapshotNotifier = ValueNotifier(null);

  Future<Database> _getSnapshotDb() async {
    if (_snapshotDb != null) return _snapshotDb!;
    try {
      final dbPath = await getDatabasesPath();
      _snapshotDb = await openDatabase(
        join(dbPath, 'dollapp_snapshot.db'),
        version: 1,
        onCreate: (db, version) {
          return db.execute(
            'CREATE TABLE $_snapshotTable (id INTEGER PRIMARY KEY, data TEXT)',
          );
        },
      );
      return _snapshotDb!;
    } catch (error, stackTrace) {
      debugPrint('HttpExchangeRateRepository._getSnapshotDb failed: $error');
      // Log error to audit service (async, non-blocking)
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'INIT_DATABASE',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'dbPath': await getDatabasesPath(),
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        } catch (auditError) {
          debugPrint('Failed to send audit log: $auditError');
        }
      });
      rethrow;
    }
  }

  @override
  Future<ExchangeRateSnapshot> getRates({bool forceRefresh = false}) async {
    final previousSnapshot = _cachedSnapshot ?? await _loadSavedSnapshot();

    try {
      // Parallelize API calls
      final results = await Future.wait([
        _fetchSupabaseRates(),
        _fetchRemoteHistories(),
      ]);
      final liveRates = results[0] as _SupabaseRates;
      final histories = results[1] as Map<String, List<ExchangeRateHistoryPoint>>;

      final updatedAt = liveRates.updatedAt;
      final liveUsdValue = liveRates.tryByCode('USD')?.value;
      final usdValue = liveUsdValue != null && liveUsdValue > 0
          ? liveUsdValue
          : previousSnapshot?.tryByCode('USD')?.value ?? 1;
      final liveSnapshotRates = _buildLiveSnapshotRates(
        liveRates: liveRates,
        updatedAt: updatedAt,
        previousSnapshot: previousSnapshot,
        usdValue: usdValue,
      );
      final rates = _ratesWithHistory(liveSnapshotRates, histories);

      _cachedSnapshot = ExchangeRateSnapshot(
        rates: rates,
        updatedAt: updatedAt,
        usedFallback: false,
      );
      await _saveSnapshot(_cachedSnapshot!);
      snapshotNotifier.value = _cachedSnapshot;
      return _cachedSnapshot!;
    } catch (error, stackTrace) {
      debugPrint('HttpExchangeRateRepository.getRates failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      // Log error to audit service (async, non-blocking)
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'FETCH_EXCHANGE_RATES',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'forceRefresh': forceRefresh,
                'hasCachedSnapshot': _cachedSnapshot != null,
                'hasPreviousSnapshot': previousSnapshot != null,
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        } catch (auditError) {
          debugPrint('Failed to send audit log: $auditError');
        }
      });

      if (_cachedSnapshot != null) {
        _cachedSnapshot = await _snapshotWithSavedHistory(
          _cachedSnapshot!.copyWith(usedFallback: true),
        );
        snapshotNotifier.value = _cachedSnapshot;
        return _cachedSnapshot!;
      }

      if (previousSnapshot != null) {
        _cachedSnapshot = await _snapshotWithSavedHistory(
          previousSnapshot.copyWith(usedFallback: true),
        );
        snapshotNotifier.value = _cachedSnapshot;
        return _cachedSnapshot!;
      }

      rethrow;
    }
  }

  List<ExchangeRate> _buildLiveSnapshotRates({
    required _SupabaseRates liveRates,
    required DateTime updatedAt,
    required ExchangeRateSnapshot? previousSnapshot,
    required double usdValue,
  }) {
    final codes =
        <String>{
          ...liveRates.entries.keys,
          if (liveRates.entries.containsKey('USD')) 'USD',
        }.toList()..sort((a, b) {
          const priority = {'USD': 0, 'EUR': 1, 'COP': 2};
          return (priority[a] ?? 99).compareTo(priority[b] ?? 99);
        });

    return codes.map((code) {
      final entry = liveRates.entries[code]!;
      return _rateFromLiveValue(
        base: _baseRateForCode(code, updatedAt),
        entry: entry,
        updatedAt: updatedAt,
        previous: previousSnapshot?.tryByCode(code),
        usdValue: usdValue,
        normalizeValue: _normalizeLiveRateValue,
      );
    }).toList();
  }

  Future<ExchangeRateSnapshot> _snapshotWithSavedHistory(
    ExchangeRateSnapshot snapshot,
  ) async {
    return snapshot;
  }

  Future<ExchangeRateSnapshot?> loadSavedSnapshot() async {
    if (_cachedSnapshot != null) {
      return _cachedSnapshot;
    }

    final snapshot = await _loadSavedSnapshot();
    if (snapshot != null) {
      _cachedSnapshot = snapshot;
      snapshotNotifier.value = snapshot;
    }
    return snapshot;
  }

  List<ExchangeRate> _ratesWithHistory(
    List<ExchangeRate> rates,
    Map<String, List<ExchangeRateHistoryPoint>> histories,
  ) {
    return rates.map((rate) {
      final remotePoints =
          histories[rate.code] ?? const <ExchangeRateHistoryPoint>[];
      final currentValue = rate.displayValue ?? rate.value;
      final currentCurrency = rate.displayCurrencyCode ?? rate.code;
      final today = DateTime(
        rate.updatedAt.year,
        rate.updatedAt.month,
        rate.updatedAt.day,
      );
      
      final normalizedPoints = remotePoints
          .where((point) => !_isSameDay(point.date, today))
          .map(
            (point) => ExchangeRateHistoryPoint(
              date: point.date,
              value: point.value,
              currencyCode: point.currencyCode,
            ),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      final historyPoints = [
        ...normalizedPoints,
        ExchangeRateHistoryPoint(
          date: today,
          value: currentValue,
          currencyCode: currentCurrency,
        ),
      ];

      final values = historyPoints.map((point) => point.value).toList();
      if (values.length < 2) {
        return rate.copyWith(
          changePercent: 0,
          sparklineValues: const [],
          historyPoints: historyPoints,
        );
      }

      final previousValue = values[values.length - 2];
      final changePercent = previousValue == 0
          ? 0.0
          : ((currentValue - previousValue) / previousValue) * 100;

      return rate.copyWith(
        changePercent: changePercent,
        sparklineValues: values,
        historyPoints: historyPoints,
      );
    }).toList();
  }

  Future<_SupabaseRates> _fetchSupabaseRates() async {
    if (AppConfig.supabaseAnonKey.isEmpty) {
      throw const FormatException('Falta configurar SUPABASE_ANON_KEY');
    }

    final uri = Uri.https(
      '${AppConfig.supabaseProjectRef}.supabase.co',
      '/functions/v1/tasas-divisas',
    );

    debugPrint('Requesting rates from $uri');

    final response = await _client
        .get(uri, headers: _supabaseHeaders())
        .timeout(const Duration(seconds: 12));
    debugPrint('Rates response status: ${response.statusCode}');
   debugPrint('Rate response: ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('Supabase respondio ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta de tasas invalida');
    }

    final entries = _extractRateEntries(decoded);
    if (entries.isEmpty) {
      throw const FormatException('La API respondio sin tasas utilizables');
    }

    return _SupabaseRates(
      entries: entries,
      updatedAt: _extractDate(decoded['fecha']) ?? DateTime.now(),
    );
  }

  Map<String, String> _supabaseHeaders() {
    return {
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      'apikey': AppConfig.supabaseAnonKey,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, List<ExchangeRateHistoryPoint>>> _fetchRemoteHistories() async {
    // Check cache first with TTL
    if (_cachedHistory != null) {
      final prefs = await SharedPreferences.getInstance();
      final expiry = prefs.getInt(_historyCacheExpiryKey);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiry != null && now < expiry) {
        return _cachedHistory!;
      }
    }

    try {
      final uri = Uri.https(
        '${AppConfig.supabaseProjectRef}.supabase.co',
        '/functions/v1/get-tasas-historico',
      );
     
      debugPrint('Requesting rate history from $uri');

      final response = await _client
          .get(uri, headers: _supabaseHeaders())
          .timeout(const Duration(seconds: 12));
      debugPrint('Rate history response status: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(
          'Supabase historico respondio ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Respuesta de historico invalida');
      }

      final histories = _extractHistoryEntries(decoded);
      _cachedHistory = histories;

      // Cache with TTL
      final prefs = await SharedPreferences.getInstance();
      final expiryTime = DateTime.now()
          .add(const Duration(hours: _historyCacheTtlHours))
          .millisecondsSinceEpoch;
      await prefs.setInt(_historyCacheExpiryKey, expiryTime);
      await prefs.setString(_historyCacheKey, jsonEncode(_serializeHistories(histories)));

      return histories;
    } catch (error, stackTrace) {
      debugPrint(
        'HttpExchangeRateRepository._fetchRemoteHistories failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      // Log error to audit service (async, non-blocking)
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'FETCH_EXCHANGE_RATE_HISTORY',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        } catch (auditError) {
          debugPrint('Failed to send audit log: $auditError');
        }
      });

      // Fallback to cached history if available
      if (_cachedHistory != null) {
        return _cachedHistory!;
      }

      // Try to load from persistent storage
      final prefs = await SharedPreferences.getInstance();
      final rawHistory = prefs.getString(_historyCacheKey);
      if (rawHistory != null) {
        try {
          final decoded = jsonDecode(rawHistory);
          if (decoded is Map<String, dynamic>) {
            final histories = _deserializeHistories(decoded);
            _cachedHistory = histories;
            return histories;
          }
        } catch (_) {
          // Invalid cache, ignore
        }
      }

      return const {};
    }
  }

  Map<String, dynamic> _serializeHistories(
      Map<String, List<ExchangeRateHistoryPoint>> histories) {
    return {
      for (final entry in histories.entries)
        entry.key: entry.value
            .map((p) => {
                  'fecha': p.date.toIso8601String(),
                  'valor': p.value,
                  'moneda': p.currencyCode,
                })
            .toList(),
    };
  }

  Map<String, List<ExchangeRateHistoryPoint>> _deserializeHistories(
      Map<String, dynamic> decoded) {
    return {
      for (final entry in decoded.entries)
        entry.key: (entry.value as List)
            .map((p) => ExchangeRateHistoryPoint(
                  date: DateTime.parse(p['fecha'] as String),
                  value: (p['valor'] as num).toDouble(),
                  currencyCode: p['moneda'] as String,
                ))
            .toList(),
    };
  }

  Map<String, List<ExchangeRateHistoryPoint>> _extractHistoryEntries(
    Map<String, dynamic> decoded,
  ) {
    final histories = <String, List<ExchangeRateHistoryPoint>>{};

    for (final entry in decoded.entries) {
      final code =
          _currencyCodeFromName(entry.key) ?? _normalizeCurrencyCode(entry.key);
      final rawPoints = entry.value;
      if (rawPoints is! List) {
        continue;
      }

      final points = <ExchangeRateHistoryPoint>[];
      for (final rawPoint in rawPoints) {
        if (rawPoint is! Map<String, dynamic>) {
          continue;
        }

        final date = _extractDate(rawPoint['fecha'] ?? rawPoint['created_at']);
        final value = _tryParseNumber(rawPoint['monto'] ?? rawPoint['valor']);
        final currencyCode = _cleanString(rawPoint['moneda']) ?? 'VES';
        if (date == null || value == null || value <= 0) {
          continue;
        }

        points.add(
          ExchangeRateHistoryPoint(
            date: DateTime(date.year, date.month, date.day),
            value: value,
            currencyCode: currencyCode,
          ),
        );
      }

      points.sort((a, b) => a.date.compareTo(b.date));
      if (points.isNotEmpty) {
        histories[code] = points;
      }
    }

    return histories;
  }

  Map<String, _SupabaseRateEntry> _extractRateEntries(
    Map<String, dynamic> decoded,
  ) {
    final entries = <String, _SupabaseRateEntry>{};

    final tasas = decoded['tasas'];
    if (tasas is List) {
      for (final item in tasas) {
        if (item is Map<String, dynamic>) {
          final rawDisplayCurrency = item['moneda'];
          final rawConversionCode = item['conver'] ?? item['conversion'];
          final rawName = item['nombre'] ?? item['name'];
          final rawCode =
              rawConversionCode ??
              rawDisplayCurrency ??
              item['codigo'] ??
              item['code'];
          if (rawCode == null) {
            continue;
          }

          final displayCurrencyCode = _cleanString(rawDisplayCurrency);
          final conversionCode = _cleanString(rawConversionCode) == null
              ? null
              : _normalizeCurrencyCode(rawConversionCode.toString());
          final code = _rateCodeFromApiItem(
            rawCode: rawCode.toString(),
            displayCurrencyCode: displayCurrencyCode,
            name: _cleanString(rawName),
            conversionCode: conversionCode,
          );
          final rawValue = item['valor'] ?? item['monto'] ?? item['rate'];
          final value = _tryParseNumber(rawValue);
          entries[code] = _SupabaseRateEntry(
            code: code,
            value: value,
            name: _cleanString(rawName),
            moneyType: _cleanString(item['type-money'] ?? item['type_money']),
            displayCurrencyCode: displayCurrencyCode,
            conversionCode: conversionCode,
            sourceUpdatedAtLabel: _cleanString(
              item['fechaActualizacion'] ?? item['create_date'],
            ),
          );
        }
      }
    }

    for (final entry in decoded.entries) {
      final value = _tryParseNumber(entry.value);
      if (value != null) {
        final code = _normalizeCurrencyCode(entry.key);
        entries.putIfAbsent(
          code,
          () => _SupabaseRateEntry(code: code, value: value),
        );
      }
    }

    return entries;
  }

  String _rateCodeFromApiItem({
    required String rawCode,
    required String? displayCurrencyCode,
    required String? name,
    required String? conversionCode,
  }) {
    final normalizedDisplayCode = displayCurrencyCode == null
        ? null
        : _normalizeCurrencyCode(displayCurrencyCode);
    final nameCode = _currencyCodeFromName(name);

    if (nameCode != null &&
        (normalizedDisplayCode == null ||
            _isVisualCurrency(normalizedDisplayCode))) {
      return nameCode;
    }

    if (normalizedDisplayCode != null &&
        !_isVisualCurrency(normalizedDisplayCode)) {
      return normalizedDisplayCode;
    }

    return conversionCode ?? _normalizeCurrencyCode(rawCode);
  }

  String? _currencyCodeFromName(String? name) {
    if (name == null) {
      return null;
    }

    final normalized = _asciiUpper(name);
    if (normalized.contains('USDT') || normalized.contains('PARALELO')) {
      return 'USDT';
    }
    if (normalized.contains('PESO') || normalized.contains('COLOMB')) {
      return 'COP';
    }
    if (normalized.contains('EURO')) {
      return 'EUR';
    }
    if (normalized.contains('DOLAR') || normalized.contains('DÓLAR')) {
      return 'USD';
    }
    return null;
  }

  bool _isVisualCurrency(String code) {
    return code == 'VES' || code == 'BS' || code == 'BS.';
  }

  String _normalizeCurrencyCode(String value) {
    final normalized = _asciiUpper(value);
    return switch (normalized) {
      'DOLAR' || 'DÓLAR' || 'DOLAR_BCV' || 'USD_BCV' => 'USD',
      'VES' || 'BS' || 'BS.' => 'VES',
      'EURO' || 'EURO_BCV' || 'EUR_BCV' => 'EUR',
      'PESO' || 'PESO_COP' || 'COP_PESO' => 'COP',
      _ => normalized,
    };
  }

  String _asciiUpper(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll('\u00C1', 'A')
        .replaceAll('\u00C9', 'E')
        .replaceAll('\u00CD', 'I')
        .replaceAll('\u00D3', 'O')
        .replaceAll('\u00DA', 'U')
        .replaceAll('\u00D1', 'N');
  }

  ExchangeRate _baseRateForCode(String code, DateTime updatedAt) {
    final mockRate = MockRates.tryByCode(code);
    if (mockRate != null) {
      return mockRate;
    }

    return ExchangeRate(
      code: code,
      name: _currencyName(code),
      source: 'API de tasas',
      value: 0,
      symbol: _currencySymbol(code),
      updatedAt: updatedAt,
      isOfficial: true,
      changePercent: 0,
      sparklineValues: const [],
      historyPoints: const [],
    );
  }

  String _currencyName(String code) {
    return switch (code) {
      'USD' => 'Dolar estadounidense',
      'EUR' => 'Euro',
      'COP' => 'Peso colombiano',
      'USDT' => 'USDT',
      'CNY' || 'CNH' || 'YUAN' => 'Yuan',
      _ => code,
    };
  }

  String _currencySymbol(String code) {
    return switch (code) {
      'USD' || 'USDT' || 'COP' => r'$',
      'EUR' => '€',
      'CNY' || 'CNH' || 'YUAN' => '¥',
      _ => code.length <= 3 ? code : code.substring(0, 3),
    };
  }

  String? _cleanString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    if (text.isEmpty || text == '00/00/0000') {
      return null;
    }
    return text;
  }

  double? _tryParseNumber(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final trimmed = value.trim();
      final normalized = trimmed.contains(',') && trimmed.contains('.')
          ? trimmed.replaceAll('.', '').replaceAll(',', '.')
          : trimmed.replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  DateTime? _extractDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    final isoDate = DateTime.tryParse(value);
    if (isoDate != null) {
      return isoDate;
    }

    final dateParts = value.split('/');
    if (dateParts.length == 3) {
      final day = int.tryParse(dateParts[0]);
      final month = int.tryParse(dateParts[1]);
      final year = int.tryParse(dateParts[2]);
      if (day != null && month != null && year != null && year > 0) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  String _fallbackSourceUpdatedAtLabel(
    ExchangeRate? previous,
    DateTime updatedAt,
  ) {
    if (previous?.sourceUpdatedAtLabel != null && previous!.sourceUpdatedAtLabel!.isNotEmpty) {
      return previous.sourceUpdatedAtLabel!;
    }

    final date = previous?.updatedAt ?? updatedAt;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$day/$month/$year';
  }

  ExchangeRate _rateFromLiveValue({
    required ExchangeRate base,
    required _SupabaseRateEntry entry,
    required DateTime updatedAt,
    required ExchangeRate? previous,
    required double usdValue,
    required double Function(String code, double value, double usdValue)
        normalizeValue,
  }) {
    final hasValidValue = entry.value != null && entry.value! > 0;
    final normalizedValue = hasValidValue
        ? normalizeValue(entry.code, entry.value!, usdValue)
        : previous?.value ?? base.value;
    final sourceDate = hasValidValue
        ? entry.sourceUpdatedAtLabel ?? previous?.sourceUpdatedAtLabel
        : _fallbackSourceUpdatedAtLabel(previous, updatedAt);
    final moneyType = entry.moneyType ?? previous?.moneyType ?? entry.code;
    final displayCurrencyCode = hasValidValue
        ? (entry.code == 'COP' ? 'COP' : (entry.displayCurrencyCode ?? entry.moneyType ?? 'VES'))
        : (previous?.displayCurrencyCode ??
              entry.displayCurrencyCode ??
              entry.moneyType ??
              (entry.code == 'COP' ? 'COP' : 'VES'));
    final displayValue = hasValidValue
        ? entry.value
        : previous?.displayValue ?? normalizedValue;

    return ExchangeRate(
      code: base.code,
      name: entry.name ?? base.name,
      source: base.source,
      value: normalizedValue,
      symbol: base.symbol,
      updatedAt: hasValidValue ? updatedAt : previous?.updatedAt ?? updatedAt,
      isOfficial: base.isOfficial,
      changePercent: base.changePercent,
      sparklineValues: _scaledSparkline(
        previous?.sparklineValues ?? base.sparklineValues,
        normalizedValue,
      ),
      historyPoints: previous?.historyPoints ?? base.historyPoints,
      moneyType: moneyType,
      sourceUpdatedAtLabel: sourceDate,
      keptPreviousValue: !hasValidValue,
      displayValue: displayValue,
      displayCurrencyCode: displayCurrencyCode,
      conversionCode: entry.conversionCode ?? previous?.conversionCode,
    );
  }

  double _normalizeLiveRateValue(String code, double value, double usdValue) {
    return value;
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  List<double> _scaledSparkline(List<double> values, double liveValue) {
    if (values.isEmpty) {
      return [liveValue];
    }

    final last = values.last == 0 ? 1 : values.last;
    return values.map((value) => (value / last) * liveValue).toList();
  }

  Future<void> _saveSnapshot(ExchangeRateSnapshot snapshot) async {
    try {
      final db = await _getSnapshotDb();
      final data = jsonEncode(snapshot.toJson());
      await db.insert(
        _snapshotTable,
        {'id': 1, 'data': data},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (error, stackTrace) {
      debugPrint('HttpExchangeRateRepository._saveSnapshot failed: $error');
      // Log error to audit service (async, non-blocking)
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'SAVE_SNAPSHOT',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'snapshotUpdatedAt': snapshot.updatedAt.toIso8601String(),
                'ratesCount': snapshot.rates.length,
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        } catch (auditError) {
          debugPrint('Failed to send audit log: $auditError');
        }
      });
      rethrow;
    }
  }

  Future<ExchangeRateSnapshot?> _loadSavedSnapshot() async {
    try {
      final db = await _getSnapshotDb();
      final maps = await db.query(_snapshotTable, where: 'id = ?', whereArgs: [1]);
      if (maps.isEmpty) return null;
      try {
        final decoded = jsonDecode(maps.first['data'] as String);
        if (decoded is Map<String, dynamic>) {
          return ExchangeRateSnapshot.fromJson(decoded);
        }
      } catch (parseError, parseStackTrace) {
        debugPrint('HttpExchangeRateRepository._loadSavedSnapshot parse failed: $parseError');
        // Log parse error to audit service (async, non-blocking)
        Future.microtask(() async {
          try {
            await AuditService.instance.logError(
              AuditLog(
                accion: 'LOAD_SNAPSHOT_PARSE',
                mensaje: parseError.toString(),
                codigo: parseError.runtimeType.toString(),
                metadatos: {
                  'rawDataLength': (maps.first['data'] as String).length,
                  'stackTrace': parseStackTrace.toString(),
                },
              ),
            );
          } catch (auditError) {
            debugPrint('Failed to send audit log: $auditError');
          }
        });
      }
    } catch (error, stackTrace) {
      debugPrint('HttpExchangeRateRepository._loadSavedSnapshot failed: $error');
      // Log error to audit service (async, non-blocking)
      Future.microtask(() async {
        try {
          await AuditService.instance.logError(
            AuditLog(
              accion: 'LOAD_SNAPSHOT',
              mensaje: error.toString(),
              codigo: error.runtimeType.toString(),
              metadatos: {
                'stackTrace': stackTrace.toString(),
              },
            ),
          );
        } catch (auditError) {
          debugPrint('Failed to send audit log: $auditError');
        }
      });
    }
    return null;
  }
}

class _SupabaseRates {
  const _SupabaseRates({required this.entries, required this.updatedAt});

  final Map<String, _SupabaseRateEntry> entries;
  final DateTime updatedAt;

  _SupabaseRateEntry byCode(String code) {
    final entry = entries[code];
    if (entry == null) {
      throw FormatException('Falta la tasa $code');
    }
    return entry;
  }

  _SupabaseRateEntry? tryByCode(String code) => entries[code];
}

class _SupabaseRateEntry {
  const _SupabaseRateEntry({
    required this.code,
    required this.value,
    this.name,
    this.moneyType,
    this.displayCurrencyCode,
    this.conversionCode,
    this.sourceUpdatedAtLabel,
  });

  final String code;
  final double? value;
  final String? name;
  final String? moneyType;
  final String? displayCurrencyCode;
  final String? conversionCode;
  final String? sourceUpdatedAtLabel;
}
