import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:she_nicest_app/models/night_usage_record.dart';
import 'package:she_nicest_app/services/night_record_service.dart';

NightUsageRecord record(DateTime day, {int minutes = 42}) => NightUsageRecord(
      day: day,
      monitorStartAt: DateTime(day.year, day.month, day.day, 21),
      targetBedtime: DateTime(day.year, day.month, day.day, 23, 30),
      entertainmentMinutes: minutes,
      reminderCount: 1,
      continueCount: 1,
      replacementSelections: const ['阅读'],
      prepareForSleepAt: DateTime(day.year, day.month, day.day, 23, 25),
      phoneIdleAt: DateTime(day.year, day.month, day.day, 23, 28),
      usageAccessGranted: true,
      monitorStatus: 'completed',
      dataSource: 'android_usage_stats',
      phase: NightExperimentPhase.intervention,
      remindersEnabled: true,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists a record and loads it after a new service instance', () async {
    final day = DateTime(2026, 10, 5);
    await NightRecordService().saveLocal(record(day));

    final loaded = await NightRecordService().loadByDate(day);
    expect(loaded, isNotNull);
    expect(loaded!.entertainmentMinutes, 42);
    expect(loaded.phoneIdleAt, DateTime(2026, 10, 5, 23, 28));
  });

  test('repeated save replaces only the same date and keeps dates separate', () async {
    final firstDay = DateTime(2026, 10, 5);
    final secondDay = DateTime(2026, 10, 6);
    final service = NightRecordService();
    await service.saveLocal(record(firstDay, minutes: 10));
    await service.saveLocal(record(firstDay, minutes: 20));
    await service.saveLocal(record(secondDay, minutes: 30));

    expect((await service.loadByDate(firstDay))!.entertainmentMinutes, 20);
    expect((await service.loadByDate(secondDay))!.entertainmentMinutes, 30);
  });

  test('daily summary contains aggregates but no raw app/event fields', () async {
    final day = DateTime(2026, 10, 5);
    final service = NightRecordService();
    await service.saveLocal(record(day));

    final summary = await service.buildDailySummary(day);
    expect(summary, isNotNull);
    expect(summary!['entertainment_minutes'], 42);
    expect(summary['replacement_count'], 1);
    expect(summary.containsKey('replacement_selections'), isFalse);
    expect(summary.containsKey('package_name'), isFalse);
    expect(summary.containsKey('segments'), isFalse);
  });

  test('missing date stays missing instead of becoming zero minutes', () async {
    final summary = await NightRecordService().buildDailySummary(DateTime(2026, 10, 7));
    expect(summary, isNull);
  });
}
