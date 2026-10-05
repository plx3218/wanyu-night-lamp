import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/app_usage_segment.dart';
import 'package:she_nicest_app/services/android_usage_service.dart';
import 'package:she_nicest_app/services/monitor_schedule_service.dart';
import 'package:she_nicest_app/services/usage_monitor_coordinator.dart';

class FakeUsageDataSource implements UsageMonitorDataSource {
  FakeUsageDataSource(this.result);

  AndroidUsageQueryResult result;
  int queryCount = 0;

  @override
  Future<AndroidUsageQueryResult> querySegments(Duration window) async {
    queryCount += 1;
    return result;
  }
}

void main() {
  final now = DateTime(2026, 10, 5, 22, 30);
  final schedule = MonitorSchedule(
    targetBedtime: DateTime(2026, 10, 5, 23, 30),
    startAt: DateTime(2026, 10, 5, 21, 30),
    source: MonitorScheduleSource.profile,
  );

  test('locks the schedule and emits a usage snapshot on refresh', () async {
    final source = FakeUsageDataSource(
      AndroidUsageQueryResult(
        hasAccess: true,
        sampledAt: now,
        segments: [
          AppUsageSegment(
            packageName: 'tv.danmaku.bili',
            startedAt: now.subtract(const Duration(minutes: 20)),
            endedAt: now,
          ),
        ],
      ),
    );
    final coordinator = UsageMonitorCoordinator(
      source: source,
      now: () => now,
      pollInterval: const Duration(hours: 1),
    );
    final events = <UsageMonitorEvent>[];
    final subscription = coordinator.events.listen(events.add);

    await coordinator.start(schedule);

    expect(coordinator.currentSchedule?.lockedAt, now);
    expect(source.queryCount, 1);
    expect(events.map((event) => event.type), <UsageMonitorEventType>[
      UsageMonitorEventType.started,
      UsageMonitorEventType.snapshot,
    ]);
    expect(events.last.snapshot?.thresholdReached, isTrue);

    await subscription.cancel();
    coordinator.dispose();
  });

  test('emits permission required instead of silently succeeding', () async {
    final coordinator = UsageMonitorCoordinator(
      source: FakeUsageDataSource(
        const AndroidUsageQueryResult(
          hasAccess: false,
          segments: <AppUsageSegment>[],
          errorCode: 'usage_access_required',
        ),
      ),
      now: () => now,
      pollInterval: const Duration(hours: 1),
    );
    final events = <UsageMonitorEvent>[];
    final subscription = coordinator.events.listen(events.add);

    await coordinator.start(schedule);

    expect(events.last.type, UsageMonitorEventType.permissionRequired);
    expect(events.last.errorCode, 'usage_access_required');

    await subscription.cancel();
    coordinator.dispose();
  });

  test('does not replace a locked schedule with a later plan', () async {
    final source = FakeUsageDataSource(
      const AndroidUsageQueryResult(
        hasAccess: true,
        segments: <AppUsageSegment>[],
      ),
    );
    final coordinator = UsageMonitorCoordinator(
      source: source,
      now: () => now,
      pollInterval: const Duration(hours: 1),
    );
    final laterSchedule = MonitorSchedule(
      targetBedtime: DateTime(2026, 10, 6),
      startAt: DateTime(2026, 10, 5, 22),
      source: MonitorScheduleSource.todayPlan,
    );

    await coordinator.start(schedule);
    await coordinator.start(laterSchedule);

    expect(coordinator.currentSchedule?.targetBedtime, schedule.targetBedtime);
    coordinator.dispose();
  });

  test('emits stopped and releases the polling timer', () async {
    final coordinator = UsageMonitorCoordinator(
      source: FakeUsageDataSource(
        const AndroidUsageQueryResult(
          hasAccess: true,
          segments: <AppUsageSegment>[],
        ),
      ),
      now: () => now,
      pollInterval: const Duration(hours: 1),
    );
    final events = <UsageMonitorEvent>[];
    final subscription = coordinator.events.listen(events.add);

    await coordinator.start(schedule);
    await coordinator.stop();

    expect(events.last.type, UsageMonitorEventType.stopped);
    await subscription.cancel();
    coordinator.dispose();
  });
}
