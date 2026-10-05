import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/user_profile.dart';

void main() {
  test('creates a local profile without account credentials', () {
    final profile = UserProfile.anonymous();

    expect(profile.bedtime, '23:00');
    expect(profile.wakeTime, '07:30');
    expect(profile.apps, isEmpty);
    expect(profile.replacementActivity, '音乐');
  });
}
