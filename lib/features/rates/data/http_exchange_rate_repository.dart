import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();

  @override
  String toString() => 'No Internet connection available.';
}

class RateRefreshLimitException implements Exception {
  const RateRefreshLimitException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() =>
      'Rate refresh limit reached. Retry after ${retryAfter.inSeconds} seconds.';
}

class RatesAlreadyUpdatedException implements Exception {
  const RatesAlreadyUpdatedException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() =>
      'Rates already updated. Retry after ${retryAfter.inMinutes} minutes.';
}

class HistoricalRateResult {
  const HistoricalRateResult({required this.value, required this.usedDate});

  final double value;
  final DateTime usedDate;
}

class HttpExchangeRateRepository implements ExchangeRateRepository {
  HttpExchangeRateRepository({http.Client? client})
    : _client = client ?? http.Client();

  static final HttpExchangeRateRepository instance =
      HttpExchangeRateRepository();

  static const _historyCacheKey = 'exchange_rate_history_v4';
  static const _historyCacheExpiryKey = 'exchange_rate_history_expiry_v4';
  static const _historyCacheTtlHours = 24;
  static const _refreshAttemptsKey = 'exchange_rate_refresh_attempts_v1';
  static const _lastSuccessfulRefreshKey =
      'exchange_rate_last_successful_refresh_v1';
  static const _refreshWindow = Duration(minutes: 1);
  static const _successfulRefreshWindow = Duration(hours: 4);
  static const _maxRefreshAttempts = 2;
  static const _snapshotTable = 'snapshot';
  static const _liveRatesTimeout = Duration(seconds: 20);

  final http.Client _client;
  static Future<void> _refreshLimitChain = Future<void>.value();
  static DateTime? _ratesNoticeUntil;

  static bool get isRatesNoticeVisible {
    final until = _ratesNoticeUntil;
    return until != null && DateTime.now().isBefore(until);
  }
  ExchangeRateSnapshot? _cachedSnapshot;
  Map<String, List<ExchangeRateHistoryPoint>>? _cachedHistory;
  Database? _snapshotDb;
  ValueNotifier<ExchangeRateSnapshot?> snapshotNotifier = ValueNotifier(null);

