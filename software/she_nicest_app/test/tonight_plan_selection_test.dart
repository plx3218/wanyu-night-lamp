import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/services/tonight_plan_selection_service.dart';

TonightPlan plan(DateTime generatedAt, String bedtime) => TonightPlan(
      wakeTime: '07:30',
      recommendedBedtime: bedtime,
      windDownTime: '23:10',
      reminderTime: '23:20',
      steps: const [],
      replacementActivity: '阅读',
      extensionMinutes: 10,
      assumptions: const [],
      reply: 'plan',
      generatedAt: generatedAt,
      source: 'ai',
    );

void main() {
  final day = DateTime(2026, 10, 5);

  test('selects the latest plan generated on the same local day', () {
    final earlier = plan(DateTime(2026, 10, 5, 18), '23:00');
    final latest = plan(DateTime(2026, 10, 5, 21), '23:30');
    final previousDay = plan(DateTime(2026, 10, 4, 23), '22:30');

    expect(
      TonightPlanSelectionService.selectLatestForDay(day, [previousDay, earlier, latest]),
      same(latest),
    );
  });

  test('does not replace a locked current plan until the next day', () {
    final current = plan(DateTime(2026, 10, 5, 18), '23:00');
    final newer = plan(DateTime(2026, 10, 5, 21), '23:30');

    expect(
      TonightPlanSelectionService.selectLatestForDay(
        day,
        [current, newer],
        currentPlan: current,
        monitoringLocked: true,
      ),
      same(current),
    );
  });

  test('midnight belongs to the calendar day of generation', () {
    final midnight = plan(DateTime(2026, 10, 6, 0, 5), '01:00');
    final dayFive = plan(DateTime(2026, 10, 5, 23, 55), '23:30');

    expect(
      TonightPlanSelectionService.selectLatestForDay(day, [dayFive, midnight]),
      same(dayFive),
    );
    expect(
      TonightPlanSelectionService.selectLatestForDay(
        DateTime(2026, 10, 6),
        [dayFive, midnight],
      ),
      same(midnight),
    );
  });
}
