import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/exchange_rate.dart';

class RateHistoryStore {
  RateHistoryStore._();

  static final RateHistoryStore instance = RateHistoryStore._();

  static const _databaseName = 'dollapp_rates.db';
  static const _tableName = 'rate_history';
  static const maxRecordsPerRate = 5;

  Database? _database;

  Future<Map<String, List<double>>> recordRates(
    List<ExchangeRate> rates,
  ) async {
    final database = await _openDatabase();
    final historyByCode = <String, List<double>>{};

    await database.transaction((txn) async {
      for (final rate in rates) {
        final value = rate.trendValue;
        if (value <= 0) {
          historyByCode[rate.code] = await _valuesForCode(txn, rate.code);
          continue;
        }

        final latestValue = await _latestValue(txn, rate.code);
        if (latestValue == null || latestValue != value) {
          await txn.insert(_tableName, {
            'code': rate.code,
            'value': value,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
          await _trimCodeHistory(txn, rate.code);
        }

        historyByCode[rate.code] = await _valuesForCode(txn, rate.code);
      }
    });

    return historyByCode;
  }

  Future<Map<String, List<double>>> historiesForCodes(
    Iterable<String> codes,
  ) async {
    final database = await _openDatabase();
    final histories = <String, List<double>>{};

    for (final code in codes) {
      histories[code] = await _valuesForCode(database, code);
    }

    return histories;
  }

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }

    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasePath, _databaseName),
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            value REAL NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_rate_history_code_created_at '
          'ON $_tableName (code, created_at DESC, id DESC)',
        );
      },
    );

    return _database!;
  }

  Future<double?> _latestValue(DatabaseExecutor executor, String code) async {
    final rows = await executor.query(
      _tableName,
      columns: const ['value'],
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return (rows.first['value'] as num).toDouble();
  }

  Future<List<double>> _valuesForCode(
    DatabaseExecutor executor,
    String code,
  ) async {
    final rows = await executor.query(
      _tableName,
      columns: const ['value'],
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'created_at DESC, id DESC',
      limit: maxRecordsPerRate,
    );

    return rows.reversed
        .map((row) => (row['value'] as num).toDouble())
        .toList();
  }

  Future<void> _trimCodeHistory(DatabaseExecutor executor, String code) async {
    final rows = await executor.query(
      _tableName,
      columns: const ['id'],
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'created_at DESC, id DESC',
      limit: -1,
      offset: maxRecordsPerRate,
    );

    for (final row in rows) {
      await executor.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}

extension ExchangeRateTrendValue on ExchangeRate {
  double get trendValue => displayValue ?? value;
}
