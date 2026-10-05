import 'dart:convert';

/// 与 server.py SYSTEM_PROMPT 严格对齐的单步计划项
class PlanStepItem {
  final String time;   // "23:10"
  final String action; // "完成手边的事"
  final String? detail; // 可选的人性化补充说明（AI 输出时提供，本地兜底时生成）

  const PlanStepItem({
    required this.time,
    required this.action,
    this.detail,
  });

  factory PlanStepItem.fromJson(Map<String, dynamic> json) => PlanStepItem(
        time: (json['time'] as String? ?? '').trim(),
        action: (json['action'] as String? ?? '').trim(),
        detail: () {
          final d = json['detail'];
          return (d is String && d.trim().isNotEmpty) ? d.trim() : null;
        }(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'time': time,
        'action': action,
        if (detail != null) 'detail': detail,
      };

  PlanStepItem copyWith({String? time, String? action, String? detail}) => PlanStepItem(
        time: time ?? this.time,
        action: action ?? this.action,
        detail: detail ?? this.detail,
      );

  /// 本地兜底详情：当 AI 没有提供 detail 时，给每个 step 生成一段友好提示
  String displayDetail() {
    if (detail != null && detail!.isNotEmpty) return detail!;
    final a = action.toLowerCase();
    if (a.contains('收') || a.contains('完成')) return '把必须做的事简单收个尾，不用追求完美';
    if (a.contains('留意') || a.contains('提醒') || a.contains('阈值')) return '连续刷超时的话，我会轻轻提醒你';
    if (a.contains('结束') || a.contains('音乐') || a.contains('阅读') || a.contains('休息')) return '可以换成温柔的陪伴，也可以直接去休息';
    if (a.contains('洗漱')) return '给自己一段舒服的准备时间';
    if (a.contains('告别') || a.contains('手机')) return '不用硬憋：把想看的加到明天收藏夹';
    return '按自己舒服的节奏来就好';
  }
}

/// AI 对话输出的整晚计划
///
/// JSON schema 与 server.py 中 SYSTEM_PROMPT 的要求严格一致：
/// { reply, status, question, plan: { wake_time, recommended_bedtime, wind_down_time,
///   reminder_time, steps: [{time,action}], replacement_activity, extension_minutes },
///   assumptions: [] }
class TonightPlan {
  final String wakeTime;            // "07:30"
  final String recommendedBedtime;  // "23:30"
  final String windDownTime;        // "23:10"
  final String reminderTime;        // "23:20"
  final List<PlanStepItem> steps;   // 最多 3 步
  final String replacementActivity; // "音乐" / "阅读" / "白噪音" / "播客" / "直接休息" / "呼吸" / "香薰"
  // 注：Demo 2.0 版本**不内置音频播放器**（按用户要求移除白噪音/播客播放功能）。
  // replacementActivity 仅用于：
  //   1) AI plan 文案描述（让用户知道自己选了什么替代方式）
  //   2) 切换到 REPLACING 状态时灯光的主题色切换（无实际音频输出）
  // 如果后续要恢复音频播放，需引入 audio 插件并在此字段取值时再封装播放逻辑。
  final int extensionMinutes;       // 10 (默认可延 10 分钟)
  final List<String> assumptions;   // AI 的默认假设说明，UI 展示让用户感知到哪些值是猜的
  final bool urgentFinish;          // 用户说"立刻关灯/现在就睡"时的急停标记
  final int? continuousThresholdMin; // 连续刷到 X 分钟触发轻提醒（默认 10）
  final int? lightLevelWindDown;    // 留意时段目标亮度 0-100（预埋）
  final int? lightLevelBedtime;     // 入睡目标亮度 0-100（预埋）
  /// AI 对这个 plan 的自然回复语，Chat 消息也用它。和 plan 一起保存，
  /// PlanScreen 顶部卡片可复用它做副标题
  final String reply;
  /// Local generation metadata used for selecting the plan for tonight.
  final DateTime? generatedAt;
  /// `ai` for a server result, `fallback` for a local result.
  final String source;

