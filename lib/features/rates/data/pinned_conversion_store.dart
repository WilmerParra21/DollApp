import 'package:shared_preferences/shared_preferences.dart';

class PinnedConversion {
  const PinnedConversion({
    this.rateId,
    this.rateCode,
    this.fromCode,
    this.toCode,
  });

  final String? rateId;
  final String? rateCode;
  final String? fromCode;
  final String? toCode;

  bool get isEmpty {
    return (rateId == null || rateId!.isEmpty) &&
        (rateCode == null || rateCode!.isEmpty) &&
        (fromCode == null || fromCode!.isEmpty) &&
        (toCode == null || toCode!.isEmpty);
  }
}

class PinnedConversionStore {
  static const _rateIdKey = 'pinned_conversion_rate_id';
  static const _rateCodeKey = 'pinned_conversion_rate_code';
  static const _fromCodeKey = 'pinned_conversion_from_code';
  static const _toCodeKey = 'pinned_conversion_to_code';

  static Future<PinnedConversion> loadPinnedConversion() async {
    final prefs = await SharedPreferences.getInstance();
    return PinnedConversion(
      rateId: prefs.getString(_rateIdKey),
      rateCode: prefs.getString(_rateCodeKey),
      fromCode: prefs.getString(_fromCodeKey),
      toCode: prefs.getString(_toCodeKey),
    );
  }

  static Future<void> savePinnedConversion({
    required String fromCode,
    required String toCode,
    String? rateId,
    String? rateCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fromCodeKey, fromCode);
    await prefs.setString(_toCodeKey, toCode);

    if (rateId != null && rateId.isNotEmpty) {
      await prefs.setString(_rateIdKey, rateId);
    } else {
      await prefs.remove(_rateIdKey);
    }

    if (rateCode != null && rateCode.isNotEmpty) {
      await prefs.setString(_rateCodeKey, rateCode);
    } else {
      await prefs.remove(_rateCodeKey);
    }
  }

  static Future<void> clearPinnedConversion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rateIdKey);
    await prefs.remove(_rateCodeKey);
    await prefs.remove(_fromCodeKey);
    await prefs.remove(_toCodeKey);
  }
}
