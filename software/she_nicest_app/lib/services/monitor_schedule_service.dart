import '../models/tonight_plan.dart';
import '../models/user_profile.dart';

enum MonitorScheduleSource { todayPlan, profile }

class MonitorSchedule {
  const MonitorSchedule({
    required this.targetBedtime,
    required this.startAt,
    required this.source,
    this.lockedAt,
  });

  final DateTime targetBedtime;
  final DateTime startAt;
  final MonitorScheduleSource source;
  final DateTime? lockedAt;

  MonitorSchedule lock(DateTime at) => MonitorSchedule(
        targetBedtime: targetBedtime,
        startAt: startAt,
        source: source,
        lockedAt: lockedAt ?? at,
      );
}

class MonitorScheduleService {
  const MonitorScheduleService._();

  static MonitorSchedule resolveFor(
    DateTime day,
    TonightPlan? latestPlan,
    UserProfile profile,
  ) {
    final bedtime = latestPlan?.recommendedBedtime ?? profile.bedtime;
    final targetBedtime = _resolveBedtime(day, bedtime);
    return MonitorSchedule(
      targetBedtime: targetBedtime,
      startAt: targetBedtime.subtract(const Duration(hours: 2)),
      source: latestPlan == null
          ? MonitorScheduleSource.profile
          : MonitorScheduleSource.todayPlan,
    );
  }

  static DateTime _resolveBedtime(DateTime day, String raw) {
    final match = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(raw.trim());
    final hour = int.tryParse(match?.group(1) ?? '') ?? 23;
    final minute = int.tryParse(match?.group(2) ?? '') ?? 0;
    var target = DateTime(day.year, day.month, day.day, hour.clamp(0, 23), minute.clamp(0, 59));
    if (hour < 12) target = target.add(const Duration(days: 1));
    return target;
  }
}
