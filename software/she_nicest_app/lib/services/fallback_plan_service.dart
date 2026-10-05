import '../models/tonight_plan.dart';

enum BedtimeScenario {
  normalWorkday,
  overtime,
  emotionalFatigue,
  importantNextMorning,
}

/// Generates a complete local plan when the AI server cannot be trusted or reached.
class FallbackPlanService {
  const FallbackPlanService._();

  static TonightPlan create({
    required DateTime now,
    required String bedtime,
    required String wakeTime,
    required Object? scenario,
    String? replacementActivity,
  }) {
    final bed = _parseTime(bedtime, 23, 30);
    final wake = _parseTime(wakeTime, 7, 30);
    final target = DateTime(now.year, now.month, now.day, bed.$1, bed.$2);
    final windDown = _format(target.subtract(const Duration(minutes: 20)));
    final reminder = _format(target.subtract(const Duration(minutes: 10)));
    final activity = replacementActivity?.trim().isNotEmpty == true
        ? replacementActivity!.trim()
        : '阅读';
    final copy = _copyFor(_normalizeScenario(scenario), activity);

    return TonightPlan(
      wakeTime: _formatClock(wake),
      recommendedBedtime: _formatClock(bed),
      windDownTime: windDown,
      reminderTime: reminder,
      steps: <PlanStepItem>[
        PlanStepItem(time: windDown, action: copy.first),
        PlanStepItem(time: reminder, action: copy.second),
        PlanStepItem(time: _format(target), action: copy.third),
      ],
      replacementActivity: activity,
      extensionMinutes: 10,
      assumptions: const <String>[
        '本地保底计划：未上传实际浏览内容',
        '连续使用同类娱乐 App 达到 20 分钟后提醒',
      ],
      reply: copy.reply,
      continuousThresholdMin: 20,
      generatedAt: now,
      source: 'fallback',
    );
  }

  static ({String first, String second, String third, String reply}) _copyFor(
    BedtimeScenario scenario,
    String activity,
  ) {
    switch (scenario) {
      case BedtimeScenario.overtime:
        return (
          first: '把加班后的收尾事项写下来',
          second: '离开工作信息，换成$activity',
          third: '关灯，准备入睡',
          reply: '今晚已经辛苦了，先把工作放到明天，给自己一段真正的收尾时间。',
        );
      case BedtimeScenario.emotionalFatigue:
        return (
          first: '先做一个不需要思考的收尾动作',
          second: '让手机离手，换成$activity',
          third: '关灯，准备入睡',
          reply: '如果今天很累，不需要再证明什么；我们把今晚安排得轻一点。',
        );
      case BedtimeScenario.importantNextMorning:
        return (
          first: '写下明早最重要的一件事',
          second: '停止刷屏，换成$activity',
          third: '关灯，准备入睡',
          reply: '明早有重要的事，更值得用一段稳定的睡眠来准备。',
        );
      case BedtimeScenario.normalWorkday:
        return (
          first: '完成手边最后一件小事',
          second: '停止刷屏，换成$activity',
          third: '关灯，准备入睡',
          reply: '今晚不需要一下子做得完美，按这三个小步骤慢慢收尾就好。',
        );
    }
  }

  static BedtimeScenario _normalizeScenario(Object? value) {
    if (value is BedtimeScenario) return value;
    switch (value?.toString()) {
      case 'overtime':
      case 'BedtimeScenario.overtime':
        return BedtimeScenario.overtime;
      case 'emotionalFatigue':
      case 'BedtimeScenario.emotionalFatigue':
        return BedtimeScenario.emotionalFatigue;
      case 'importantNextMorning':
      case 'BedtimeScenario.importantNextMorning':
        return BedtimeScenario.importantNextMorning;
      default:
        return BedtimeScenario.normalWorkday;
    }
  }

  static (int, int) _parseTime(String raw, int fallbackHour, int fallbackMinute) {
    final match = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(raw.trim());
    final hour = int.tryParse(match?.group(1) ?? '') ?? fallbackHour;
    final minute = int.tryParse(match?.group(2) ?? '') ?? fallbackMinute;
    return (hour.clamp(0, 23), minute.clamp(0, 59));
  }

  static String _formatClock((int, int) value) =>
      '${value.$1.toString().padLeft(2, '0')}:${value.$2.toString().padLeft(2, '0')}';

  static String _format(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
