import '../models/exchange_rate_snapshot.dart';

abstract class ExchangeRateRepository {
  Future<ExchangeRateSnapshot> getRates({bool forceRefresh = false});
}
