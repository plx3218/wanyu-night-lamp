import 'dart:convert';
import 'tonight_plan.dart';

/// FR-11 SheNicest 睡前守护八状态
///
/// 状态转移关系（严格按 PRD 2.0 §11）：
/// UNPLANNED ──[confirmPlan]──▶ PLANNED ──[开始守护 / 达到 windDown 时间]──▶ OBSERVING
/// OBSERVING ──[连续刷 X 分钟超时]──▶ NUDGED ──[用户: 换替代活动]──▶ REPLACING
/// OBSERVING ──[立刻结束]──▶ FINISHED
/// NUDGED ──[用户: 再延长 N 分钟]──▶ EXTENDING ──[延长时间到期]──▶ NUDGED
/// NUDGED ──[用户: 结束今天]──▶ FINISHED
/// NUDGED ──[用户: 本次不提醒]──▶ REMINDER_MUTED（当日不再触发灯光通知，App 记录仍继续）
/// REMINDER_MUTED ──[阈值再次到达]──▶ (不灯光 / 不通知) ──▶ REMINDER_MUTED
/// REPLACING ──[用户: 准备结束]──▶ FINISHED
/// FINISHED ──[用户: 我还要看一下]──▶ REPLACING
/// 任意状态 ──[restoreLight 手动]──▶ PLANNED（退出守护，仅做紧急照明，不触发阈值）
enum NightSessionState {
  unplanned,   // 还没生成 plan / 已 reset
  planned,     // plan 已确认但还没到 wind_down 时间（暖光就绪）
  observing,   // 守护中：观测连续使用时长
  nudged,      // 轻提醒（灯光 + 本地通知）
  replacing,   // 替代活动模式（音乐/阅读/白噪音）
  extending,   // 延长中（保持亮度不提醒）
  finished,    // 今晚结束（5% 夜灯）
  muted,       // 本次提醒静音（用户点了"这次不用提醒我"）
}

/// 硬件命令（FR-08 11 条指令对齐）；可直接传给 ESP32 / 模拟灯光 / mock
enum LampCommandId {
  lightLevel3,   // LIGHT_LEVEL_3 : 高亮度（日常照明 / RESTORE_LIGHT）
  lightLevel2,   // LIGHT_LEVEL_2 : 中等暖光（PLANNED 就绪）
  lightLevel1,   // LIGHT_LEVEL_1 : 弱光（NUDGED 提示）
  windDown,      // WIND_DOWN     : 呼吸 + 渐变亮度（OBSERVING）
  nudge,         // LIGHT_LEVEL_1 别名（保持命令语义独立）
  extend,        // EXTEND_N_MIN  : 保持当前亮度 N 分钟
  finish,        // FINISH        : 5% 夜灯（结束）
  restoreLight,  // RESTORE_LIGHT : 紧急照明（回到 LIGHT_LEVEL_3 不进入守护）
  enterReplace,  // REPLACE_MODE  : 替代活动（偏暖、无闪烁）
  mute,          // MUTE_REMINDER : 暂时停止提醒（灯光不变化）
  unmute,        // UNMUTE        : 恢复提醒
}

/// 硬件命令结果
enum CommandResult {
  accepted,       // ESP32 返回 ack=accepted=true + request_id 匹配
  offline,        // 网络异常 / 未连接（按 FR-13 降级：不阻塞 UI 流程）
  timeout,        // 超时但重试后仍无响应（视同 offline）
  ackMismatch,    // 收到了 ack，但 request_id 不一致（丢弃，认为无效）
  notReady,       // session 还没 setTonightPlan 就派发命令 → 拒绝
}

class CommandOutcome {
  final CommandResult result;
  final String requestId;
  final String? rawAckBody;
  final String? errorMessage;
  const CommandOutcome(this.result, this.requestId, {this.rawAckBody, this.errorMessage});
  bool get ok => result == CommandResult.accepted;
  String get displayMessage {
    switch (result) {
      case CommandResult.accepted:
        return '灯光已同步 ✨';
      case CommandResult.offline:
        return '灯光离线，计划仍在继续';
      case CommandResult.timeout:
        return '灯光没响应，我再陪你等一等';
      case CommandResult.ackMismatch:
        return '灯光反馈不一致，稍后我会再确认';
      case CommandResult.notReady:
        return '还没有今晚的安排。先和我聊聊？';
    }
  }
}

/// 状态转移事件：通过 NightSession.transition 的返回值描述"这一次跳转做了什么"
class StateTransitionResult {
  final NightSessionState from;
  final NightSessionState to;
  final bool allowed;
  final String reason;
  final LampCommandId? commandOnEnter; // 进入 to 状态时派发的命令
  const StateTransitionResult({
    required this.from,
    required this.to,
    required this.allowed,
    required this.reason,
    this.commandOnEnter,
  });
}

