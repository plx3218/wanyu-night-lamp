import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/lamp_models.dart';
import 'models/tonight_plan.dart';
import 'models/night_session.dart';
import 'services/lamp_service.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/esp32_lamp_service.dart';
import 'services/notification_service.dart';
import 'services/android_usage_service.dart';
import 'services/continuous_usage_engine.dart';
import 'services/background_handler.dart';
import 'services/monitor_schedule_service.dart';
import 'services/usage_monitor_coordinator.dart';
import 'services/night_record_service.dart';
import 'models/night_usage_record.dart';

/// AppController.confirmPlan 在没有 AI 生成 plan 时抛出；
/// UI 层捕获后应该引导用户回到聊天页和 AI 先聊一轮再回来。
class PlanNotReadyException implements Exception {
  const PlanNotReadyException();
  String get message => '还没有今晚的安排。先和我聊聊，生成一份属于你的？';
}

/// NightSessionState 在非法转移（如 FINISHED → NUDGED）时抛出，UI toast 不阻塞。
class IllegalTransitionException implements Exception {
  IllegalTransitionException(this.from, this.to, this.reason);
  final NightSessionState from;
  final NightSessionState to;
  final String reason;
  @override
  String toString() => '状态机拒绝: ${from.name} → ${to.name}，原因：$reason';
}

class AppController extends ChangeNotifier {
  AppController(
    this.lamp,
    this.ai, {
    UsageMonitorCoordinator? usageMonitor,
    NightRecordService? nightRecordService,
  })
      : usageMonitor = usageMonitor ??
            UsageMonitorCoordinator(
              source: AndroidUsageDataSource(AndroidUsageClient()),
            ),
        nightRecordService = nightRecordService ?? NightRecordService() {
    _lampSubscription = lamp.events.listen((event) {
      lastLampEvent = event;
      if (event.state != null) {
        final prev = _lampState;
        _lampState = event.state!;
        // 硬件事件驱动状态机（FR-11：NUDGED 可能来自 ESP32 waiting 状态上报）
        if (prev.rawState != 'waiting' && _lampState.rawState == 'waiting') {
          onNudge?.call();
          // 自动把 NightSession.state 推进到 nudged（如果当前在 observing / extending）
          if (_nightSession.state == NightSessionState.observing ||
              _nightSession.state == NightSessionState.extending ||
              _nightSession.state == NightSessionState.muted) {
            _transitionTo(
              NightSessionState.nudged,
              because: '硬件 waiting 事件（连续刷超阈值）',
              sendCommand: LampCommandId.nudge,
            );
          }
        }
        // 离线/重连反馈同步到 session.lampOnline
        _nightSession = _nightSession.copyWith(lampOnline: _lampState.connected);
        notifyListeners();
      }
    });
    FlutterForegroundTask.addTaskDataCallback(_handleForegroundTaskData);
    _usageMonitorSubscription = this.usageMonitor.events.listen((event) {
      lastUsageMonitorEvent = event;
      if (event.snapshot != null) {
        _lastUsageSnapshot = event.snapshot;
      }
      notifyListeners();
      if (event.type == UsageMonitorEventType.snapshot &&
          event.snapshot?.thresholdReached == true) {
        unawaited(_handleUsageThreshold(event));
      }
    });
  }

  final LampService lamp;
  final AiService ai;
  final UsageMonitorCoordinator usageMonitor;
  final NightRecordService nightRecordService;
  late final StreamSubscription<LampEvent> _lampSubscription;
  late final StreamSubscription<UsageMonitorEvent> _usageMonitorSubscription;
  LampEvent? lastLampEvent;
  LampState _lampState = LampState.initial();
  bool simulationMode = true;

  // ====================== 旧字段（保持对外兼容）======================
  /// [计划已确认] 等价于 NightSession.state != unplanned 且 ≠ planned（进入守护相关状态后视为确认）
  bool get planConfirmed =>
      _nightSession.state != NightSessionState.unplanned &&
      _nightSession.state != NightSessionState.planned;

  bool get sessionFinished => _nightSession.state == NightSessionState.finished;
  int get extensionCount => _nightSession.extendCount;

  /// 手动调亮度是否可用：仅在睡前流程未运行时允许（避免干扰时间线状态机）
  bool get canManualControl => !isSessionRunning;

  /// 手动设置灯光亮度（平滑渐变）。睡前流程运行中忽略，离线静默失败（无反应）。
  Future<void> manualSetBrightness(int level) async {
    if (!canManualControl) return;
    await lamp.setBrightness(level);
    notifyListeners();
  }

  // ====================== 新增：NightSession 状态机 ======================
  // 演示加速：管理员 1 分钟 = 1 秒（演示用，几秒内看到每个阶段效果）；
  // 普通用户 = 真实时间（1:1）。上线后只有管理员账号保留快进。
  static int get kDemoTimeDivisor => AuthService.isAdmin ? 60 : 1;
  static int minutesToDemoSeconds(int minutes) {
    if (minutes <= 0) return 0;
    final s = (minutes * 60) ~/ kDemoTimeDivisor;
    return s < 1 ? 1 : s;
  }

  NightSession _nightSession = NightSession.initial();
  NightSession get nightSession => _nightSession;
  bool get isSessionRunning =>
      _nightSession.state == NightSessionState.observing ||
      _nightSession.state == NightSessionState.nudged ||
      _nightSession.state == NightSessionState.replacing ||
      _nightSession.state == NightSessionState.extending ||
      _nightSession.state == NightSessionState.muted;

  /// 硬件命令幂等 requestId 生成：简短可读，日志里方便排查
  final Random _rand = Random();
  String nextRequestId(String prefix) {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = _rand.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '$prefix-$t$r';
  }

  VoidCallback? onNudge;

  /// 当前保存的 ESP32 IP（从 lamp 实现中读取）
  String get lampHost {
    if (lamp is Esp32LampService) {
      return (lamp as Esp32LampService).host;
    }
    return '模拟模式';
  }

  bool get isEsp32Mode => lamp is Esp32LampService;

  LampState get lampState => _lampState;

  // ============ AI 计划共享状态（P0），同时与状态机本地缓存 plan 同步 ============
  TonightPlan? get tonightPlan => _nightSession.plan;
  bool get hasTonightPlan => tonightPlan != null;
  MonitorSchedule? get monitorSchedule => usageMonitor.currentSchedule;
  UsageMonitorEvent? lastUsageMonitorEvent;
  UsageSnapshot? _lastUsageSnapshot;
  String? lastNightRecordError;
  bool _awaitingReminderAction = false;
  TonightPlan? _pendingTonightPlan;
  bool _disposed = false;
  NightExperimentPhase experimentPhase = NightExperimentPhase.baseline;

  bool get remindersEnabled => experimentPhase == NightExperimentPhase.intervention;

