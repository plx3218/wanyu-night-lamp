/// 本地睡眠档案模型。
class UserProfile {
  const UserProfile({
    required this.bedtime,
    required this.wakeTime,
    required this.apps,
    required this.replacementActivity,
  });

  const UserProfile.anonymous()
      : bedtime = '23:00',
        wakeTime = '07:30',
        apps = '',
        replacementActivity = '音乐';

  final String bedtime;
  final String wakeTime;
  final String apps;
  final String replacementActivity;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? json;
    return UserProfile(
      bedtime: (profile['bedtime'] as String?) ?? '23:00',
      wakeTime: (profile['wakeTime'] as String?) ?? '07:30',
      apps: (profile['apps'] as String?) ?? '',
      replacementActivity: (profile['replacementActivity'] as String?) ?? '音乐',
    );
  }

  Map<String, String> toJson() => {
        'bedtime': bedtime,
        'wakeTime': wakeTime,
        'apps': apps,
        'replacementActivity': replacementActivity,
      };

  UserProfile copyWith({
    String? bedtime,
    String? wakeTime,
    String? apps,
    String? replacementActivity,
  }) {
    return UserProfile(
      bedtime: bedtime ?? this.bedtime,
      wakeTime: wakeTime ?? this.wakeTime,
      apps: apps ?? this.apps,
      replacementActivity: replacementActivity ?? this.replacementActivity,
    );
  }
}
