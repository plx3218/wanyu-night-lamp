/// 用户档案 + 登录会话模型（对应后端 /api/auth/* 与 /api/profile 返回结构）
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.isAdmin,
    required this.bedtime,
    required this.wakeTime,
    required this.apps,
    required this.replacementActivity,
  });

  final int id;
  final String username;
  final bool isAdmin;
  final String bedtime;
  final String wakeTime;
  final String apps;
  final String replacementActivity;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? const {};
    return UserProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: (json['username'] as String?) ?? '',
      isAdmin: (json['isAdmin'] as bool?) ?? false,
      bedtime: (profile['bedtime'] as String?) ?? '23:00',
      wakeTime: (profile['wakeTime'] as String?) ?? '07:30',
      apps: (profile['apps'] as String?) ?? '',
      replacementActivity: (profile['replacementActivity'] as String?) ?? '音乐',
    );
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final UserProfile user;
}