  Future<void> _enforceRefreshLimit() {
    final operation = _refreshLimitChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - _refreshWindow.inMilliseconds;
      final attempts = (prefs.getStringList(_refreshAttemptsKey) ?? [])
          .map(int.tryParse)
          .whereType<int>()
          .where((value) => value > cutoff)
          .toList();

      if (attempts.length >= _maxRefreshAttempts) {
        final oldest = attempts.reduce((a, b) => a < b ? a : b);
        final retryAfter = Duration(
          milliseconds: (oldest + _refreshWindow.inMilliseconds) - now,
        );
        throw RateRefreshLimitException(
          retryAfter.isNegative ? Duration.zero : retryAfter,
        );
      }

      attempts.add(now);
      await prefs.setStringList(
        _refreshAttemptsKey,
        attempts.map((value) => value.toString()).toList(),
      );
    });

    _refreshLimitChain = operation.catchError((_) {});
    return operation;
  }

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
        } catch (_) {
          // Silently fail to avoid error loops
        }
      });
      rethrow;
    }
  }

  bool _isNetworkError(Object error) {
    return error is SocketException ||
        error is http.ClientException ||
        error is HandshakeException;
  }

  Future<Duration?> _timeUntilRefreshAllowed(
    ExchangeRateSnapshot? snapshot,
  ) async {
    if (snapshot == null || snapshot.usedFallback) return null;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final savedMillis = prefs.getInt(_lastSuccessfulRefreshKey);

    if (savedMillis == null) {
      final snapshotDate = snapshot.updatedAt.toLocal();
      final sameDay = snapshotDate.year == now.year &&
          snapshotDate.month == now.month &&
          snapshotDate.day == now.day;
      if (sameDay) {
        await prefs.setInt(
          _lastSuccessfulRefreshKey,
          now.millisecondsSinceEpoch,
        );
        return _successfulRefreshWindow;
      }
      return null;
    }

    final lastRefresh = DateTime.fromMillisecondsSinceEpoch(savedMillis);
    final sameDay = lastRefresh.year == now.year &&
        lastRefresh.month == now.month &&
        lastRefresh.day == now.day;

    if (!sameDay) return null;

    final elapsed = now.difference(lastRefresh);
    if (elapsed >= _successfulRefreshWindow) return null;
    return _successfulRefreshWindow - elapsed;
  }

  Future<void> _markSuccessfulRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastSuccessfulRefreshKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<ExchangeRateSnapshot> getRates({bool forceRefresh = false}) async {
    final previousSnapshot = _cachedSnapshot ?? await _loadSavedSnapshot();

    final retryAfter = await _timeUntilRefreshAllowed(previousSnapshot);
    if (retryAfter != null) {
      _ratesNoticeUntil = DateTime.now().add(const Duration(seconds: 4));
      throw RatesAlreadyUpdatedException(retryAfter);
    }

    await _enforceRefreshLimit();

    try {
      // Parallelize API calls
      final results = await Future.wait([
        _fetchSupabaseRates(forceRefresh: forceRefresh),
        _fetchRemoteHistories(forceRefresh: forceRefresh),
      ]);
      final liveRates = results[0] as _SupabaseRates;
      final histories = results[1] as Map<String, List<ExchangeRateHistoryPoint>>;

      if (previousSnapshot != null &&
          liveRates.updatedAt.isBefore(previousSnapshot.updatedAt)) {
        throw const FormatException(
          'La API devolvió una tasa más antigua que la tasa ya cargada.',
        );
      }

      final updatedAt = liveRates.updatedAt;
      final liveSnapshotRates = _buildLiveSnapshotRates(
        liveRates: liveRates,
        updatedAt: updatedAt,
        previousSnapshot: previousSnapshot,
      );
      final rates = _ratesWithHistory(liveSnapshotRates, histories);

      final sortedRates = _sortRatesWithFavorites(rates);
    _cachedSnapshot = ExchangeRateSnapshot(
        rates: sortedRates,
        updatedAt: updatedAt,
        usedFallback: false,
      );
      await _saveSnapshot(_cachedSnapshot!);
      await _markSuccessfulRefresh();
      snapshotNotifier.value = _cachedSnapshot;
      return _cachedSnapshot!;
    } catch (error, stackTrace) {
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
        } catch (_) {
          // Silently fail
        }
      });

      if (_cachedSnapshot != null) {
        if (!_isNetworkError(error)) {
          rethrow;
        }
        final fallbackError = _isNetworkError(error)
            ? null
            : error.toString();
        _cachedSnapshot = await _snapshotWithSavedHistory(
          _cachedSnapshot!.copyWith(
            usedFallback: true,
            fallbackError: fallbackError,
          ),
        );
        snapshotNotifier.value = _cachedSnapshot;
        return _cachedSnapshot!;
      }

      if (previousSnapshot != null) {
        if (!_isNetworkError(error)) {
          rethrow;
        }
        final fallbackError = _isNetworkError(error)
            ? null
            : error.toString();
        _cachedSnapshot = await _snapshotWithSavedHistory(
          previousSnapshot.copyWith(
            usedFallback: true,
            fallbackError: fallbackError,
          ),
        );
        snapshotNotifier.value = _cachedSnapshot;
        return _cachedSnapshot!;
      }

      if (_isNetworkError(error)) {
        throw const NetworkUnavailableException();
      }

      rethrow;
    }
  }

  List<ExchangeRate> _buildLiveSnapshotRates({
    required _SupabaseRates liveRates,
    required DateTime updatedAt,
    required ExchangeRateSnapshot? previousSnapshot,
  }) {
    final previousRatesByPairKey = {
      for (final rate in previousSnapshot?.rates ?? const <ExchangeRate>[])
        _rateBindingKey(
          fromCurrency: rate.moneyType ?? rate.code,
          toCurrency: rate.conversionCode ?? rate.displayCurrencyCode,
          name: rate.name,
        ): rate,
    };

    final entries = liveRates.entries.asMap().entries.toList()
      ..sort((a, b) {
        return a.key.compareTo(b.key);
      });

    return entries.map((entry) {
      final rateEntry = entry.value;
      final pairKey = _rateBindingKey(
        fromCurrency: rateEntry.fromCurrency ?? rateEntry.code,
        toCurrency: rateEntry.conversionCode ?? rateEntry.displayCurrencyCode,
        name: rateEntry.name,
      );
      final previous =
          previousSnapshot?.tryById(rateEntry.id) ??
          previousRatesByPairKey[pairKey];
      return _rateFromLiveValue(
        id: rateEntry.id,
        base: _baseRateForCode(rateEntry.code, updatedAt),
        entry: rateEntry,
        updatedAt: updatedAt,
        previous: previous,
        normalizeValue: _normalizeLiveRateValue,
        isFavorite: previous?.isFavorite ?? false,
      );
    }).toList();
  }

  List<ExchangeRate> _sortRatesWithFavorites(List<ExchangeRate> rates) {
    final favorites = rates.where((rate) => rate.isFavorite).toList();
    final others = rates.where((rate) => !rate.isFavorite).toList();
    return [...favorites, ...others];
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
      _cachedSnapshot = snapshot.copyWith(
        rates: _sortRatesWithFavorites(snapshot.rates),
      );
      snapshotNotifier.value = _cachedSnapshot;
    }
    return snapshot;
  }

  Future<void> setFavorite(String id, bool isFavorite) async {
    final snapshot = _cachedSnapshot ?? await _loadSavedSnapshot();
    if (snapshot == null) {
      return;
    }

    final alreadyFavorite = snapshot.rates.any(
      (rate) => rate.id == id && rate.isFavorite,
    );
    final favoriteCount = snapshot.rates.where((rate) => rate.isFavorite).length;
    if (isFavorite && !alreadyFavorite && favoriteCount >= 3) {
      return;
    }

    final updatedRates = snapshot.rates.map((rate) {
      if (rate.id == id) {
        return rate.copyWith(isFavorite: isFavorite);
      }
      return rate;
    }).toList();

    _cachedSnapshot = snapshot.copyWith(
      rates: _sortRatesWithFavorites(updatedRates),
    );
    snapshotNotifier.value = _cachedSnapshot;
    await _saveSnapshot(_cachedSnapshot!);
  }

  List<ExchangeRate> _ratesWithHistory(
    List<ExchangeRate> rates,
    Map<String, List<ExchangeRateHistoryPoint>> histories,
  ) {
    return rates.map((rate) {
      final remotePoints = histories[_historyBindingKey(rate.name)] ??
          const <ExchangeRateHistoryPoint>[];
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

      // During non-operating days the API can repeat the last published rate
      // for today. Compare against the most recent *different* value so a
      // repeated weekend rate does not hide the available historical trend.
      final previousValue = _latestDifferentPositiveValue(values);
      final changePercent = previousValue == null
          ? 0.0
          : ((currentValue - previousValue) / previousValue) * 100;

      return rate.copyWith(
        changePercent: changePercent,
        sparklineValues: values,
        historyPoints: historyPoints,
      );
    }).toList();
  }

  double? _latestDifferentPositiveValue(List<double> values) {
    final currentValue = values.last;
    for (var index = values.length - 2; index >= 0; index--) {
      final candidate = values[index];
      if (candidate > 0) {
        final changePercent =
            ((currentValue - candidate) / candidate).abs() * 100;
        // Ignore insignificant differences caused by the API formatting the
        // live value to two decimals while history keeps more precision.
        if (changePercent > 0.01) {
          return candidate;
        }
      }
    }
    return null;
  }

  Future<_SupabaseRates> _fetchSupabaseRates({
    bool forceRefresh = false,
  }) async {
    if (AppConfig.supabaseAnonKey.isEmpty) {
      throw const FormatException('Falta configurar SUPABASE_ANON_KEY');
    }
    
    final uri = Uri.https(
      '${AppConfig.supabaseProjectRef}.supabase.co',
      '/functions/v1/tasas-divisas',
      forceRefresh
          ? {'refresh': DateTime.now().millisecondsSinceEpoch.toString()}
          : null,
    );

    final response = await _client
        .get(uri, headers: _supabaseHeaders())
        .timeout(_liveRatesTimeout);

    final rawBody = utf8.decode(response.bodyBytes);
    debugPrint('[tasas-divisas] HTTP ${response.statusCode} ${response.request?.url ?? uri}');
    debugPrint('[tasas-divisas] Respuesta cruda inicio');
    for (var offset = 0; offset < rawBody.length; offset += 800) {
      final end = (offset + 800 < rawBody.length)
          ? offset + 800
          : rawBody.length;
      debugPrint(rawBody.substring(offset, end));
    }
    debugPrint('[tasas-divisas] Respuesta cruda fin');
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = rawBody.trim();
      final preview = body.length > 300 ? body.substring(0, 300) : body;
      final detail = preview.isEmpty ? '' : ': $preview';
      throw FormatException(
        'Supabase respondio ${response.statusCode}$detail',
      );
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta de tasas invalida');
    }

    final updatedAt = _extractDate(decoded['fecha']);
    if (updatedAt == null) {
      throw const FormatException(
        'La API de tasas no devolvió una fecha de actualización válida.',
      );
    }

    final entries = _extractRateEntries(
      decoded,
      fallbackDate: updatedAt,
    );
    if (entries.isEmpty) {
      throw const FormatException('La API respondio sin tasas utilizables');
    }

    return _SupabaseRates(
      entries: entries,
      updatedAt: updatedAt,
    );
  }

  Map<String, String> _supabaseHeaders() {
    return {
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      'apikey': AppConfig.supabaseAnonKey,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache',
    };
  }

  Future<Map<String, List<ExchangeRateHistoryPoint>>> _fetchRemoteHistories({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      _cachedHistory = null;
    }

    // Check cache first with TTL
    if (!forceRefresh && _cachedHistory != null) {
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
        forceRefresh
            ? {'refresh': DateTime.now().millisecondsSinceEpoch.toString()}
            : null,
      );
     
      final response = await _client
          .get(uri, headers: _supabaseHeaders())
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(
          'Supabase historico respondio ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final histories = _extractHistoryEntries(decoded);
      if (histories.isEmpty) {
        throw const FormatException(
          'La API de históricos no devolvió registros válidos.',
        );
      }
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
        //  debugPrint('Failed to send audit log: $auditError');
        }
      });

      // Fallback to cached history if available
      if (!forceRefresh && _cachedHistory != null) {
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
              if (histories.isNotEmpty) {
                _cachedHistory = histories;
                return histories;
              }
            }
        } catch (_) {
          // Invalid cache, ignore
        }
      }

      return const {};
    }
  }

  Future<double> fetchHistoricalRate({
    required String nombre,
    required DateTime fecha,
  }) async {
    final result = await fetchHistoricalRateDetails(
      nombre: nombre,
      fecha: fecha,
    );
    return result.value;
  }

  Future<HistoricalRateResult> fetchHistoricalRateDetails({
    required String nombre,
    required DateTime fecha,
  }) async {
    Object? lastError;
    for (final candidateName in _historicalNameCandidates(nombre)) {
      try {
        return await _fetchHistoricalRateOnce(
          nombre: candidateName,
          fecha: fecha,
        );
      } catch (error) {
        lastError = error;
        if (!error.toString().contains('(400)')) {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const FormatException('No se encontrÃ³ la tasa histÃ³rica.');
  }

  Future<HistoricalRateResult> _fetchHistoricalRateOnce({
    required String nombre,
    required DateTime fecha,
  }) async {
    if (AppConfig.supabaseAnonKey.isEmpty) {
      throw const FormatException('Falta configurar SUPABASE_ANON_KEY');
    }

    final uri = Uri.https(
      '${AppConfig.supabaseProjectRef}.supabase.co',
      '/functions/v1/tasas-historicos',
    );

    final formattedDate =
        '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

    final body = jsonEncode({
      'nombre': nombre,
      'fecha': formattedDate,
    });

    final response = await _client
        .post(uri, headers: _supabaseHeaders(), body: body)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      String message =
          'Error al consultar tasa histórica (${response.statusCode})';
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> &&
            decoded['error'] != null) {
          message = decoded['error'] as String;
        }
      } catch (_) {}
      throw FormatException(message);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Respuesta de tasa histórica inválida',
      );
    }

    final tasa = decoded['tasa'];
    if (tasa is! Map<String, dynamic>) {
      throw const FormatException(
        'No se encontró la tasa en la respuesta',
      );
    }

    final value = _tryParseNumber(tasa['monto']);
    if (value == null || value <= 0) {
      throw const FormatException(
        'No hay tasa disponible para la fecha seleccionada.',
      );
    }

    final usedDate = _extractDate(decoded['fechaTasaUsada']) ?? fecha;
    return HistoricalRateResult(value: value, usedDate: usedDate);
  }

  List<String> _historicalNameCandidates(String rawName) {
    final name = rawName.trim();
    final candidates = <String>{name};

    // Some historical records were stored with UTF-8 bytes interpreted as
    // Latin-1. Try that representation when the exact name is rejected.
    try {
      candidates.add(latin1.decode(utf8.encode(name)));
    } catch (_) {}

    try {
      candidates.add(utf8.decode(latin1.encode(name)));
    } catch (_) {}

    // Support old cached names that lost the accent in "DÃ³lar".
    final mojibakeDolar = 'D\u00C3\u00B3lar';
    candidates.add(name.replaceFirst('Dolar', mojibakeDolar));
    candidates.add(name.replaceFirst('D\u00F3lar', mojibakeDolar));

    return candidates.where((candidate) => candidate.isNotEmpty).toList();
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
    Object decoded,
  ) {
    final histories = <String, List<ExchangeRateHistoryPoint>>{};

    if (decoded is Map<String, dynamic>) {
      for (final entry in decoded.entries) {
        final historyKey = _historyBindingKey(entry.key);
        final rawPoints = entry.value;
        if (rawPoints is! List) {
          continue;
        }

        final points = _parseHistoryPoints(rawPoints, fallbackKey: entry.key);
        if (points.isNotEmpty) {
          histories[historyKey] = points;
        }
      }
      return histories;
    }

    if (decoded is List) {
      for (final rawEntry in decoded) {
        if (rawEntry is! Map<String, dynamic>) {
          continue;
        }

        final historyKey = _historyBindingKey(
          _cleanString(rawEntry['nombre'] ?? rawEntry['name']) ??
              rawEntry['moneda']?.toString() ??
              '',
        );
        if (historyKey.isEmpty) {
          continue;
        }

        final points = _parseHistoryPoints([rawEntry],
            fallbackKey: rawEntry['moneda']?.toString() ?? '');
        if (points.isEmpty) {
          continue;
        }

        histories.putIfAbsent(historyKey, () => []).addAll(points);
      }

      for (final entry in histories.entries) {
        entry.value.sort((a, b) => a.date.compareTo(b.date));
      }
      return histories;
    }

    return histories;
  }

  List<ExchangeRateHistoryPoint> _parseHistoryPoints(
    List<dynamic> rawPoints, {
    required String fallbackKey,
  }) {
    final points = <ExchangeRateHistoryPoint>[];

    for (final rawPoint in rawPoints) {
      if (rawPoint is! Map<String, dynamic>) {
        continue;
      }

      final date = _extractDate(rawPoint['fecha'] ?? rawPoint['created_at']);
      final value = _tryParseNumber(rawPoint['monto'] ?? rawPoint['valor']);
      final currencyCode = _normalizeCurrencyCode(
        _cleanString(rawPoint['moneda']) ?? fallbackKey,
      );
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

    return points;
  }

  List<_SupabaseRateEntry> _extractRateEntries(
    Map<String, dynamic> decoded, {
    required DateTime fallbackDate,
  }) {
     final entries = <_SupabaseRateEntry>[];
     final seenEntryKeys = <String>{};

final tasas = decoded['tasas'];
      if (tasas is List) {
        for (final item in tasas) {
          if (item is Map<String, dynamic>) {
            final rawFromCurrency = item['moneda'];
            final rawToCurrency = item['conver'] ?? item['conversion'];
            final rawName = item['nombre'] ?? item['name'];
            final rawSymbol = item['simbolo'];
            final rawMoneyTypeSymbol =
                item['simboloMoneda'] ?? item['simbolo_moneda'];
            final rawConversionSymbol =
                item['simboloConver'] ?? item['simbolo_conver'];
            final rawCode =
                rawToCurrency ??
                rawFromCurrency ??
                item['codigo'] ??
                item['code'];
            if (rawCode == null) {
              continue;
            }

            final fromCurrency = _cleanString(rawFromCurrency);
            final toCurrency = _cleanString(rawToCurrency);
            final normalizedName = _cleanString(rawName);
            final displayCurrencyCode = toCurrency == null
                ? null
                : _normalizeCurrencyCode(toCurrency);
            final conversionCode = toCurrency == null
                ? null
                : _normalizeCurrencyCode(rawToCurrency.toString());
            final code = _rateCodeFromApiItem(
              rawCode: rawCode.toString(),
              fromCurrency: fromCurrency,
              toCurrency: toCurrency,
              name: normalizedName,
            );
            final rawValue = item['valor'] ?? item['monto'] ?? item['rate'];
            final value = _tryParseNumber(rawValue);
            final sourceUpdatedAtLabel = _cleanString(
              item['fechaActualizacion'] ?? item['create_date'],
            );
_cleanString(item['type-money'] ?? item['type_money']);
            final id = [
              conversionCode ?? code,
              displayCurrencyCode ?? code,
              normalizedName ?? code,
              _normalizeCurrencyCode(fromCurrency ?? ''),
            ].join('-');
            final entryKey = [
              code,
              value?.toString() ?? '',
              normalizedName ?? '',
              fromCurrency ?? '',
              displayCurrencyCode ?? '',
              conversionCode ?? '',
              sourceUpdatedAtLabel ?? '',
              rawMoneyTypeSymbol?.toString() ?? '',
              rawConversionSymbol?.toString() ?? '',
            ].join('|');

            if (seenEntryKeys.contains(entryKey)) {
              continue;
            }
            seenEntryKeys.add(entryKey);

entries.add(_SupabaseRateEntry(
              id: id,
              code: code,
              value: value,
              name: normalizedName,
              moneyType: fromCurrency == null
                  ? null
                  : _normalizeCurrencyCode(fromCurrency),
              displayCurrencyCode: displayCurrencyCode,
              conversionCode: conversionCode,
              sourceUpdatedAtLabel: sourceUpdatedAtLabel,
              simbolo: _cleanString(rawSymbol),
              moneyTypeSymbol: _cleanString(rawMoneyTypeSymbol),
              conversionSymbol: _cleanString(rawConversionSymbol),
            ));
          }
        }
      }

     // Solo aplicar fallback flat si la pasada estructurada no produjo resultados
     if (entries.isEmpty) {
       for (final entry in decoded.entries) {
         final value = _tryParseNumber(entry.value);
         if (value != null) {
           final code = _normalizeCurrencyCode(entry.key);
           // Saltar claves que no son monedas
           if ({'tasas', 'fecha', 'updated_at', 'created_at', 'version'}
               .contains(code.toLowerCase())) {
             continue;
           }
            entries.add(
              _SupabaseRateEntry(
                id: code,
                code: code,
                value: value,
                simbolo: null,
              ),
            );
         }
       }
     }

     // La API puede devolver varias filas del mismo par (por ejemplo, si una
     // consulta histórica insertó una fila anterior). La calculadora debe
     // usar únicamente la fila más reciente por par y nombre, no la última
     // fila que venga en el arreglo.
     final latestByBinding = <String, _SupabaseRateEntry>{};
     for (final entry in entries) {
       final binding = _rateBindingKey(
         fromCurrency: entry.fromCurrency ?? entry.code,
         toCurrency: entry.conversionCode ?? entry.displayCurrencyCode,
         name: entry.name,
       );
       final previous = latestByBinding[binding];
       if (previous == null ||
           _entryDate(entry, fallbackDate).isAfter(
             _entryDate(previous, fallbackDate),
           )) {
         latestByBinding[binding] = entry;
       }
     }

     return latestByBinding.values.toList();
   }

  DateTime _entryDate(_SupabaseRateEntry entry, DateTime fallbackDate) {
    return _extractDate(entry.sourceUpdatedAtLabel) ?? fallbackDate;
  }

  String _rateCodeFromApiItem({
    required String rawCode,
    required String? fromCurrency,
    required String? toCurrency,
    required String? name,
  }) {
    if (toCurrency != null && toCurrency.isNotEmpty) {
      return _normalizeCurrencyCode(toCurrency);
    }
    if (fromCurrency != null && fromCurrency.isNotEmpty) {
      return _normalizeCurrencyCode(fromCurrency);
    }
    final displayCurrencyCode = toCurrency;
    final conversionCode = toCurrency;
    final normalizedDisplayCode = displayCurrencyCode == null
        ? null
        : _normalizeCurrencyCode(displayCurrencyCode);

    // Cuando la tasa se expresa en Bs, usamos el código de conversión
    // para mostrar la moneda extranjera (USD, EUR, USDT, etc.).
    // Si la tasa se expresa en una moneda distinta a Bs, usamos esa moneda
    // para evitar que varias tasas con el mismo destino se sobrescriban.
    if (normalizedDisplayCode != null && normalizedDisplayCode.isNotEmpty &&
        normalizedDisplayCode != 'VES') {
      return normalizedDisplayCode;
    }

    if (conversionCode != null && conversionCode.isNotEmpty) {
      return conversionCode;
    }

    return _normalizeCurrencyCode(rawCode);
  }

  String _rateBindingKey({
    required String? fromCurrency,
    required String? toCurrency,
    required String? name,
  }) {
    final from = _normalizeCurrencyCode(fromCurrency ?? '');
    final to = _normalizeCurrencyCode(toCurrency ?? '');
    final label = _asciiUpper(name ?? '');
    return '$from->$to|$label';
  }

  String _normalizeCurrencyCode(String value) {
    return _asciiUpper(value);
  }

  String _historyBindingKey(String value) => _asciiUpper(value);

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
    return ExchangeRate(
      id: code,
      code: code,
      name: code,
      value: 0,
      symbol: code.length <= 3 ? code : code.substring(0, 3),
      updatedAt: updatedAt,
      isOfficial: true,
      changePercent: 0,
      sparklineValues: const [],
      historyPoints: const [],
    );
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

  String _dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  ExchangeRate _rateFromLiveValue({
    required String id,
    required ExchangeRate base,
    required _SupabaseRateEntry entry,
    required DateTime updatedAt,
    required ExchangeRate? previous,
    required double Function(String code, double value) normalizeValue,
    required bool isFavorite,
  }) {
    final hasValidValue = entry.value != null && entry.value! > 0;
    final normalizedValue = hasValidValue
        ? normalizeValue(entry.code, entry.value!)
        : previous?.value ?? base.value;
    final sourceDate = hasValidValue
        ? entry.sourceUpdatedAtLabel ?? _dateLabel(updatedAt)
        : _fallbackSourceUpdatedAtLabel(previous, updatedAt);
    final moneyType = entry.fromCurrency ?? previous?.moneyType ?? entry.code;
    final inferredDisplayCurrencyCode =
        entry.conversionCode ?? entry.displayCurrencyCode;
    final displayCurrencyCode = hasValidValue
        ? (inferredDisplayCurrencyCode ?? entry.code)
        : (previous?.displayCurrencyCode ??
              inferredDisplayCurrencyCode ??
              entry.code);
    final displayValue = hasValidValue
        ? entry.value
        : previous?.displayValue ?? normalizedValue;

return ExchangeRate(
       id: id,
       code: base.code,
       name: entry.name ?? base.name,
       value: normalizedValue,
       symbol: entry.moneyTypeSymbol ?? entry.simbolo ?? base.symbol,
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
       moneyTypeSymbol:
           entry.moneyTypeSymbol ?? previous?.moneyTypeSymbol,
       conversionSymbol:
           entry.conversionSymbol ?? previous?.conversionSymbol,
       isFavorite: isFavorite,
     );
  }

  double _normalizeLiveRateValue(String code, double value) {
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
        } catch (_) {
          // Silently fail
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
        } catch (_) {}
      });
    }
  } catch (error, stackTrace) {
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
      } catch (_) {}
    });
  }
  return null;
}
}

