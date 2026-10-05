import '../models/tonight_plan.dart';

class TonightPlanSelectionService {
  const TonightPlanSelectionService._();

  static TonightPlan? selectLatestForDay(
    DateTime day,
    List<TonightPlan> candidates, {
    TonightPlan? currentPlan,
    bool monitoringLocked = false,
  }) {
    if (monitoringLocked) return currentPlan;
    final sameDay = candidates
        .where((plan) => _isSameDay(plan.generatedAt, day))
        .toList()
      ..sort((a, b) => a.generatedAt!.compareTo(b.generatedAt!));
    return sameDay.isEmpty ? null : sameDay.last;
  }

  static bool _isSameDay(DateTime? value, DateTime day) =>
      value != null &&
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;
}
