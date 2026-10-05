import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/night_usage_record.dart';

class NightRecordException implements Exception {
  const NightRecordException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NightRecordService {
  NightRecordService({Future<SharedPreferences> Function()? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'wanyu_night_usage_record_';
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<void> saveLocal(NightUsageRecord record) async {
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(_keyFor(record.day), record.encode());
    } catch (_) {
      throw const NightRecordException('今晚记录保存失败，请检查本机存储空间后重试。');
    }
  }

  Future<NightUsageRecord?> loadByDate(DateTime day) async {
    try {
      final prefs = await _preferencesLoader();
      final raw = prefs.getString(_keyFor(day));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('invalid night record');
      }
      return NightUsageRecord.fromJson(decoded);
    } catch (error) {
      if (error is NightRecordException) rethrow;
      throw const NightRecordException('今晚记录读取失败，未将缺失记录当作 0 分钟。');
    }
  }

  Future<Map<String, dynamic>?> buildDailySummary(DateTime day) async {
    final record = await loadByDate(day);
    return record?.toDailySummaryJson();
  }

  static String _keyFor(DateTime day) =>
      '$_keyPrefix${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