  const TonightPlan({
    required this.wakeTime,
    required this.recommendedBedtime,
    required this.windDownTime,
    required this.reminderTime,
    required this.steps,
    required this.replacementActivity,
    required this.extensionMinutes,
    required this.assumptions,
    required this.reply,
    this.urgentFinish = false,
    this.continuousThresholdMin,
    this.lightLevelWindDown,
    this.lightLevelBedtime,
    this.generatedAt,
    this.source = 'ai',
  });

  factory TonightPlan.fromServerJson(Map<String, dynamic> serverJson) {
    // serverJson 是 {reply,status,question,plan,assumptions} 整包
    final plan = serverJson['plan'] is Map<String, dynamic>
        ? serverJson['plan'] as Map<String, dynamic>
        : <String, dynamic>{};
    final replyStr = (serverJson['reply'] as String? ?? '').trim();
    final assumptionsRaw = serverJson['assumptions'];
    final assumptionsList = <String>[
      if (assumptionsRaw is List)
        for (final a in assumptionsRaw)
          if (a is String && a.trim().isNotEmpty) a.trim(),
    ];
    final stepsRaw = plan['steps'];
    final stepsList = <PlanStepItem>[
      if (stepsRaw is List)
        for (final s in stepsRaw)
          if (s is Map<String, dynamic>) PlanStepItem.fromJson(s),
    ];
    int clampInt(dynamic v, int min, int max, int fallback) {
      if (v is int) return v.clamp(min, max);
      if (v is double) return v.round().clamp(min, max);
      if (v is String) {
        final n = int.tryParse(v.trim());
        if (n != null) return n.clamp(min, max);
      }
      return fallback;
    }
    return TonightPlan(
      wakeTime: _ensureTime(plan['wake_time'], '07:30'),
      recommendedBedtime: _ensureTime(plan['recommended_bedtime'], '23:30'),
      windDownTime: _ensureTime(plan['wind_down_time'], '23:10'),
      reminderTime: _ensureTime(plan['reminder_time'], '23:20'),
      steps: stepsList,
      replacementActivity: () {
        final r = plan['replacement_activity'];
        return (r is String && r.trim().isNotEmpty) ? r.trim() : '音乐';
      }(),
      extensionMinutes: clampInt(plan['extension_minutes'], 1, 120, 10),
      assumptions: assumptionsList,
      reply: replyStr.isNotEmpty
          ? replyStr
          : '好的，我帮你整理好了今晚的安排，看看合不合适？',
      urgentFinish: () {
        final u = serverJson['urgent_finish'] ?? plan['urgent_finish'];
        if (u is bool) return u;
        if (u is String) return u.trim().toLowerCase() == 'true';
        return false;
      }(),
      continuousThresholdMin: () {
        final v = plan['continuous_threshold_min'] ?? serverJson['continuous_threshold_min'];
        if (v == null) return null;
        return clampInt(v, 1, 240, 20);
      }(),
      lightLevelWindDown: () {
        final v = plan['light_level_wind_down'] ?? serverJson['light_level_wind_down'];
        if (v == null) return null;
        return clampInt(v, 0, 100, 40);
      }(),
      lightLevelBedtime: () {
        final v = plan['light_level_bedtime'] ?? serverJson['light_level_bedtime'];
        if (v == null) return null;
        return clampInt(v, 0, 100, 10);
      }(),
      generatedAt: () {
        final value = serverJson['generated_at'];
        return value is String ? DateTime.tryParse(value) : null;
      }(),
      source: () {
        final value = serverJson['source'];
        return value is String && value.trim().isNotEmpty ? value.trim() : 'ai';
      }(),
    );
  }

