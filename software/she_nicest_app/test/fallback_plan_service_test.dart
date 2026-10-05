import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/services/fallback_plan_service.dart';

void main() {
  final now = DateTime(2026, 10, 5, 20, 30);

  test('creates the normal workday fallback plan with a 20 minute threshold', () {
    final plan = FallbackPlanService.create(
      now: now,
      bedtime: '23:30',
      wakeTime: '07:30',
      scenario: BedtimeScenario.normalWorkday,
      replacementActivity: '阅读',
    );

    expect(plan.source, 'fallback');
    expect(plan.generatedAt, now);
    expect(plan.wakeTime, '07:30');
    expect(plan.recommendedBedtime, '23:30');
    expect(plan.continuousThresholdMin, 20);
    expect(plan.steps, hasLength(3));
    expect(plan.replacementActivity, '阅读');
  });

  test('supports all four offline scenarios with the same valid shape', () {
    for (final scenario in BedtimeScenario.values) {
      final plan = FallbackPlanService.create(
        now: now,
        bedtime: '01:00',
        wakeTime: '08:00',
        scenario: scenario,
      );

      expect(plan.source, 'fallback');
      expect(plan.steps, hasLength(3));
      expect(plan.extensionMinutes, 10);
      expect(plan.wakeTime, '08:00');
      expect(plan.recommendedBedtime, '01:00');
      expect(plan.windDownTime, '00:40');
      expect(plan.reminderTime, '00:50');
      expect(plan.reply, isNotEmpty);
    }
  });

  test('uses the default bedtime and replacement when inputs are malformed', () {
    final plan = FallbackPlanService.create(
      now: now,
      bedtime: 'not-a-time',
      wakeTime: 'also-not-a-time',
      scenario: 'unknown-scenario',
    );

    expect(plan.recommendedBedtime, '23:30');
    expect(plan.wakeTime, '07:30');
    expect(plan.windDownTime, '23:10');
    expect(plan.reminderTime, '23:20');
    expect(plan.replacementActivity, '阅读');
  });
}
