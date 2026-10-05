import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:she_nicest_app/app_controller.dart';
import 'package:she_nicest_app/models/night_session.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/models/app_usage_segment.dart';
import 'package:she_nicest_app/services/usage_monitor_coordinator.dart';
import 'package:she_nicest_app/services/android_usage_service.dart';

import 'test_doubles.dart';

TonightPlan testPlan() => const TonightPlan(
      wakeTime: '07:30',
      recommendedBedtime: '23:30',
      windDownTime: '23:10',
      reminderTime: '23:20',
      steps: <PlanStepItem>[],
      replacementActivity: 'reading',
      extensionMinutes: 10,
      assumptions: <String>[],
      reply: 'plan',
      continuousThresholdMin: 20,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('controller attaches a plan and preserves the P0 state transition path', () async {
    final source = FakeUsageDataSource(
      const AndroidUsageQueryResult(
        hasAccess: true,
        segments: <AppUsageSegment>[],
      ),
    );
    final monitor = UsageMonitorCoordinator(source: source);
    final controller = AppController(
      FakeLampService(),
      FakeAiService(),
      usageMonitor: monitor,
    );

    controller.setTonightPlan(testPlan());
    expect(controller.hasTonightPlan, isTrue);
    expect(controller.nightSession.state, NightSessionState.planned);
    expect(controller.tonightPlan!.generatedAt, isNotNull);
    expect(controller.tonightPlan!.source, 'ai');

    final finished = await controller.prepareForSleep();
    expect(finished.allowed, isTrue);
    expect(controller.nightSession.state, NightSessionState.finished);
    expect(controller.nightSession.actionLog, contains('prepareForSleep'));

    controller.dispose();
  });
}