class _SupabaseRates {
  const _SupabaseRates({required this.entries, required this.updatedAt});

  final List<_SupabaseRateEntry> entries;
  final DateTime updatedAt;

  _SupabaseRateEntry byCode(String code) {
    final entry = tryByCode(code);
    if (entry == null) {
      throw FormatException('Falta la tasa $code');
    }
    return entry;
  }

  _SupabaseRateEntry? tryByCode(String code) {
    for (final entry in entries) {
      if (entry.code == code) {
        return entry;
      }
    }
    return null;
  }

  _SupabaseRateEntry? tryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }
}

class _SupabaseRateEntry {
  const _SupabaseRateEntry({
    required this.id,
    required this.code,
    required this.value,
    this.name,
    this.moneyType,
    this.displayCurrencyCode,
    this.conversionCode,
    this.sourceUpdatedAtLabel,
    this.simbolo,
    this.moneyTypeSymbol,
    this.conversionSymbol,
  });

  final String id;
  final String code;
  final double? value;
  final String? name;
  final String? moneyType;
  final String? displayCurrencyCode;
  final String? conversionCode;
  final String? sourceUpdatedAtLabel;
  final String? simbolo;
  final String? moneyTypeSymbol;
  final String? conversionSymbol;

  String? get fromCurrency => moneyType;
}