/// 当前 session 的完整状态机快照（UI 通过 AnimatedBuilder 直接渲染）
class NightSession {
  final NightSessionState state;
  final DateTime enteredAt;
  final DateTime? observedSince;   // 进入 OBSERVING 的时间
  final int thresholdMin;          // 连续刷触发阈值（从 TonightPlan.continuousThresholdMin 默认 10）
  final int extensionMinutesLeft;  // EXTENDING 剩余分钟数
  final int nudgeCount;            // 当日已 nudged 次数（FR-12 统计）
  final int extendCount;           // 当日已 extend 次数（对齐 AppController.extensionCount）
  final bool lampOnline;           // 最近一次派发命令的可达性（FR-13 UI 显示）
  final String? lastLampMessage;   // 最近一次灯光同步文案（"灯光已同步✨" / "灯光离线..."）
  final String enteredBecause;     // 调试/审计用：进入当前状态的原因描述
  final TonightPlan? plan;         // 与 AppController.tonightPlan 保持同步的本地缓存引用

  final List<String> actionLog;

  const NightSession({
    required this.state,
    required this.enteredAt,
    required this.thresholdMin,
    required this.extensionMinutesLeft,
    required this.nudgeCount,
    required this.extendCount,
    required this.lampOnline,
    required this.enteredBecause,
    this.plan,
    this.observedSince,
    this.lastLampMessage,
    this.actionLog = const [],
  });

  factory NightSession.initial() => NightSession(
        state: NightSessionState.unplanned,
        enteredAt: DateTime.now(),
        thresholdMin: 10,
        extensionMinutesLeft: 0,
        nudgeCount: 0,
        extendCount: 0,
        lampOnline: false,
        enteredBecause: '初始化',
      );

  NightSession copyWith({
    NightSessionState? state,
    DateTime? enteredAt,
    DateTime? observedSince,
    int? thresholdMin,
    int? extensionMinutesLeft,
    int? nudgeCount,
    int? extendCount,
    bool? lampOnline,
    String? lastLampMessage,
    String? enteredBecause,
    TonightPlan? plan,
    List<String>? actionLog,
  }) =>
      NightSession(
        state: state ?? this.state,
        enteredAt: enteredAt ?? this.enteredAt,
        observedSince: observedSince ?? this.observedSince,
        thresholdMin: thresholdMin ?? this.thresholdMin,
        extensionMinutesLeft: extensionMinutesLeft ?? this.extensionMinutesLeft,
        nudgeCount: nudgeCount ?? this.nudgeCount,
        extendCount: extendCount ?? this.extendCount,
        lampOnline: lampOnline ?? this.lampOnline,
        lastLampMessage: lastLampMessage ?? this.lastLampMessage,
        enteredBecause: enteredBecause ?? this.enteredBecause,
        plan: plan ?? this.plan,
        actionLog: actionLog ?? this.actionLog,
      );

  NightSession recordAction(String action) => copyWith(
        actionLog: <String>[...actionLog, action],
      );

  List<String> get replacementSelections => <String>[
        for (final action in actionLog)
          if (action.startsWith('chooseReplacement:'))
            action.substring('chooseReplacement:'.length),
      ];

  bool get preparedForSleep => actionLog.contains('prepareForSleep');

  // ================ 便捷派生字段（UI 直接调用）===============

  /// 友好的当前状态中文名
  String get displayState {
    switch (state) {
      case NightSessionState.unplanned: return '未生成计划';
      case NightSessionState.planned: return '计划就绪';
      case NightSessionState.observing: return '温柔守护中';
      case NightSessionState.nudged: return '该准备休息啦';
      case NightSessionState.replacing: return '替代活动中';
      case NightSessionState.extending: return '再陪我一会儿';
      case NightSessionState.finished: return '晚安，今天就到这里';
      case NightSessionState.muted: return '暂不提醒';
    }
  }

  /// 顶部状态徽标的颜色
  String get debugJson => const JsonEncoder.withIndent('  ').convert({
    'state': state.name,
    'enteredAt': enteredAt.toIso8601String(),
    'thresholdMin': thresholdMin,
    'extensionMinutesLeft': extensionMinutesLeft,
    'nudgeCount': nudgeCount,
    'extendCount': extendCount,
    'lampOnline': lampOnline,
    'lastLampMessage': lastLampMessage,
    'enteredBecause': enteredBecause,
  });

  /// FR-12 数据记录基础字段（给后续 sleep_records 表持久化时用）
  Map<String, dynamic> toRecordRow({required DateTime finishedAt}) => <String, dynamic>{
    'wake_time_target': plan?.wakeTime,
    'bedtime_target': plan?.recommendedBedtime,
    'continuous_threshold_min': thresholdMin,
    'nudge_count_total': nudgeCount,
    'extend_count_total': extendCount,
    'lamp_online_at_finish': lampOnline,
    'session_started_at': observedSince?.toIso8601String() ?? enteredAt.toIso8601String(),
    'session_finished_at': finishedAt.toIso8601String(),
    'final_state': state.name,
    'plan_json': plan?.toJson(),
    'action_log': actionLog,
    'replacement_selections': replacementSelections,
    'prepared_for_sleep': preparedForSleep,
  };
}