  static String _ensureTime(dynamic raw, String fallback) {
    if (raw is! String || raw.trim().isEmpty) return fallback;
    final t = raw.trim();
    // 正则匹配 XX:XX 或 X:XX；全角/半角冒号都接受
    final m = RegExp(r'(\d{1,2})[:：.](\d{2})').firstMatch(t);
    if (m == null) return fallback;
    final hh = int.parse(m.group(1)!).toString().padLeft(2, '0');
    final mm = m.group(2)!;
    return '$hh:$mm';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'reply': reply,
        'plan': <String, dynamic>{
          'wake_time': wakeTime,
          'recommended_bedtime': recommendedBedtime,
          'wind_down_time': windDownTime,
          'reminder_time': reminderTime,
          'steps': [for (final s in steps) s.toJson()],
          'replacement_activity': replacementActivity,
          'extension_minutes': extensionMinutes,
          if (continuousThresholdMin != null) 'continuous_threshold_min': continuousThresholdMin,
          if (lightLevelWindDown != null) 'light_level_wind_down': lightLevelWindDown,
          if (lightLevelBedtime != null) 'light_level_bedtime': lightLevelBedtime,
        },
        'assumptions': assumptions,
        if (urgentFinish) 'urgent_finish': true,
        if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
        'source': source,
      };

  TonightPlan copyWith({
    String? wakeTime,
    String? recommendedBedtime,
    String? windDownTime,
    String? reminderTime,
    List<PlanStepItem>? steps,
    String? replacementActivity,
    int? extensionMinutes,
    List<String>? assumptions,
    String? reply,
    bool? urgentFinish,
    int? continuousThresholdMin,
    int? lightLevelWindDown,
    int? lightLevelBedtime,
    DateTime? generatedAt,
    String? source,
  }) =>
      TonightPlan(
        wakeTime: wakeTime ?? this.wakeTime,
        recommendedBedtime: recommendedBedtime ?? this.recommendedBedtime,
        windDownTime: windDownTime ?? this.windDownTime,
        reminderTime: reminderTime ?? this.reminderTime,
        steps: steps ?? this.steps,
        replacementActivity: replacementActivity ?? this.replacementActivity,
        extensionMinutes: extensionMinutes ?? this.extensionMinutes,
        assumptions: assumptions ?? this.assumptions,
        reply: reply ?? this.reply,
        urgentFinish: urgentFinish ?? this.urgentFinish,
        continuousThresholdMin: continuousThresholdMin ?? this.continuousThresholdMin,
        lightLevelWindDown: lightLevelWindDown ?? this.lightLevelWindDown,
        lightLevelBedtime: lightLevelBedtime ?? this.lightLevelBedtime,
        generatedAt: generatedAt ?? this.generatedAt,
        source: source ?? this.source,
      );

  /// 对 steps 做规范化：如果 AI 返回 < 3 步且有头尾时间，本地自动补齐「现在（开始行动）/ windDown 留意 / reminder 结束」三段
  List<PlanStepItem> normalizedSteps() {
    if (steps.isNotEmpty) return steps;
    return <PlanStepItem>[
      PlanStepItem(time: '现在', action: '完成手边的事', detail: '把必须做的事简单收住'),
      PlanStepItem(
        time: windDownTime,
        action: '开始留意时间',
        detail: '连续刷 ${continuousThresholdMin ?? 10} 分钟时，我会轻轻提醒',
      ),
      PlanStepItem(
        time: reminderTime,
        action: '准备结束今天',
        detail: '可以换成$replacementActivity，也可以直接休息',
      ),
    ];
  }

  /// assumptions 友好拼接展示字符串
  String displayAssumptions() {
    if (assumptions.isEmpty) return '';
    return '• ' + assumptions.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n• ');
  }

  /// PlanScreen 顶部副标题格式：明早 07:30 起床。今晚可以在 23:30 左右准备入睡，不必立刻放下手机。
  String displayHeadline() {
    final wakeDisplay = _friendlyTime(wakeTime);
    final bedDisplay = _friendlyTime(recommendedBedtime);
    return '明早 $wakeDisplay 起床。今晚可以在 $bedDisplay 左右准备入睡，不必立刻放下手机。';
  }

  String displayThresholdText() {
    final m = continuousThresholdMin ?? 10;
    final t = _friendlyTime(windDownTime);
    return '从 $t 起，连续刷 ${m} 分钟我就轻轻提醒你。';
  }

  static String _friendlyTime(String t) {
    // 去除前导 0：07:30 → 7:30
    final parts = t.split(':');
    if (parts.length != 2) return t;
    final h = int.tryParse(parts.first);
    if (h == null) return t;
    return '$h:${parts[1]}';
  }

  String toDebugJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
