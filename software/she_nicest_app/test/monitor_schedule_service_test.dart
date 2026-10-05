import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/models/user_profile.dart';
import 'package:she_nicest_app/services/monitor_schedule_service.dart';

void main() {
  TonightPlan plan(String bedtime) => TonightPlan(
        wakeTime: '07:30',
        recommendedBedtime: bedtime,
        windDownTime: bedtime,
        reminderTime: bedtime,
        steps: const [],
        replacementActivity: '阅读',
        extensionMinutes: 10,
        assumptions: const [],
        reply: 'plan',
      );

  UserProfile profile({String bedtime = '23:30'}) => UserProfile(
        id: 1,
        username: 'tester',
        isAdmin: false,
        bedtime: bedtime,
        wakeTime: '07:30',
        apps: '短视频',
        replacementActivity: '阅读',
      );

  test('prefers the latest plan and starts two hours before target bedtime', () {
    final schedule = MonitorScheduleService.resolveFor(
      DateTime(2026, 10, 5),
      plan('23:30'),
      profile(bedtime: '22:00'),
    );

    expect(schedule.source, MonitorScheduleSource.todayPlan);
    expect(schedule.targetBedtime, DateTime(2026, 10, 5, 23, 30));
    expect(schedule.startAt, DateTime(2026, 10, 5, 21, 30));
    expect(schedule.lockedAt, isNull);
  });

  test('falls back to the profile bedtime when there is no plan', () {
    final schedule = MonitorScheduleService.resolveFor(
      DateTime(2026, 10, 5),
      null,
      profile(),
    );

    expect(schedule.source, MonitorScheduleSource.profile);
    expect(schedule.targetBedtime, DateTime(2026, 10, 5, 23, 30));
    expect(schedule.startAt, DateTime(2026, 10, 5, 21, 30));
  });

  test('places after-midnight bedtime on the next calendar day', () {
    final schedule = MonitorScheduleService.resolveFor(
      DateTime(2026, 10, 5),
      null,
      profile(bedtime: '00:30'),
    );

    expect(schedule.targetBedtime, DateTime(2026, 10, 6, 0, 30));
    expect(schedule.startAt, DateTime(2026, 10, 5, 22, 30));
  });

  test('locking a schedule records the lock time without changing its window', () {
    final schedule = MonitorScheduleService.resolveFor(
      DateTime(2026, 10, 5),
      plan('23:30'),
      profile(),
    );
    final lockedAt = DateTime(2026, 10, 5, 21, 35);
    final locked = schedule.lock(lockedAt);

    expect(locked.lockedAt, lockedAt);
    expect(locked.startAt, schedule.startAt);
    expect(locked.targetBedtime, schedule.targetBedtime);
  });
}
