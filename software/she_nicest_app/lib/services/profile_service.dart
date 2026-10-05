import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// 本地睡眠档案：不创建账号，不保存密码，也不依赖登录会话。
class ProfileService {
  ProfileService._();

  static const String _profileKey = 'wanyu_local_profile';
  static const String _legacyUserKey = 'wanyu_auth_user';
  static const String _legacyTokenKey = 'wanyu_auth_token';

  static UserProfile _profile = const UserProfile.anonymous();

  static UserProfile get profile => _profile;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _profile = UserProfile.fromJson(decoded);
        }
      } else {
        // 迁移旧版本已经缓存的档案字段，但不继续保留旧登录态。
        final legacy = prefs.getString(_legacyUserKey);
        if (legacy != null && legacy.isNotEmpty) {
          final decoded = jsonDecode(legacy);
          if (decoded is Map<String, dynamic>) {
            _profile = UserProfile.fromJson(decoded);
            await _persist(prefs);
          }
        }
      }
      await prefs.remove(_legacyTokenKey);
      await prefs.remove(_legacyUserKey);
    } catch (_) {
      _profile = const UserProfile.anonymous();
    }
  }

  static Future<void> save(UserProfile profile) async {
    _profile = profile;
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  static Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(_profileKey, jsonEncode(_profile.toJson()));
  }
}
