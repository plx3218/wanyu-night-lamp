import 'dart:convert';

enum NightExperimentPhase { baseline, intervention }

/// One privacy-safe nightly record. Raw package names and event segments never
/// appear in this model or in its daily summary payload.
class NightUsageRecord {
  const NightUsageRecord({
    required this.day,
    required this.monitorStartAt,
    required this.targetBedtime,
    required this.entertainmentMinutes,
    required this.reminderCount,
    required this.continueCount,
    required this.replacementSelections,
    required this.prepareForSleepAt,
    required this.phoneIdleAt,
    required this.usageAccessGranted,
    required this.monitorStatus,
    required this.dataSource,
    required this.phase,
    required this.remindersEnabled,
  });

  final DateTime day;
  final DateTime? monitorStartAt;
  final DateTime? targetBedtime;
  final int entertainmentMinutes;
  final int reminderCount;
  final int continueCount;
  final List<String> replacementSelections;
  final DateTime? prepareForSleepAt;
  /// Proxy metric: the last observed phone activity, not actual sleep time.
  final DateTime? phoneIdleAt;
  final bool usageAccessGranted;
  final String monitorStatus;
  final String dataSource;
  final NightExperimentPhase phase;
  final bool remindersEnabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'day': _dateKey(day),
        'monitor_start_at': monitorStartAt?.toIso8601String(),
        'target_bedtime': targetBedtime?.toIso8601String(),
        'entertainment_minutes': entertainmentMinutes,
        'reminder_count': reminderCount,
        'continue_count': continueCount,
        'replacement_selections': replacementSelections,
        'prepare_for_sleep_at': prepareForSleepAt?.toIso8601String(),
        'phone_idle_proxy_at': phoneIdleAt?.toIso8601String(),
        'usage_access_granted': usageAccessGranted,
        'monitor_status': monitorStatus,
        'data_source': dataSource,
        'phase': phase.name,
        'reminders_enabled': remindersEnabled,
      };

  /// Upload-safe payload: aggregate fields only, with no raw app identifiers.
  Map<String, dynamic> toDailySummaryJson() => <String, dynamic>{
        'day': _dateKey(day),
        'monitor_start_at': monitorStartAt?.toIso8601String(),
        'target_bedtime': targetBedtime?.toIso8601String(),
        'entertainment_minutes': entertainmentMinutes,
        'reminder_count': reminderCount,
        'continue_count': continueCount,
        'replacement_count': replacementSelections.length,
        'prepare_for_sleep_at': prepareForSleepAt?.toIso8601String(),
        'phone_idle_proxy_at': phoneIdleAt?.toIso8601String(),
        'usage_access_granted': usageAccessGranted,
        'monitor_status': monitorStatus,
        'data_source': dataSource,
        'phase': phase.name,
        'reminders_enabled': remindersEnabled,
      };

  factory NightUsageRecord.fromJson(Map<String, dynamic> json) {
    final day = DateTime.tryParse(json['day'] as String? ?? '') ?? DateTime.now();
    DateTime? parseDate(dynamic value) =>
        value is String ? DateTime.tryParse(value) : null;
    final selections = json['replacement_selections'];
    final phase = json['phase'] == NightExperimentPhase.baseline.name
        ? NightExperimentPhase.baseline
        : NightExperimentPhase.intervention;
    return NightUsageRecord(
      day: day,
      monitorStartAt: parseDate(json['monitor_start_at']),
      targetBedtime: parseDate(json['target_bedtime']),
      entertainmentMinutes: _intValue(json['entertainment_minutes']),
      reminderCount: _intValue(json['reminder_count']),
      continueCount: _intValue(json['continue_count']),
      replacementSelections: <String>[
        if (selections is List)
          for (final item in selections)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      prepareForSleepAt: parseDate(json['prepare_for_sleep_at']),
      phoneIdleAt: parseDate(json['phone_idle_proxy_at']),
      usageAccessGranted: json['usage_access_granted'] == true,
      monitorStatus: json['monitor_status'] as String? ?? 'unknown',
      dataSource: json['data_source'] as String? ?? 'local',
      phase: phase,
      remindersEnabled: json['reminders_enabled'] != false,
    );
  }

  String encode() => jsonEncode(toJson());

  static int _intValue(dynamic value) => value is num ? value.toInt().clamp(0, 1440) : 0;

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
