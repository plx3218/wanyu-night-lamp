import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'api_service.dart';

/// 全局登录态（单例）：App 启动时 load()，登录/注册后 save()，退出 clear()
class AuthService {
  AuthService._();
  static const String _kTokenKey = 'wanyu_auth_token';
  static const String _kUserKey = 'wanyu_auth_user';

  static AuthSession? _session;

  static AuthSession? get session => _session;
  static bool get isLoggedIn => _session != null;
  static UserProfile? get user => _session?.user;
  static bool get isAdmin => _session?.user.isAdmin ?? false;
  static String? get token => _session?.token;

  /// App 启动时调用：从本地恢复登录态
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kTokenKey);
      final rawUser = prefs.getString(_kUserKey);
      if (token == null || token.isEmpty || rawUser == null) return;
      final map = jsonDecode(rawUser);
      if (map is Map<String, dynamic>) {
        _session = AuthSession(token: token, user: UserProfile.fromJson(map));
        debugPrint('[Auth] 登录态已恢复: ${_session!.user.username}');
      }
    } catch (e) {
      debugPrint('[Auth] 登录态恢复失败: $e');
      _session = null;
    }
  }

  /// 登录/注册成功后调用：保存会话
  static Future<void> save(AuthSession s) async {
    _session = s;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, s.token);
      await prefs.setString(_kUserKey, jsonEncode({
        'id': s.user.id,
        'username': s.user.username,
        'isAdmin': s.user.isAdmin,
        'profile': {
          'bedtime': s.user.bedtime,
          'wakeTime': s.user.wakeTime,
          'apps': s.user.apps,
          'replacementActivity': s.user.replacementActivity,
        },
      }));
    } catch (e) {
      debugPrint('[Auth] 登录态保存失败: $e');
    }
  }

  /// 档案编辑后更新内存 + 本地缓存
  static void updateCachedUser(UserProfile u) {
    final s = _session;
    if (s == null) return;
    _session = AuthSession(token: s.token, user: u);
    save(_session!);
  }

  /// 退出登录：清服务端 token + 本地缓存
  static Future<void> clear() async {
    final t = _session?.token;
    _session = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokenKey);
      await prefs.remove(_kUserKey);
    } catch (_) {}
    if (t != null) await ApiService.logout(t);
  }
}