  void setExperimentPhase(NightExperimentPhase phase) {
    experimentPhase = phase;
    unawaited(_persistExperimentPhase(phase));
    if (!_disposed) notifyListeners();
  }

  static const String _kExperimentPhaseKey = 'wanyu_experiment_phase';

  Future<void> loadExperimentPhase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kExperimentPhaseKey);
      experimentPhase = raw == NightExperimentPhase.intervention.name
          ? NightExperimentPhase.intervention
          : NightExperimentPhase.baseline;
    } catch (_) {
      experimentPhase = NightExperimentPhase.baseline;
    }
  }

  Future<void> _persistExperimentPhase(NightExperimentPhase phase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kExperimentPhaseKey, phase.name);
    } catch (_) {}
  }

  void _handleForegroundTaskData(Object data) {
    if (data is Map && data['type'] == 'usage_monitor_tick') {
      unawaited(usageMonitor.refresh());
    }
  }

  Future<void> _handleUsageThreshold(UsageMonitorEvent event) async {
    if (experimentPhase == NightExperimentPhase.baseline) return;
    if (_awaitingReminderAction) return;
    _awaitingReminderAction = true;
    if (_nightSession.state == NightSessionState.planned) {
      _nightSession = _nightSession.copyWith(
        state: NightSessionState.observing,
        observedSince: event.schedule?.startAt ?? event.occurredAt,
      );
    }
    final result = await triggerNudge();
    if (!result.allowed) {
      _awaitingReminderAction = false;
      return;
    }
    await NotificationService.showStage(
      id: 201,
      title: '晚屿',
      body: '你已经连续使用手机 20 分钟了，准备换个节奏吗？',
    );
  }

  void setTonightPlan(TonightPlan plan) {
    final datedPlan = plan.generatedAt == null
        ? plan.copyWith(generatedAt: DateTime.now())
        : plan;
    final now = DateTime.now();
    final currentSchedule = usageMonitor.currentSchedule;
    final monitoringWindowLocked = usageMonitor.isRunning &&
        currentSchedule != null &&
        !now.isBefore(currentSchedule.startAt);
    if (monitoringWindowLocked && _nightSession.plan != null) {
      _pendingTonightPlan = datedPlan;
      unawaited(_persistPendingPlan(datedPlan));
      notifyListeners();
      return;
    }
    _applyTonightPlan(datedPlan);
  }

  void _applyTonightPlan(TonightPlan plan) {
    _pendingTonightPlan = null;
    unawaited(_removePendingPlan());
    // 挂接 plan → 立即把状态机推到 PLANNED（不再是 unplanned）
    _nightSession = NightSession(
      state: NightSessionState.planned,
      enteredAt: DateTime.now(),
      thresholdMin: plan.continuousThresholdMin ?? 20,
      extensionMinutesLeft: 0,
      nudgeCount: 0,
      extendCount: 0,
      lampOnline: _lampState.connected,
      enteredBecause: 'AI 生成了专属 plan',
      plan: plan,
    );
    _persistPlan(plan); // 本地持久化：App 重启后按钮/计划仍在
    notifyListeners();
    unawaited(syncUsageMonitoring());
  }

  void clearTonightPlan() {
    _nightSession = NightSession.initial();
    _persistPlan(null);
    notifyListeners();
  }

  // ============ plan 本地持久化（修复「看看今晚的安排」按钮重启后消失）============
  static const String _kPlanCacheKey = 'wanyu_tonight_plan_cache';
  static const String _kPendingPlanCacheKey = 'wanyu_pending_plan_cache';

  Future<void> _persistPlan(TonightPlan? plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (plan == null) {
        await prefs.remove(_kPlanCacheKey);
      } else {
        await prefs.setString(_kPlanCacheKey, jsonEncode(plan.toJson()));
      }
    } catch (_) {
      // 持久化失败不影响主流程
    }
  }

  /// App 启动时调用：从本地缓存恢复上一次的 TonightPlan（不恢复会话进度）
  Future<void> _persistPendingPlan(TonightPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPendingPlanCacheKey, jsonEncode(plan.toJson()));
    } catch (_) {
      // Pending plan persistence is best effort and never blocks monitoring.
    }
  }

  Future<void> _removePendingPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPendingPlanCacheKey);
    } catch (_) {}
  }

  Future<void> restoreCachedPlan() async {
    if (_nightSession.plan != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_kPlanCacheKey);
      final pendingRaw = prefs.getString(_kPendingPlanCacheKey);
      var selectedPending = false;
      if (pendingRaw != null && pendingRaw.trim().isNotEmpty) {
        try {
          final pendingMap = jsonDecode(pendingRaw);
          if (pendingMap is Map<String, dynamic>) {
            final pending = TonightPlan.fromServerJson(pendingMap);
            final today = DateTime.now();
            final generated = pending.generatedAt;
            if (generated != null &&
                generated.year == today.year &&
                generated.month == today.month &&
                generated.day == today.day) {
              raw = pendingRaw;
              selectedPending = true;
            }
          }
        } catch (_) {}
      }
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        final plan = TonightPlan.fromServerJson(map);
        _nightSession = NightSession(
          state: NightSessionState.planned,
          enteredAt: DateTime.now(),
          thresholdMin: plan.continuousThresholdMin ?? 20,
          extensionMinutesLeft: 0,
          nudgeCount: 0,
          extendCount: 0,
          lampOnline: _lampState.connected,
          enteredBecause: '从本地缓存恢复了 plan',
          plan: plan,
        );
        if (selectedPending) {
          unawaited(_removePendingPlan());
        }
        notifyListeners();
        unawaited(syncUsageMonitoring());
      }
    } catch (_) {
      // 缓存损坏则忽略
    }
  }

  /// 更新 ESP32 IP 地址（只在 Esp32LampService 模式下生效）
  bool updateLampHost(String newHost) {
    final trimmed = newHost.trim();
    if (trimmed.isEmpty) return false;
    if (lamp is Esp32LampService) {
      (lamp as Esp32LampService).updateHost(trimmed);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// 连接灯光设备（会先断开已有的连接）
  Future<LampState> connectLamp() async {
    await lamp.disconnect();
    _lampState = _lampState.copyWith(connected: false);
    _nightSession = _nightSession.copyWith(lampOnline: false);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      await lamp.connect().timeout(const Duration(seconds: 5));
    } catch (_) {
      // connect() 内部已经通过 events 广播 error
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _lampState;
  }

  /// 断开灯光设备
  Future<void> disconnectLamp() async {
    await lamp.disconnect();
    _lampState = LampState.initial();
    _nightSession = _nightSession.copyWith(lampOnline: false);
    notifyListeners();
  }

  /// 切换连接状态
  Future<void> toggleLampConnection() async {
    if (_lampState.connected) {
      await disconnectLamp();
    } else {
      await connectLamp();
    }
  }

  // ================ 状态机：核心转移引擎 ================
  /// 所有 UI/事件驱动的跳转都走这里：校验允许 → 派发 Lamp 命令 → 写入
  /// NightSession.state → notifyListeners。
  Future<StateTransitionResult> _transitionTo(
    NightSessionState to, {
    required String because,
    LampCommandId? sendCommand,
    int? brightness,
    int? durationMinutes,
    // 可选覆盖：调用方希望把 NightSession.plan 的 extensionMinutes / nudgeCount 等同步写入
    int? extensionMinutesLeftOverride,
    int? nudgeCountDelta,
    int? extendCountDelta,
  }) async {
    final from = _nightSession.state;
    if (!_isAllowed(from, to)) {
      final reason = '${from.name} 不允许跳到 ${to.name}：$because';
      return StateTransitionResult(
          from: from, to: to, allowed: false, reason: reason);
    }

    CommandOutcome? outcome;
    if (sendCommand != null) {
      outcome = await lamp.sendCommandV1(
        sendCommand,
        requestId: nextRequestId(to.name),
        brightness: brightness,
        durationMinutes: durationMinutes,
      );
    }

    final now = DateTime.now();
    final prev = _nightSession;
    final plan = prev.plan;
    int newThreshold = prev.thresholdMin;
    int newNudgeCount = prev.nudgeCount + (nudgeCountDelta ?? (to == NightSessionState.nudged ? 1 : 0));
    int newExtendCount = prev.extendCount + (extendCountDelta ?? 0);
    int newExtLeft = extensionMinutesLeftOverride ??
        (to == NightSessionState.extending ? (plan?.extensionMinutes ?? 10) : 0);

    // 阈值如果 plan 里有就用 plan 的（保持 AI 用户自定义意图）
    if (plan != null) newThreshold = plan.continuousThresholdMin ?? newThreshold;

    _nightSession = NightSession(
      state: to,
      enteredAt: now,
      observedSince: (to == NightSessionState.observing)
          ? now
          : (from == NightSessionState.observing &&
                  (to == NightSessionState.nudged ||
                      to == NightSessionState.extending ||
                      to == NightSessionState.muted))
              ? prev.observedSince
              : prev.observedSince,
      thresholdMin: newThreshold,
      extensionMinutesLeft: newExtLeft,
      nudgeCount: newNudgeCount,
      extendCount: newExtendCount,
      lampOnline: outcome == null
          ? prev.lampOnline
          : (outcome.result == CommandResult.accepted ||
              outcome.result == CommandResult.ackMismatch),
      lastLampMessage: outcome?.displayMessage ?? prev.lastLampMessage,
      enteredBecause: because,
      plan: plan,
      actionLog: <String>[...prev.actionLog, because],
    );
    notifyListeners();

    return StateTransitionResult(
      from: from,
      to: to,
      allowed: true,
      reason: because,
      commandOnEnter: sendCommand,
    );
  }

  bool _isAllowed(NightSessionState from, NightSessionState to) {
    // FR-11 状态转移表（允许自转移幂等，但不重复计数）
    switch (from) {
      case NightSessionState.unplanned:
        return to == NightSessionState.planned;
      case NightSessionState.planned:
        return to == NightSessionState.observing ||
            to == NightSessionState.finished /* 立刻结束 */ ||
            to == NightSessionState.unplanned /* reset */;
      case NightSessionState.observing:
        return to == NightSessionState.nudged ||
            to == NightSessionState.finished ||
            to == NightSessionState.replacing ||
            to == NightSessionState.extending ||
            to == NightSessionState.muted ||
            to == NightSessionState.planned /* restoreLight */ ||
            to == NightSessionState.unplanned /* reset */;
      case NightSessionState.nudged:
        return to == NightSessionState.extending ||
            to == NightSessionState.replacing ||
            to == NightSessionState.finished ||
            to == NightSessionState.muted ||
            to == NightSessionState.planned ||
            to == NightSessionState.observing /* 误触发，用户要回去 */ ||
            to == NightSessionState.unplanned;
      case NightSessionState.extending:
        return to == NightSessionState.extending /* 再多一次延时 */ ||
            to == NightSessionState.nudged ||
            to == NightSessionState.finished ||
            to == NightSessionState.replacing ||
            to == NightSessionState.muted ||
            to == NightSessionState.planned ||
            to == NightSessionState.unplanned;
      case NightSessionState.replacing:
        return to == NightSessionState.finished ||
            to == NightSessionState.observing ||
            to == NightSessionState.planned ||
            to == NightSessionState.unplanned;
      case NightSessionState.muted:
        return to == NightSessionState.nudged /* 次日 / 用户关闭静音 */ ||
            to == NightSessionState.finished ||
            to == NightSessionState.planned ||
            to == NightSessionState.observing ||
            to == NightSessionState.unplanned;
      case NightSessionState.finished:
        return to == NightSessionState.replacing /* 我还要看一下 */ ||
            to == NightSessionState.planned ||
            to == NightSessionState.unplanned;
    }
  }

  // ================ 对外暴露的业务 API（SessionScreen 按钮直接调用）================

  /// 用户在 PlanScreen 点「就按这个来」。
  /// 必须 hasTonightPlan（原逻辑保留）→ 状态机按 urgentFinish 决定进 FINISHED 还是 OBSERVING
  ///
  /// 2026-08-29 关键体验修复：命令下发改为「Fire-and-Forget」——
  ///   1) 同步更新本地状态机 + 通知 UI（让 PlanScreen 立刻 push SessionScreen，不再卡顿）
  ///   2) 命令异步在后台发；失败时写个 lastLampMessage 提醒（不挡 UI）
  /// 这样用户体感是「点完 100ms 内就跳转」，不会因 HTTP 超时等待 3~5 秒。
  Future<void> confirmPlan() async {
    final plan = tonightPlan;
    if (plan == null) throw const PlanNotReadyException();

    final bedBright = plan.lightLevelBedtime ?? 5;

    if (plan.urgentFinish) {
      // 同步写本地状态（立即生效，UI 立刻切）
      _applyStateLocally(
        NightSessionState.finished,
        because: 'AI plan.urgentFinish=true',
        brightness: bedBright,
      );
      // 异步发命令（不 await）
      _fireCommand(LampCommandId.finish, brightness: bedBright);
      return;
    }

    // 时间线已在跑（重复点"开始守护"）→ 不重启，避免计时混乱
    if (_timelineRunning) return;

    // ① 立即切 PLANNED 暖光 70%（本地状态立刻更新 + 后台发命令，不阻塞跳转）
    _applyStateLocally(
      NightSessionState.planned,
      because: '用户点了「就按这个来」，先打 70% 暖光就绪',
      brightness: 70,
    );
    _fireCommand(LampCommandId.lightLevel2, brightness: 70);

    // ② 启动时间线引擎：按 AI plan 的步骤时间依次推进
    //    第一步时间 → 70%（进入守护）→ 第二步时间 → 50% → 最后时间 → 弹窗询问延时
    await startPlanTimeline();
  }

  // ================== 时间线引擎（按 AI plan 时间点驱动灯光）==================
  // 用户需求：AI 说 23:00 进入睡眠准备 → 灯 70%；23:15 → 50%；23:30 → 弹窗询问
  // 是否延时 10 分钟；选"是"保持 50% 十分钟后变 5%；选"否"直接 5%。全程平滑渐变。
  // 演示加速：1 分钟 = 1 秒（与全局 kDemoTimeDivisor 一致）。
  //
  // 引擎放在 AppController（而非页面）里：用户离开 SessionScreen 计时也不中断。

  Timer? _timelineTimer;
  Timer? _extendTimeoutTimer; // 延时结束后 5 分钟超时：自动判定"不延时"
  bool _timelineRunning = false;
  List<_TlEvent> _timeline = [];
  int _timelineIndex = -1;

  /// 下一个事件的真实触发时刻（SessionScreen 圆环倒计时用）
  DateTime? nextTimelineFireAt;
  /// 当前倒计时起始秒（进度环分母）
  int nextEventInitialSec = 0;
  /// 当前阶段描述（如「第 2 步 · 放下手机」）
  String timelineCurrentLabel = '';
  /// 即将发生的事件描述（如「调至 50% 亮度」）
  String timelineNextLabel = '';
  /// 即将发生事件的 plan 原始时间（如 "23:15"）
  String timelineNextPlanTime = '';
  /// 即将发生事件的目标亮度（进度/文案用）
  int? timelineNextBrightness;
  /// SessionScreen 注册：到询问点时弹「要不要延时」对话框
  VoidCallback? onAskExtend;
  /// SessionScreen 注册：阶段信息弹窗（步骤1/步骤2 的提示）
  void Function(String title, String body)? onShowStageInfo;

  // ================== 后台弹窗 pending 队列 ==================
  // App 在后台时，时间线事件触发的弹窗会存入 pending 队列，
  // 用户从通知点进 App 恢复前台时，SessionScreen 检查并显示。
  final List<({String title, String body})> _pendingStageInfos = [];
  bool _pendingAskExtend = false;

  /// 是否有待显示的阶段信息弹窗
  bool get hasPendingStageInfo => _pendingStageInfos.isNotEmpty;
  /// 是否有待显示的延时询问弹窗
  bool get hasPendingAskExtend => _pendingAskExtend;

  /// 消费（取出并清空）待显示的阶段信息弹窗
  ({String title, String body})? consumePendingStageInfo() {
    if (_pendingStageInfos.isEmpty) return null;
    return _pendingStageInfos.removeAt(0);
  }

  /// 消费（取出并清空）待显示的延时询问弹窗
  bool consumePendingAskExtend() {
    final v = _pendingAskExtend;
    _pendingAskExtend = false;
    return v;
  }

  Future<void> startPlanTimeline() async {
    final plan = tonightPlan;
    if (plan == null) return;
    _timeline = _buildTimeline(plan);
    if (_timeline.isEmpty) return;
    _timelineRunning = true;
    // 启动前台服务：App 在后台时时间线继续运行
    // 必须 await 等待完成，否则 startService 的异步异常不会被捕获
    await _startForegroundService();
    _scheduleTimelineEvent(0);
  }

  /// 由 plan 的步骤时间构建事件序列：
  ///   steps[0].time → 70%（进入守护）
  ///   steps[1].time → 50%（若无第二步则用 reminder_time）
  ///   最后时间（steps.last / recommended_bedtime）→ 询问点（亮度保持 50%）
  List<_TlEvent> _buildTimeline(TonightPlan plan) {
    final steps = plan.normalizedSteps();
    final n = steps.length;
    final t70 = n > 0 ? steps.first.time : plan.windDownTime;
    final t50 = n > 1 ? steps[1].time : plan.reminderTime;
    final tAsk = n > 1 ? steps.last.time : plan.recommendedBedtime;
    final a1 = n > 0 ? steps.first.action : '进入睡眠准备';
    final a2 = n > 1 ? steps[1].action : '灯光调暗，慢慢准备入睡';

    // 演示秒（1 分钟 = 1 秒），并保证相邻事件至少间隔 6 秒（渐变才看得清）
    int d1 = _demoSecFromNowTo(t70, floor: 2);
    int d2 = _demoSecFromNowTo(t50, floor: d1 + 6);
    int d3 = _demoSecFromNowTo(tAsk, floor: d2 + 6);

    return [
      _TlEvent(
        delaySec: d1,
        planTime: t70,
        label: '第 1 步 · $a1',
        brightness: 70,
        command: LampCommandId.lightLevel2,
        state: NightSessionState.observing,
      ),
      _TlEvent(
        delaySec: d2,
        planTime: t50,
        label: '第 2 步 · $a2',
        brightness: 50,
        command: LampCommandId.windDown,
        state: NightSessionState.observing,
      ),
      _TlEvent(
        delaySec: d3,
        planTime: tAsk,
        label: '到了计划入睡提醒时间',
        brightness: null, // 保持 50% 不变
        command: null,
        state: NightSessionState.nudged,
        ask: true,
      ),
    ];
  }

  /// "HH:MM" 距现在多少演示秒；已过去(6 小时内)的时间点视为立即触发
  int _demoSecFromNowTo(String hhmm, {required int floor}) {
    final now = DateTime.now();
    final parts = hhmm.split(':');
    if (parts.length != 2) return floor;
    final hh = int.tryParse(parts.first);
    final mm = int.tryParse(parts.last);
    if (hh == null || mm == null) return floor;
    var target = DateTime(now.year, now.month, now.day, hh, mm);
    if (target.isBefore(now)) {
      if (now.difference(target).inMinutes > 360) {
        target = target.add(const Duration(days: 1)); // 跨午夜：视为明天
      } else {
        return floor; // 刚过的时间点 → 立即（用 floor 兜底）
      }
    }
    final diffMin = target.difference(now).inMinutes.clamp(0, 240);
    final sec = minutesToDemoSeconds(diffMin);
    return sec < floor ? floor : sec;
  }

  void _scheduleTimelineEvent(int index) {
    _timelineTimer?.cancel();
    if (index >= _timeline.length) return; // 序列播完（询问点后由用户选择接管）
    final ev = _timeline[index];
    _timelineIndex = index;

    // 供 UI 显示的"下一站"信息
    nextTimelineFireAt = DateTime.now().add(Duration(seconds: ev.delaySec));
    nextEventInitialSec = ev.delaySec;
    timelineNextLabel = ev.brightness != null ? '亮度调至 ${ev.brightness}%' : '询问是否延时';
    timelineNextPlanTime = ev.planTime;
    timelineNextBrightness = ev.brightness;
    notifyListeners();

    _timelineTimer = Timer(Duration(seconds: ev.delaySec), () {
      _executeTimelineEvent(index);
    });
  }

  // 各阶段固定通知 id（相同 id 可更新通知：先发降级，AI 成功后更新）
  static const _stageNotifyId = {
    'wind_down': 200,
    'agenda': 201,
    'bedtime': 202,
    'extended': 203,
  };

  // 各阶段降级文案（本地兜底，保证后台一定弹出）
  static const _fallbackNotify = {
    'wind_down': {'title': '晚屿', 'body': '放下手边的事，靠一靠'},
    'agenda': {'title': '晚屿', 'body': '准备结束今天，要睡觉啦'},
    'bedtime': {'title': '晚屿', 'body': '到了入睡提醒时间，需要延时么'},
    'extended': {'title': '晚屿', 'body': '已经比计划晚了，今晚就到这里吧'},
  };

  /// 立即发降级通知，再异步用 AI 文案更新（fire-and-forget，保证后台一定弹出）
  /// 关键修复：通知发送不依赖任何前置异步操作，先弹降级文案，AI 成功后用相同 id 更新。
  /// 遵循 MIUI 后台规范：网络请求在后台可能因平台通道挂起而无法完成，
  /// 因此必须先发通知再异步请求 AI，否则会出现"需要点开 App 才显示通知"。
  void _pushStageNotification(String stage) {
    final fallback = _fallbackNotify[stage] ?? _fallbackNotify['wind_down']!;
    final notifyId = _stageNotifyId[stage] ?? 200;
    // 1. 立即发通知（不阻塞，保证后台弹出）
    NotificationService.showStage(id: notifyId, title: fallback['title']!, body: fallback['body']!);
    // 2. 异步请求 AI 个性化文案，成功后用相同 id 更新（失败/超时则保持降级文案）
    _generateNotifyText(stage).then((text) {
      NotificationService.showStage(id: notifyId, title: text['title']!, body: text['body']!);
    });
  }

  /// 调用 AI 生成个性化通知文案，失败时降级
  /// stage: 'wind_down' | 'agenda' | 'bedtime' | 'extended'
  Future<Map<String, String>> _generateNotifyText(String stage) async {
    final fallback = _fallbackNotify[stage] ?? _fallbackNotify['wind_down']!;

    try {
      final plan = tonightPlan;
      final planData = {
        'recommended_bedtime': plan?.recommendedBedtime,
        'wake_time': plan?.wakeTime,
        'steps': plan?.steps.map((s) => {'action': s.action, 'time': s.time}).toList(),
        'delay_count': _nightSession.extendCount,
        'delay_minutes': plan?.extensionMinutes ?? 10,
      };

      final resp = await http
          .post(
            Uri.parse('${ai.serverUrl}/api/v1/notify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'stage': stage,
              'plan': planData,
              'chat_summary': plan?.reply ?? '',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        debugPrint('[AppController] 通知文案 source=${data['source']}, used_fields=${data['used_fields']}');
        return {
          'title': (data['title'] as String?) ?? fallback['title']!,
          'body': (data['body'] as String?) ?? fallback['body']!,
        };
      }
    } catch (e) {
      debugPrint('[AppController] 通知文案生成失败: $e');
    }
    return fallback;
  }

  void _executeTimelineEvent(int index) {
    if (index >= _timeline.length) return;
    final ev = _timeline[index];
    timelineCurrentLabel = ev.label;

    if (ev.state != null) {
      _applyStateLocally(
        ev.state!,
        because: '时间线：${ev.label}（${ev.planTime}）',
        brightness: ev.brightness,
      );
    }
    if (ev.command != null) {
      _fireCommand(ev.command!, brightness: ev.brightness);
    }
    if (ev.ask) {
      // 询问点：亮度保持 50%，推送通知 + 页面弹窗
      // 询问点：先发降级通知（保证后台弹出），AI 成功后用相同 id 更新为个性化文案
      _pushStageNotification('bedtime');
      // 记录到 pending 队列（App 在后台时用户点进来能看到弹窗）
      _pendingAskExtend = true;
      onAskExtend?.call();
      // 不继续排下一个事件，等用户选择（timelineExtend / timelineFinish）
      notifyListeners();
      return;
    }
    // 阶段推送（步骤1/步骤2）
    // 步骤1：只有 push，不弹窗
    // 步骤2：push + 信息弹窗（毛玻璃版）
    if (ev.label.contains('第 1 步')) {
      _pushStageNotification('wind_down');
    } else if (ev.label.contains('第 2 步')) {
      _pushStageNotification('agenda');
      _pendingStageInfos.add((title: '晚屿', body: '准备结束今天，要睡觉啦'));
      onShowStageInfo?.call('晚屿', '准备结束今天，要睡觉啦');
    }
    _scheduleTimelineEvent(index + 1);
  }

  /// 演示用：直接跳到询问点（跳过中间等待）
  void skipToAskPoint() {
    if (!_timelineRunning) return;
    final askIndex = _timeline.indexWhere((e) => e.ask);
    if (askIndex < 0) return;
    _timelineTimer?.cancel();
    _executeTimelineEvent(askIndex);
  }

  /// 用户在询问点选「再延时 X 分钟」：
  /// - 灯平滑渐变到 50%，延时 X 分钟
  /// - 延时结束后（第1/2次）→ 灯变 5%，发通知，等待用户决定
  ///   - 用户选"是" → 再次 timelineExtend（灯渐变到 50%）
  ///   - 用户选"否" → 保持 5%
  ///   - 5 分钟超时 → 自动保持 5%，不再发通知
  /// - 第 3 次延时结束 → 直接 5% 夜灯（不再询问）
  void timelineExtend() {
    final plan = tonightPlan;
    final ext = plan?.extensionMinutes ?? 10;
    final holdBright = 50; // 延时期间维持 50%
    // 取消之前的超时定时器（用户做了决定）
    _extendTimeoutTimer?.cancel();
    // 灯平滑渐变到 50%（从 5% 渐变回来）
    _applyStateLocally(
      NightSessionState.extending,
      because: '用户选择延时 $ext 分钟，灯渐变到 50%',
      brightness: holdBright,
      extensionMinutesLeftOverride: ext,
      extendCountDelta: 1,
    );
    _fireCommand(
      LampCommandId.extend,
      brightness: holdBright,
      durationMinutes: ext,
    );
    // 延时开始：先发降级通知（保证后台弹出），AI 成功后用相同 id 更新
    _pushStageNotification('extended');
    final sec = minutesToDemoSeconds(ext);
    nextTimelineFireAt = DateTime.now().add(Duration(seconds: sec));
    nextEventInitialSec = sec;
    timelineNextLabel = '延时结束，灯变 5%';
    timelineNextPlanTime = '';
    timelineNextBrightness = plan?.lightLevelBedtime ?? 5;
    notifyListeners();
    _timelineTimer?.cancel();
    _timelineTimer = Timer(Duration(seconds: sec), () {
      // 延时结束 → 直接 5% 夜灯（不再询问，不再发通知）
      timelineFinish();
    });
  }

  /// 时间线结束：平滑渐变到 5% 夜灯
  /// Persists the privacy-safe nightly aggregate. `phoneIdleAt` is a proxy,
  /// never a claim that the user actually fell asleep at that time.
  Future<void> saveTonightRecord({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final schedule = monitorSchedule;
    final target = schedule?.targetBedtime;
    final snapshot = _lastUsageSnapshot;
    final event = lastUsageMonitorEvent;
    final recordDay = target ?? current;
    final record = NightUsageRecord(
      day: DateTime(recordDay.year, recordDay.month, recordDay.day),
      monitorStartAt: schedule?.startAt,
      targetBedtime: target,
      entertainmentMinutes: snapshot?.entertainmentMinutes ?? 0,
      reminderCount: _nightSession.nudgeCount,
      continueCount: _nightSession.extendCount,
      replacementSelections: _nightSession.replacementSelections,
      prepareForSleepAt: _nightSession.preparedForSleep ? current : null,
      phoneIdleAt: snapshot?.lastPhoneActivityAt,
      usageAccessGranted: event?.type != UsageMonitorEventType.permissionRequired,
      monitorStatus: event?.type.name ?? 'not_started',
      dataSource: snapshot == null ? 'local_no_snapshot' : 'android_usage_stats',
      phase: experimentPhase,
      remindersEnabled: remindersEnabled,
    );
    try {
      await nightRecordService.saveLocal(record);
      lastNightRecordError = null;
    } on NightRecordException catch (error) {
      lastNightRecordError = error.message;
    }
    if (!_disposed) notifyListeners();
  }

  void timelineFinish() {
    _timelineRunning = false;
    _timelineTimer?.cancel();
    _timelineTimer = null;
    _extendTimeoutTimer?.cancel();
    _extendTimeoutTimer = null;
    // 停止前台服务：时间线结束，不再需要后台运行
    _stopForegroundService();
    nextTimelineFireAt = null;
    final bedBright = tonightPlan?.lightLevelBedtime ?? 5;
    _applyStateLocally(
      NightSessionState.finished,
      because: '进入入睡陪伴，5% 夜灯陪你入睡',
      brightness: bedBright,
    );
    unawaited(saveTonightRecord());
    _fireCommand(LampCommandId.finish, brightness: bedBright);
  }

  // ================= 修复配套：本地同步写状态 + 异步发命令 =================

  /// 只改 NightSession 本地缓存，不发 HTTP，保证 UI 立即变。
  void _applyStateLocally(
    NightSessionState to, {
    required String because,
    int? brightness,
    int? extensionMinutesLeftOverride,
    int? nudgeCountDelta,
    int? extendCountDelta,
  }) {
    final now = DateTime.now();
    final prev = _nightSession;
    final plan = prev.plan;
    int newThreshold = prev.thresholdMin;
    int newNudgeCount =
        prev.nudgeCount + (nudgeCountDelta ?? (to == NightSessionState.nudged ? 1 : 0));
    int newExtendCount = prev.extendCount + (extendCountDelta ?? 0);
    int newExtLeft = extensionMinutesLeftOverride ??
        (to == NightSessionState.extending ? (plan?.extensionMinutes ?? 10) : 0);
    if (plan != null) newThreshold = plan.continuousThresholdMin ?? newThreshold;

    _nightSession = NightSession(
      state: to,
      enteredAt: now,
      observedSince: (to == NightSessionState.observing)
          ? now
          : (prev.state == NightSessionState.observing &&
                  (to == NightSessionState.nudged ||
                      to == NightSessionState.extending ||
                      to == NightSessionState.muted))
              ? prev.observedSince
              : prev.observedSince,
      thresholdMin: newThreshold,
      extensionMinutesLeft: newExtLeft,
      nudgeCount: newNudgeCount,
      extendCount: newExtendCount,
      lampOnline: prev.lampOnline,
      lastLampMessage: prev.lastLampMessage ?? '指令同步中…',
      enteredBecause: because,
      plan: plan,
    );
    notifyListeners();
  }

  /// 后台异步发命令，失败时写 lastLampMessage 给 UI 提示，不抛异常不阻塞。
  /// 自动重试 1 次，两次都失败再提示"同步超时"，避免偶发 WiFi 抖动丢包。
  Future<void> _fireCommand(
    LampCommandId cmd, {
    int? brightness,
    int? durationMinutes,
    int retry = 1, // 至少尝试 1 + retry = 2 次
  }) async {
    CommandOutcome? outcome;
    for (int attempt = 0; attempt <= retry; attempt++) {
      try {
        outcome = await lamp.sendCommandV1(
          cmd,
          requestId: nextRequestId('${cmd.name}-a$attempt'),
          brightness: brightness,
          durationMinutes: durationMinutes,
        );
        if (outcome.result == CommandResult.accepted ||
            outcome.result == CommandResult.ackMismatch) {
          break;
        }
      } catch (_) {
        if (attempt < retry) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
      }
    }
    if (outcome == null) {
      _nightSession = _nightSession.copyWith(
        lastLampMessage: '灯光同步失败（网络异常），请稍后手动点一下',
      );
    } else {
      final online = outcome.result == CommandResult.accepted ||
          outcome.result == CommandResult.ackMismatch;
      final msg = outcome.displayMessage?.isNotEmpty == true
          ? outcome.displayMessage!
          : (online ? '灯光已同步' : '灯光同步失败：${outcome.errorMessage ?? outcome.result.name}');
      _nightSession = _nightSession.copyWith(
        lampOnline: online || _lampState.connected,
        lastLampMessage: msg,
      );
    }
    notifyListeners();
  }

  /// 再陪我 X 分钟（X 默认来自 TonightPlan.extensionMinutes）
  /// 延时结束后：
  ///   第 1/2 次 → 亮度降至 5%，重新弹询问弹窗
  ///   第 3 次 → 直接 5% 夜灯（不再询问）
  Future<StateTransitionResult> continueUsage() async {
    if (_nightSession.extendCount >= 2) {
      const reason = 'continueForTenMinutes blocked after two extensions';
      _nightSession = _nightSession.recordAction(reason);
      notifyListeners();
      await NotificationService.showStage(
        id: 204,
        title: '晚屿',
        body: '今晚已经延后两次了，准备入睡会更合适。',
      );
      return StateTransitionResult(
        from: _nightSession.state,
        to: _nightSession.state,
        allowed: false,
        reason: reason,
      );
    }
    final result = await extendSession(minutes: 10);
    if (result.allowed) {
      _awaitingReminderAction = false;
      _nightSession = _nightSession.recordAction('continueForTenMinutes');
      notifyListeners();
    }
    return result;
  }

  Future<StateTransitionResult> selectReplacement(String activity) async {
    final replacement = activity.trim().isEmpty
        ? (tonightPlan?.replacementActivity ?? '直接休息')
        : activity.trim();
    final brightness = tonightPlan?.lightLevelWindDown == null
        ? 60
        : (tonightPlan!.lightLevelWindDown! + 10).clamp(0, 100);
    final result = await _transitionTo(
      NightSessionState.replacing,
      because: 'chooseReplacement:$replacement',
      sendCommand: LampCommandId.enterReplace,
      brightness: brightness,
      durationMinutes: 30,
    );
    if (result.allowed) {
      _awaitingReminderAction = false;
      _nightSession = _nightSession.recordAction('chooseReplacement:$replacement');
      notifyListeners();
    }
    return result;
  }

  Future<StateTransitionResult> prepareForSleep() async {
    final result = await finishSession();
    if (result.allowed) {
      _awaitingReminderAction = false;
      _nightSession = _nightSession.recordAction('prepareForSleep');
      unawaited(saveTonightRecord());
      notifyListeners();
    }
    return result;
  }

  Future<void> handleReminderAction(ReminderAction action) async {
    switch (action) {
      case ReminderAction.continueForTenMinutes:
        await continueUsage();
      case ReminderAction.chooseReplacement:
        await selectReplacement(
          AuthService.user?.replacementActivity ??
              tonightPlan?.replacementActivity ??
              '直接休息',
        );
      case ReminderAction.prepareForSleep:
        await prepareForSleep();
    }
  }

  Future<StateTransitionResult> extendSession({int? minutes}) async {
    final plan = tonightPlan;
    final mins = minutes?.clamp(1, 240) ?? plan?.extensionMinutes ?? 10;
    final holdBright = plan?.lightLevelWindDown ?? 50;
    final res = await _transitionTo(
      NightSessionState.extending,
      because: '用户选择"再陪我 $mins 分钟"',
      sendCommand: LampCommandId.extend,
      brightness: holdBright,
      durationMinutes: mins,
      extendCountDelta: 1,
      extensionMinutesLeftOverride: mins,
    );
    if (res.allowed) {
      final sec = minutesToDemoSeconds(mins);
      nextTimelineFireAt = DateTime.now().add(Duration(seconds: sec));
      nextEventInitialSec = sec;
      timelineNextLabel = '延时结束，调至 5% 夜灯';
      timelineNextPlanTime = '';
      timelineNextBrightness = plan?.lightLevelBedtime ?? 5;
      notifyListeners();
      _timelineTimer?.cancel();
      _timelineTimer = Timer(Duration(seconds: sec), () {
        if (_nightSession.extendCount >= 3) {
          // 第三次延时结束 → 直接 5% 夜灯，不再询问
          timelineFinish();
        } else {
          // 第一/二次延时结束 → 亮度降至 5%，重新弹询问弹窗
          final bedBright = plan?.lightLevelBedtime ?? 5;
          _applyStateLocally(
            NightSessionState.nudged,
            because: '延时结束，亮度降至 $bedBright%，询问是否继续',
            brightness: bedBright,
          );
          _fireCommand(LampCommandId.finish, brightness: bedBright);
          final body = _nightSession.extendCount == 1
              ? '还需要延时么'
              : '你已经用手机时间很长了，快休息吧';
          NotificationService.showStage(id: 203, title: '晚屿', body: body);
          _pendingAskExtend = true;
          onAskExtend?.call();
          notifyListeners();
        }
      });
    }
    return res;
  }

  /// 用户说"结束今天/现在准备睡"
  Future<StateTransitionResult> finishSession() async {
    // 手动结束今晚计划 → 停掉时间线引擎（不再自动推进）
    _timelineRunning = false;
    _timelineTimer?.cancel();
    _timelineTimer = null;
    nextTimelineFireAt = null;
    final bedBright = tonightPlan?.lightLevelBedtime ?? 5;
    return _transitionTo(
      NightSessionState.finished,
      because: '用户结束今晚，进入 5% 夜灯',
      sendCommand: LampCommandId.finish,
      brightness: bedBright,
    );
  }

  /// UI 手动触发 Nudge（例如"跳到提醒时刻"）
  Future<StateTransitionResult> triggerNudge() async {
    final brightness = tonightPlan?.lightLevelWindDown == null
        ? 30
        : (tonightPlan!.lightLevelWindDown! - 20).clamp(5, 100);
    return _transitionTo(
      NightSessionState.nudged,
      because: '用户手动跳到提醒时刻',
      sendCommand: LampCommandId.nudge,
      brightness: brightness,
      nudgeCountDelta: 1,
    );
  }

  /// 用户选择替代活动（音乐/阅读/白噪音……）
  Future<StateTransitionResult> switchToReplacing() async {
    final brightness = tonightPlan?.lightLevelWindDown == null
        ? 60
        : (tonightPlan!.lightLevelWindDown! + 10).clamp(0, 100);
    return _transitionTo(
      NightSessionState.replacing,
      because: '用户切换到替代活动：${tonightPlan?.replacementActivity ?? "未选择"}',
      sendCommand: LampCommandId.enterReplace,
      brightness: brightness,
      durationMinutes: 30,
    );
  }

  /// 本次不用提醒我
  Future<StateTransitionResult> muteReminder() async {
    return _transitionTo(
      NightSessionState.muted,
      because: '用户点了"本次不用提醒"',
      sendCommand: LampCommandId.mute,
    );
  }

  /// 恢复提醒
  Future<StateTransitionResult> unmuteReminder() async {
    return _transitionTo(
      NightSessionState.observing,
      because: '用户恢复提醒',
      sendCommand: LampCommandId.unmute,
    );
  }

  /// 紧急照明（回到 LIGHT_LEVEL_3，暂时不进入守护）
  Future<StateTransitionResult> restoreLight() async {
    return _transitionTo(
      NightSessionState.planned,
      because: '用户按了"恢复照明"',
      sendCommand: LampCommandId.restoreLight,
      brightness: 100,
    );
  }

  /// 完全重置：回到 UNPLANNED（不清除 plan，让 setTonightPlan 被新的覆盖）
  Future<void> resetSession() async {
    // 停掉时间线引擎（重置后不再自动推进灯光）
    _timelineRunning = false;
    _timelineTimer?.cancel();
    _timelineTimer = null;
    nextTimelineFireAt = null;
    timelineCurrentLabel = '';
    timelineNextLabel = '';
    timelineNextPlanTime = '';
    timelineNextBrightness = null;
    await lamp.reset(); // 兼容层已转为 restoreLight V1
    _nightSession = NightSession.initial().copyWith(
      plan: tonightPlan, // 保留 plan 方便用户重新"就按这个来"
      lampOnline: _lampState.connected,
      lastLampMessage: '已重置',
    );
    notifyListeners();
  }

  /// ========== 调试兜底：用户按「立即同步灯光」时按当前 NightSession.state 再发一次对应命令 ==========
  /// 避免偶发 HTTP 丢包导致灯光和 UI 不同步。
  Future<void> debugSyncCurrentStateToLamp() async {
    final plan = tonightPlan;
    switch (_nightSession.state) {
      case NightSessionState.unplanned:
      case NightSessionState.planned:
        await _fireCommand(
          LampCommandId.lightLevel2,
          brightness: plan?.lightLevelWindDown == null
              ? 70
              : (plan!.lightLevelWindDown! + 30).clamp(40, 100),
        );
        break;
      case NightSessionState.observing:
      case NightSessionState.muted:
        await _fireCommand(
          LampCommandId.windDown,
          brightness: plan?.lightLevelWindDown ?? 50,
        );
        break;
      case NightSessionState.nudged:
        await _fireCommand(
          LampCommandId.nudge,
          brightness: (plan?.lightLevelWindDown ?? 50) - 20,
        );
        break;
      case NightSessionState.extending:
        await _fireCommand(
          LampCommandId.extend,
          brightness: (plan?.lightLevelWindDown ?? 50) + 5,
          durationMinutes: plan?.extensionMinutes ?? 10,
        );
        break;
      case NightSessionState.replacing:
        await _fireCommand(
          LampCommandId.enterReplace,
          brightness: (plan?.lightLevelWindDown ?? 50) + 10,
        );
        break;
      case NightSessionState.finished:
        await _fireCommand(
          LampCommandId.finish,
          brightness: plan?.lightLevelBedtime ?? 5,
        );
        break;
    }
  }

  /// 清空 AI 对话历史
  void clearAiHistory() => ai.clearHistory();

  // ============ 用户档案 → AI 上下文 ============

  /// 登录/建档/档案编辑后调用：把最新档案注入 AI 对话上下文
  void syncProfileContext() {
    final u = AuthService.user;
    if (u == null) {
      ai.setProfileContext(null);
      return;
    }
    ai.setProfileContext(
      '（我的睡眠档案）我通常 ${u.bedtime} 入睡，${u.wakeTime} 起床，'
      '睡前常刷${u.apps.isEmpty ? '手机（没有特别偏好）' : u.apps}，'
      '喜欢的睡前替代活动是${u.replacementActivity}。'
      '请把我的习惯作为默认安排，除非我今晚另外说明。',
    );
  }

  /// 建档后「直接用习惯生成计划」：不经过聊天界面，静默调 AI 生成 plan
  /// Uses the latest plan for today, or the onboarding bedtime as fallback.
  /// The coordinator stays idle until the two-hour monitoring window begins.
  Future<void> syncUsageMonitoring({DateTime? now}) async {
    final profile = AuthService.user;
    final current = now ?? DateTime.now();
    if (profile == null) return;
    if (usageMonitor.isRunning) {
      final locked = usageMonitor.currentSchedule;
      if (locked == null || current.isBefore(locked.targetBedtime)) {
        final active = locked != null && !current.isBefore(locked.startAt);
        if (active) return;
        await usageMonitor.stop();
      } else {
        await usageMonitor.stop();
        if (_pendingTonightPlan != null) {
          final pending = _pendingTonightPlan!;
          _pendingTonightPlan = null;
          _applyTonightPlan(pending);
          return;
        }
      }
    }
    final schedule = MonitorScheduleService.resolveFor(
      DateTime(current.year, current.month, current.day),
      tonightPlan,
      profile,
    );
    await usageMonitor.start(schedule);
  }

  Future<bool> generatePlanFromProfile() async {
    final u = AuthService.user;
    if (u == null) return false;
    try {
      final prompt =
          '请根据我的睡眠档案直接生成今晚的计划：我通常 ${u.bedtime} 入睡，${u.wakeTime} 起床，'
          '睡前常刷${u.apps.isEmpty ? '手机' : u.apps}，喜欢的替代活动是${u.replacementActivity}。'
          '今晚就按我的习惯来，直接给计划，不要问我问题。';
      final plan = await ai.generatePlan(
        prompt: prompt,
        bedtime: u.bedtime,
        wakeTime: u.wakeTime,
        replacementActivity: u.replacementActivity,
      );
      setTonightPlan(plan);
      return true;
    } catch (e) {
      debugPrint('[AppController] 档案生成计划失败: $e');
      return false;
    }
  }

  // ================ 辅助工具 ================

  /// 从当前时间到"HH:MM"字符串还有多少分钟；若该时间已经过去就返回 fallback
  int _minutesFromNowTo(String hhmm, {int fallback = 5}) {
    final now = DateTime.now();
    final parts = hhmm.split(':');
    if (parts.length != 2) return fallback;
    final hh = int.tryParse(parts.first);
    final mm = int.tryParse(parts.last);
    if (hh == null || mm == null) return fallback;
    DateTime target = DateTime(now.year, now.month, now.day, hh, mm);
    if (target.isBefore(now.subtract(const Duration(minutes: 5)))) {
      target = target.add(const Duration(days: 1)); // 跨午夜
    }
    final diff = target.difference(now).inMinutes;
    if (diff < 0) return fallback;
    if (diff > 240) return 240; // 最多 4 小时
    return diff;
  }

  @override
  void dispose() {
    _disposed = true;
    _lampSubscription.cancel();
    _timelineTimer?.cancel();
    _stopForegroundService();
    FlutterForegroundTask.removeTaskDataCallback(_handleForegroundTaskData);
    _usageMonitorSubscription.cancel();
    usageMonitor.dispose();
    lamp.dispose();
    super.dispose();
  }

  // ================ 前台服务：保证 App 在后台时时间线继续运行 ================

  Future<void> _startForegroundService() async {
    try {
      await FlutterForegroundTask.startService(
        callback: startCallback,
        notificationTitle: '晚屿',
        notificationText: '睡前时间线运行中…',
      );
      debugPrint('[AppController] 前台服务启动成功');
    } catch (e) {
      debugPrint('[AppController] 前台服务启动失败: $e');
    }
  }

  void _stopForegroundService() {
    try {
      FlutterForegroundTask.stopService();
    } catch (_) {
      // 忽略
    }
  }
}

/// 时间线引擎的单个事件（私有数据类）
class _TlEvent {
  /// 距上一个事件的真实秒数（已按演示加速换算 + 最小间隔保护）
  final int delaySec;
  /// plan 里的原始时间字符串（如 "23:15"，UI 展示用）
  final String planTime;
  /// 阶段描述（如「第 2 步 · 放下手机」）
  final String label;
  /// 目标亮度；null = 保持不变（询问点）
  final int? brightness;
  /// 要发给硬件的命令；null = 不发
  final LampCommandId? command;
  /// 要切到的本地状态；null = 不切
  final NightSessionState? state;
  /// 是否为「询问是否延时」点
  final bool ask;

  const _TlEvent({
    required this.delaySec,
    required this.planTime,
    required this.label,
    this.brightness,
    this.command,
    this.state,
    this.ask = false,
  });
}
