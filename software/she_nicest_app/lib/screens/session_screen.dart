import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/night_session.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_session_dialog.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  // ================== 时间线展示层（引擎在 AppController，页面只渲染）============
  // 灯光按 AI plan 的时间点自动推进（演示加速 1 分钟 = 1 秒）：
  //   第一步时间 → 70% → 第二步时间 → 50% → 最后时间 → 弹窗询问延时
  //   选"是"保持 50% 延时 X 分钟 → 自动 5% 夜灯；选"否"直接 5%。
  // 页面每秒 setState 刷新圆环倒计时（真实计时在 controller 的 Timer 里）。
  // 弹窗由 main.dart 全局管理，本页面只负责渲染 UI。

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicking();
    // 注册回调：时间线事件触发时弹毛玻璃弹窗
    widget.controller.onAskExtend = _showAskExtendDialog;
    widget.controller.onShowStageInfo = _showStageInfoDialog;
    // 后台→前台恢复时：检查 pending 弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingDialogs());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.onAskExtend = null;
    widget.controller.onShowStageInfo = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingDialogs();
    }
  }

  /// 检查 pending 队列：App 从后台恢复时，弹窗可能积压
  void _checkPendingDialogs() {
    if (!mounted) return;
    if (widget.controller.consumePendingAskExtend()) {
      _showAskExtendDialog();
      return;
    }
    final stageInfo = widget.controller.consumePendingStageInfo();
    if (stageInfo != null) {
      _showStageInfoDialog(stageInfo.title, stageInfo.body);
    }
  }

  /// 延时询问弹窗（毛玻璃版）
  /// 状态由 extendCount 决定：
  ///   0 = 第一次问（步骤3到，亮度50%）
  ///   1 = 第一次延时结束 → "还需要延时么"（亮度5%）
  ///   2 = 第二次延时结束 → "你已经用手机时间很长了"（亮度5%）
  void _showAskExtendDialog() {
    if (!mounted) return;
    final s = widget.controller.nightSession;
    final plan = s.plan;
    final extMin = plan?.extensionMinutes ?? 10;
    final extSec = AppController.minutesToDemoSeconds(extMin);
    final bedBright = plan?.lightLevelBedtime ?? 5;
    final brightness = s.extendCount == 0 ? (plan?.lightLevelWindDown ?? 50) : bedBright;

    String title;
    String subtitle;
    String primaryLabel;
    String secondaryLabel;

    switch (s.extendCount) {
      case 0:
        title = '已经刷了一会儿';
        subtitle = '到了计划的入睡提醒时间。还想继续，还是准备慢慢入睡？';
        primaryLabel = '再延时 $extMin 分钟';
        secondaryLabel = '不用了，准备入睡';
      case 1:
        title = '还需要延时么';
        subtitle = '延时时间到了，如果还需要一点时间可以再延时。';
        primaryLabel = '再延时 $extMin 分钟';
        secondaryLabel = '不用了';
      case 2:
        title = '你已经用手机时间很长了';
        subtitle = '快休息吧，明天还有很多时间。';
        primaryLabel = '再延时 $extMin 分钟';
        secondaryLabel = '不用了';
      default:
        return; // extendCount >= 3 不应该弹窗（直接 5%）
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => FrostedSessionDialog(
        title: title,
        subtitle: subtitle,
        brightness: brightness,
        primaryLabel: primaryLabel,
        onPrimary: () {
          Navigator.of(context).pop();
          widget.controller.extendSession();
        },
        secondaryLabel: secondaryLabel,
        onSecondary: () {
          Navigator.of(context).pop();
          widget.controller.finishSession();
        },
        lampStatus: '灯光已同步',
        demoHint: '(演示加速: 延时$extMin分钟=${extSec}秒)',
      ),
    );
  }

  /// 阶段信息弹窗（毛玻璃版）— 步骤2 的"准备结束今天"
  void _showStageInfoDialog(String title, String body) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (_) => FrostedSessionDialog(
        title: body,
        subtitle: '温柔守护中，不必立刻停下来。',
        primaryLabel: '知道了',
        onPrimary: () => Navigator.of(context).pop(),
        lampStatus: '灯光已同步',
      ),
    );
  }

  /// 每秒刷新倒计时显示（引擎计时在 controller，页面只负责渲染）
  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // ================== 当前 APP 端"模拟亮度"：跟随状态变化（屏幕渐变颜色） ==================
  ({List<Color> gradient, Color overlay}) _ambience(NightSession s) {
    switch (s.state) {
      case NightSessionState.unplanned:
      case NightSessionState.planned:
        return (
          gradient: const [Color(0x55102028), Color(0xD014252B)],
          overlay: const Color(0x00000000),
        );
      case NightSessionState.observing:
        // 暖湖蓝 · 呼吸守护
        return (
          gradient: const [Color(0x550E1E26), Color(0xE01A3340)],
          overlay: Color.lerp(
              AppColors.lake.withValues(alpha: 0.06),
              AppColors.lake.withValues(alpha: 0.14),
              0.5 + 0.5 * math.sin(DateTime.now().millisecondsSinceEpoch / 1800))!,
        );
      case NightSessionState.nudged:
        // 琥珀提醒 · 昏暗
        return (
          gradient: const [Color(0x60201A0E), Color(0xE02C2216)],
          overlay: AppColors.dusk.withValues(alpha: 0.22),
        );
      case NightSessionState.replacing:
        return (
          gradient: const [Color(0x5512262E), Color(0xE01B323C)],
          overlay: AppColors.lake.withValues(alpha: 0.06),
        );
      case NightSessionState.extending:
        return (
          gradient: const [Color(0x501B2E38), Color(0xE01E3848)],
          overlay: const Color(0x00000000),
        );
      case NightSessionState.muted:
        return (
          gradient: const [Color(0x66142026), Color(0xE21A2830)],
          overlay: Colors.black.withValues(alpha: 0.08),
        );
      case NightSessionState.finished:
        // 全黑 5% 夜灯
        return (
          gradient: const [Color(0x900A1116), Color(0xF50B131A)],
          overlay: Colors.black.withValues(alpha: 0.32),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          // 跟随状态变化的屏幕色彩"虚拟亮度分级"（v0 固件无分级时也有视觉反馈）
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final ambience = _ambience(widget.controller.nightSession);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: ambience.gradient,
                    stops: const [0, 0.5],
                  ),
                ),
                child: Container(color: ambience.overlay),
              );
            },
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final s = widget.controller.nightSession;
                // LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight):
                // 内容少 → Spacer 撑满 minHeight，圆环垂直居中（保留原视觉）
                // 内容多（固定 230 圆环 + plan 卡 + 按钮组超屏）→ 可滚动，不再 bottom overflow
                return LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(s),
                            const Spacer(),
                            _buildHeadline(s),
                            const SizedBox(height: 14),
                            _buildSubtitle(s),
                            const SizedBox(height: 28),
                            _buildTonightPlanSummaryCard(s),
                            const SizedBox(height: 22),
                            _buildRing(s),
                            const Spacer(),
                            if (s.lastLampMessage != null && s.lastLampMessage!.isNotEmpty)
                              _buildLampStatus(s),
                            const SizedBox(height: 20),
                            _buildActionButtons(s),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // =============== UI 子组件 ===============

  Widget _buildHeader(NightSession s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => Navigator.popUntil(context, ModalRoute.withName('/')),
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          tooltip: '返回首页',
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _stateColor(s.state).withValues(alpha: 0.12),
            border: Border.all(color: _stateColor(s.state).withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_stateIcon(s.state), size: 14, color: _stateColor(s.state)),
              const SizedBox(width: 6),
              Text(s.displayState,
                  style: TextStyle(fontSize: 13, color: _stateColor(s.state))),
            ],
          ),
        ),
      ],
    );
  }

  /// AI plan 概要卡：直接展示 TonightPlan 关键值，彻底解决"页面与 AI 指令不对应"问题
  Widget _buildTonightPlanSummaryCard(NightSession s) {
    final plan = s.plan;
    if (plan == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Text(
          '还没有 AI 生成的专属 plan。先退出，和她聊聊生成一份。',
          style: TextStyle(color: AppColors.textTertiary, height: 1.5, fontSize: 13),
        ),
      );
    }
    final thMin = plan.continuousThresholdMin ?? 10;
    final thSec = AppController.minutesToDemoSeconds(thMin);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.moon.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.moon.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          _PlanRow(icon: Icons.nights_stay_outlined, label: '明早起床', value: _fmt(plan.wakeTime)),
          const SizedBox(height: 8),
          _PlanRow(icon: Icons.bedtime_rounded, label: '建议入睡', value: _fmt(plan.recommendedBedtime)),
          const SizedBox(height: 8),
          _PlanRow(
              icon: Icons.timer_outlined,
              label: '使用阈值（现场加速）',
              value: '$thMin 分钟（约 $thSec 秒）'),
          const SizedBox(height: 8),
          _PlanRow(icon: Icons.self_improvement_rounded, label: '替代活动', value: plan.replacementActivity),
          const SizedBox(height: 8),
          _PlanRow(
              icon: Icons.more_time_rounded,
              label: '最多可延长',
              value: '${plan.extensionMinutes} 分钟'),
        ],
      ),
    );
  }

  Widget _buildHeadline(NightSession s) {
    final plan = s.plan;
    switch (s.state) {
      case NightSessionState.unplanned:
        return const Text('今晚还没安排', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600));
      case NightSessionState.planned:
        return Text(
            plan == null
                ? '今晚计划已就绪，等你开始'
                : '明早 ${_fmt(plan.wakeTime)} 起 · 目标 ${_fmt(plan.recommendedBedtime)} 前入睡',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.3));
      case NightSessionState.observing:
        return const Text('温柔守护中，不必立刻停下来',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500));
      case NightSessionState.nudged:
        return const Text('已经刷了一会儿',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600));
      case NightSessionState.replacing:
        return Text('换个温柔的方式：${plan?.replacementActivity ?? '听听音乐'}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.3));
      case NightSessionState.extending:
        return Text('好，再陪你 ${s.extensionMinutesLeft} 分钟',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600));
      case NightSessionState.muted:
        return const Text('这次我不打扰', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600));
      case NightSessionState.finished:
        return const Text('晚安，今天就到这里',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600));
    }
  }

  Widget _buildSubtitle(NightSession s) {
    const style = TextStyle(color: AppColors.textSecondary, height: 1.55);
    final plan = s.plan;
    final c = widget.controller;
    switch (s.state) {
      case NightSessionState.unplanned:
        return const Text('关闭这个页面，去和她聊聊生成一份专属计划。', style: style);
      case NightSessionState.planned:
        return Text(
            plan == null
                ? '准备好了，点"开始守护"进入。'
                : '从今晚 ${_fmt(plan.windDownTime)} 起留意。${_fmt(plan.reminderTime)} 我再叫你。替代活动：${plan.replacementActivity}。',
            style: style);
      case NightSessionState.observing:
        // 时间线模式：显示当前步骤 + 下一站（AI plan 的真实时间点）
        if (c.timelineCurrentLabel.isNotEmpty && c.timelineNextLabel.isNotEmpty) {
          final nextTimeTxt = c.timelineNextPlanTime.isNotEmpty
              ? '${_fmt(c.timelineNextPlanTime)} '
              : '';
          return Text(
              '${c.timelineCurrentLabel}\n下一站：$nextTimeTxt${c.timelineNextLabel}（演示加速中）',
              style: style);
        }
        return Text(plan?.displayThresholdText() ?? '', style: style);
      case NightSessionState.nudged:
        return Text(
            '到了计划的入睡提醒时间。还想继续，还是准备慢慢入睡？替代活动可以是${plan?.replacementActivity ?? '音乐'}。',
            style: style);
      case NightSessionState.replacing:
        return const Text('不用硬逼自己立刻睡。找一件能让你慢慢安静下来的事。', style: style);
      case NightSessionState.extending: {
        final sec = AppController.minutesToDemoSeconds(s.extensionMinutesLeft);
        return Text(
            '这次再延长 ${s.extensionMinutesLeft} 分钟（现场约 $sec 秒），到点自动进入入睡陪伴，切换至 5% 夜灯。已延长 ${s.extendCount} 次。',
            style: style);
      }
      case NightSessionState.muted:
        return const Text('本次不再做灯光/通知提醒，但记录依然在继续。', style: style);
      case NightSessionState.finished:
        return Text(
            plan == null
                ? '灯光已调成 5% 夜灯模式'
                : '已按计划在 ${_fmt(plan.recommendedBedtime)} 进入入睡陪伴。5% 夜灯开启 · 明早 ${_fmt(plan.wakeTime)} 见。',
            style: style);
    }
  }

  Widget _buildRing(NightSession s) {
    // ===== 时间线模式：倒计时到下一个事件（引擎在 controller）=====
    final fireAt = widget.controller.nextTimelineFireAt;
    final int secondsLeft = (fireAt == null)
        ? 0
        : fireAt.difference(DateTime.now()).inSeconds.clamp(0, 99999);
    final int initial = widget.controller.nextEventInitialSec <= 0
        ? 1
        : widget.controller.nextEventInitialSec;
    final progress = s.state == NightSessionState.finished
        ? 1.0
        : (fireAt == null ? 1.0 : (initial - secondsLeft) / initial);
    final String centerText;
    switch (s.state) {
      case NightSessionState.observing:
      case NightSessionState.extending:
      case NightSessionState.planned:
        centerText = fireAt != null && secondsLeft > 0 ? '$secondsLeft' : '准备好了';
        break;
      case NightSessionState.nudged:
        centerText = '点我选择';   // ← 文字更明确告诉用户可以点
        break;
      case NightSessionState.finished:
        centerText = '晚安';
        break;
      case NightSessionState.replacing:
        centerText = s.plan?.replacementActivity ?? '替换中';
        break;
      case NightSessionState.muted:
        centerText = '安静';
        break;
      case NightSessionState.unplanned:
        centerText = '未开始';
        break;
    }
    // ===== 2026-08-29 修复：把圆环包上 GestureDetector，让中心文字真的能点 =====
    Widget inner = SizedBox(
      width: 230,
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 3,
            color: _stateColor(s.state),
            backgroundColor: Colors.white10,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerText,
                    style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w400,
                        color: _stateColor(s.state))),   // 点击态颜色提示
                const SizedBox(height: 6),
                Text(
                  (s.state == NightSessionState.observing ||
                          s.state == NightSessionState.extending ||
                          s.state == NightSessionState.planned) &&
                          fireAt != null
                      ? widget.controller.timelineNextLabel
                      : '已提醒 ${s.nudgeCount} 次',
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // NUDGED / OBSERVING 状态可以点（其他状态点了也没意义）
    final canTap = s.state == NightSessionState.nudged ||
        s.state == NightSessionState.observing ||
        s.state == NightSessionState.planned;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canTap ? () => _onRingTapped(s) : null,
      child: inner,
    );
  }

  /// 圆环点击响应：根据当前状态弹出合适的交互
  Future<void> _onRingTapped(NightSession s) async {
    switch (s.state) {
      case NightSessionState.nudged:
        // NUDGED → 弹出 3 选 1 底部菜单
        final plan = s.plan;
        final extMin = plan?.extensionMinutes ?? 10;
        final repl = plan?.replacementActivity ?? '换一下';
        final choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF162930),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('接下来想怎么来？',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _SheetTile(
                    icon: Icons.more_time_rounded,
                    title: '再陪我 $extMin 分钟',
                    subtitle: '继续看一会，我记住时间',
                    color: AppColors.moon,
                    onTap: () => Navigator.pop(context, 'extend'),
                  ),
                  const SizedBox(height: 10),
                  _SheetTile(
                    icon: Icons.self_improvement_rounded,
                    title: '换个方式放松',
                    subtitle: '温柔陪你慢慢安静下来',
                    color: AppColors.lake,
                    onTap: () => Navigator.pop(context, 'replace'),
                  ),
                  const SizedBox(height: 10),
                  _SheetTile(
                    icon: Icons.bedtime_rounded,
                    title: '准备入睡 / 晚安',
                    subtitle: '今天就到这里，灯光变暗陪你',
                    color: AppColors.dusk,
                    onTap: () => Navigator.pop(context, 'finish'),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
        if (choice == null) return;
        switch (choice) {
          case 'extend':
            await widget.controller.extendSession();
            break;
          case 'replace':
            await widget.controller.switchToReplacing();
            break;
          case 'finish':
            final res = await widget.controller.finishSession();
            if (!res.allowed && mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(res.reason)));
            } else {
              await Future<void>.delayed(const Duration(seconds: 1));
              if (mounted) Navigator.popUntil(context, ModalRoute.withName('/'));
            }
            break;
        }
        break;
      case NightSessionState.observing:
        // OBSERVING → 直接跳到询问点（时间线引擎快进，灯保持 50% + 弹延时询问）
        widget.controller.skipToAskPoint();
        break;
      case NightSessionState.planned:
        // PLANNED → 开始守护
        await widget.controller.confirmPlan();
        break;
      default:
        break;
    }
  }

  Widget _buildLampStatus(NightSession s) {
    final ok = s.lampOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (ok ? AppColors.lake : AppColors.dusk).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (ok ? AppColors.lake : AppColors.dusk).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle_outline_rounded : Icons.signal_wifi_off_rounded,
                  size: 18, color: ok ? AppColors.lake : AppColors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.lastLampMessage ?? (ok ? '灯光同步中' : '灯光离线，计划仍在继续'),
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.textSecondary, height: 1.4)),
              ),
              // 2026-08-29 新增：手动兜底按钮
              IconButton.filledTonal(
                onPressed: widget.controller.isEsp32Mode && widget.controller.lampState.connected
                    ? () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('正在按当前状态强制同步灯光…'),
                            backgroundColor: AppColors.cardBg,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        );
                        await widget.controller.debugSyncCurrentStateToLamp();
                      }
                    : null,
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.moon,
                  backgroundColor: AppColors.moon.withValues(alpha: 0.14),
                ),
                icon: const Icon(Icons.sync_alt_rounded, size: 18),
                tooltip: '立即同步灯光',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(NightSession s) {
    final extMin = s.plan?.extensionMinutes ?? 10;
    final repl = s.plan?.replacementActivity ?? '替代活动';
    switch (s.state) {
      case NightSessionState.unplanned:
        return FilledButton(
          onPressed: () => Navigator.popUntil(context, ModalRoute.withName('/')),
          child: const Text('先去生成今晚安排'),
        );
      case NightSessionState.planned:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: () async {
                try {
                  await widget.controller.confirmPlan();
                } on PlanNotReadyException catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                } catch (_) {}
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始守护'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => widget.controller.restoreLight(),
              child: const Text('需要更亮（恢复照明）'),
            ),
          ],
        );
      case NightSessionState.observing:
      case NightSessionState.muted:
        return Column(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => widget.controller.skipToAskPoint(),
              child: const Text('跳到询问时刻（演示快进）'),
            ),
            const SizedBox(height: 10),
            if (s.state == NightSessionState.observing)
              TextButton(
                onPressed: () => widget.controller.muteReminder(),
                child: const Text('本次不用提醒我'),
              )
            else
              TextButton(
                onPressed: () => widget.controller.unmuteReminder(),
                child: const Text('恢复提醒'),
              ),
          ],
        );
      case NightSessionState.nudged:
        return Column(
          children: [
            FilledButton(
              onPressed: () async {
                final res = await widget.controller.extendSession();
                if (!res.allowed && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.reason)));
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.more_time_rounded),
                  const SizedBox(width: 8),
                  Text('再陪我 $extMin 分钟'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => widget.controller.switchToReplacing(),
              child: Text('换一下：$repl'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => widget.controller.muteReminder(),
              child: const Text('本次不用提醒我'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final res = await widget.controller.finishSession();
                if (!mounted) return;
                if (!res.allowed) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.reason)));
                  return;
                }
                await Future<void>.delayed(const Duration(seconds: 1));
                if (mounted) Navigator.popUntil(context, ModalRoute.withName('/'));
              },
              icon: const Icon(Icons.bedtime_rounded),
              label: const Text('准备入睡 / 晚安'),
            ),
          ],
        );
      case NightSessionState.extending:
        return Column(
          children: [
            FilledButton(
              onPressed: () => widget.controller.extendSession(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.more_time_rounded),
                  const SizedBox(width: 8),
                  Text('再多 $extMin 分钟'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final res = await widget.controller.finishSession();
                if (!mounted) return;
                if (!res.allowed) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.reason)));
                  return;
                }
                await Future<void>.delayed(const Duration(seconds: 1));
                if (mounted) Navigator.popUntil(context, ModalRoute.withName('/'));
              },
              icon: const Icon(Icons.bedtime_rounded),
              label: const Text('不看了，准备睡'),
            ),
          ],
        );
      case NightSessionState.replacing:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: () async {
                final res = await widget.controller.finishSession();
                if (!mounted) return;
                if (!res.allowed) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.reason)));
                  return;
                }
                await Future<void>.delayed(const Duration(seconds: 1));
                if (mounted) Navigator.popUntil(context, ModalRoute.withName('/'));
              },
              icon: const Icon(Icons.bedtime_rounded),
              label: const Text('差不多了，去睡'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => widget.controller.restoreLight(),
              child: const Text('需要更亮（恢复照明）'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Demo 版本替代活动仅保留灯光陪你，不自动播放白噪音 / 播客。',
              style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case NightSessionState.finished:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: () => widget.controller.switchToReplacing(),
              icon: const Icon(Icons.phone_android_rounded),
              label: const Text('我还要再看一会儿'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.popUntil(context, ModalRoute.withName('/')),
              child: const Text('好的，离开'),
            ),
          ],
        );
    }
  }

  Color _stateColor(NightSessionState st) {
    switch (st) {
      case NightSessionState.unplanned: return AppColors.textTertiary;
      case NightSessionState.planned: return AppColors.moon;
      case NightSessionState.observing: return AppColors.lake;
      case NightSessionState.nudged: return AppColors.dusk;
      case NightSessionState.replacing: return AppColors.lake;
      case NightSessionState.extending: return AppColors.moon;
      case NightSessionState.muted: return AppColors.textTertiary;
      case NightSessionState.finished: return AppColors.moon;
    }
  }

  IconData _stateIcon(NightSessionState st) {
    switch (st) {
      case NightSessionState.unplanned: return Icons.event_busy_rounded;
      case NightSessionState.planned: return Icons.wb_incandescent_rounded;
      case NightSessionState.observing: return Icons.visibility_outlined;
      case NightSessionState.nudged: return Icons.notifications_active_outlined;
      case NightSessionState.replacing: return Icons.self_improvement_rounded;
      case NightSessionState.extending: return Icons.more_time_rounded;
      case NightSessionState.muted: return Icons.notifications_off_outlined;
      case NightSessionState.finished: return Icons.nightlight_round;
    }
  }

  static String _fmt(String hhmm) {
    if (hhmm.isEmpty) return '——';
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts.first);
    return h == null ? hhmm : '$h:${parts[1]}';
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.moon.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary, height: 1.4)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

/// NUDGED 底部菜单的一行
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            color: color.withValues(alpha: 0.08),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
