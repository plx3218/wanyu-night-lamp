import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';

/// 后端返回的业务错误（400/401/409 的 error 字段）
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiService {
  ApiService._();
  static const String baseUrl = 'http://121.40.96.105:8000';

  static Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};
  static Map<String, String> _authHeaders(String token) => {
        ..._jsonHeaders,
        'Authorization': 'Bearer $token',
      };

  static void _throwIfError(http.Response resp) {
    if (resp.statusCode >= 400) {
      try {
        final data = jsonDecode(resp.body);
        throw ApiException((data['error'] as String?) ?? '请求失败（${resp.statusCode}）');
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException('网络异常，请稍后再试');
      }
    }
  }

  static AuthSession _parseSession(String body) {
    final data = jsonDecode(body);
    final token = (data['token'] as String?) ?? '';
    final user = UserProfile.fromJson((data['user'] as Map<String, dynamic>?) ?? const {});
    if (token.isEmpty) throw ApiException('服务器返回异常，请重试');
    return AuthSession(token: token, user: user);
  }

  /// 注册 + 首次建档（管理员账号在服务端配置，注册时自动标记 isAdmin）
  static Future<AuthSession> register({
    required String username,
    required String password,
    required String bedtime,
    required String wakeTime,
    required String apps,
    required String replacementActivity,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'username': username,
            'password': password,
            'bedtime': bedtime,
            'wakeTime': wakeTime,
            'apps': apps,
            'replacementActivity': replacementActivity,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _throwIfError(resp);
    return _parseSession(resp.body);
  }

  static Future<AuthSession> login(String username, String password) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: _jsonHeaders,
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    _throwIfError(resp);
    return _parseSession(resp.body);
  }

  static Future<void> logout(String token) async {
    try {
      await http
          .post(Uri.parse('$baseUrl/api/auth/logout'), headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // 登出失败不影响本地清理
    }
  }

  static Future<UserProfile> fetchProfile(String token) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/api/profile'), headers: _authHeaders(token))
        .timeout(const Duration(seconds: 15));
    _throwIfError(resp);
    final data = jsonDecode(resp.body);
    return UserProfile.fromJson((data['user'] as Map<String, dynamic>?) ?? const {});
  }

  /// 更新档案：传 null 的字段保持原值（服务端 pick）
  static Future<UserProfile> updateProfile(
    String token, {
    String? bedtime,
    String? wakeTime,
    String? apps,
    String? replacementActivity,
  }) async {
    final body = <String, dynamic>{};
    if (bedtime != null) body['bedtime'] = bedtime;
    if (wakeTime != null) body['wakeTime'] = wakeTime;
    if (apps != null) body['apps'] = apps;
    if (replacementActivity != null) body['replacementActivity'] = replacementActivity;
    final resp = await http
        .put(Uri.parse('$baseUrl/api/profile'), headers: _authHeaders(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    _throwIfError(resp);
    final data = jsonDecode(resp.body);
    return UserProfile.fromJson((data['user'] as Map<String, dynamic>?) ?? const {});
  }
}
