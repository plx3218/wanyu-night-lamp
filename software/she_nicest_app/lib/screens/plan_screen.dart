import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models/tonight_plan.dart';
import '../theme/app_theme.dart';

class PlanScreen extends StatelessWidget {
  const PlanScreen({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('确认今晚计划')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55102028), Color(0xCC14252B)],
                stops: [0, 0.4],
              ),
            ),
          ),
          SafeArea(
            // AnimatedBuilder：ChatScreen 里刚生成 plan → PlanScreen 立刻重建显示新内容
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final plan = controller.tonightPlan;
                if (plan == null) {
                  return const _EmptyPlanState();
                }
                return _PlanReadyView(plan: plan, controller: controller);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ============ 空状态：还没和 AI 聊过 → 引导回到聊天页 ============
class _EmptyPlanState extends StatelessWidget {
  const _EmptyPlanState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const SizedBox(height: 40),
        Icon(
          Icons.nightlight_round,
          size: 72,
          color: AppColors.moon.withValues(alpha: 0.85),
        ),
        const SizedBox(height: 28),
        const Text(
          '今晚的安排还没生成哦',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.25),
        ),
        const SizedBox(height: 14),
        const Text(
          '告诉她明早几点起床、今晚还有什么要做、现在累不累——她会根据你今天的真实状态，写一份最多三步、能做得到的睡前计划。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 15.5),
        ),
        const SizedBox(height: 38),
        FilledButton.icon(
          onPressed: () {
            // 回到首页 Tab(1=聊天)；若外层路由管理有不同方式，可改为直接 pop
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('先和她聊聊'),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          label: const Text('返回上一页'),
        ),
      ],
    );
  }
}

/// ============ Ready 状态：AI 已生成 TonightPlan → 完整卡片渲染 ============
class _PlanReadyView extends StatelessWidget {
  const _PlanReadyView({required this.plan, required this.controller});
  final TonightPlan plan;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final steps = plan.normalizedSteps();
    final assumptionsText = plan.displayAssumptions();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // 顶部徽标：现在是"AI 专属"，不再是模拟演示
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lake.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.lake.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.lake),
                  SizedBox(width: 6),
                  Text('为你定制', style: TextStyle(fontSize: 13, color: AppColors.lake)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '给今天一个柔和的结尾',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, height: 1.25),
        ),
        const SizedBox(height: 12),
        Text(
          plan.displayHeadline(),
          style: const TextStyle(color: AppColors.textSecondary, height: 1.55),
        ),
        const SizedBox(height: 24),
        // 观测阈值提示：与 hardware 联动预埋
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.moon.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.moon.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.visibility_outlined, color: AppColors.moon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  plan.displayThresholdText() +
                      '\n替代活动：${plan.replacementActivity} · 最多可再延长 ${plan.extensionMinutes} 分钟',
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        _MonitorWindowCard(controller: controller),
        const SizedBox(height: 30),
        // 3 步：step 渲染完全复用 AI 生成的 time+action，不再硬编码
        for (int i = 0; i < steps.length; i++) ...[
          _PlanStep(
            time: steps[i].time,
            title: steps[i].action,
            detail: steps[i].displayDetail(),
            index: i,
            total: steps.length,
          ),
          if (i != steps.length - 1) const SizedBox(height: 4),
        ],
        // 假设说明（如果 AI 标注了默认值）
        if (assumptionsText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.dusk.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textTertiary),
                    SizedBox(width: 6),
                    Text('这些是我按一般情况做的假设',
                        style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  assumptionsText,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 4),
                const Text(
                  '不合适的话，随时回聊天页告诉我，我会重新生成。',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        // ===== 2026-08-29 新增：调试区「立即同步灯光」，硬件偶发不同步时用户可以手动兜底 =====
        AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final lamp = controller.lampState;
            final String lampInfo;
            if (!controller.isEsp32Mode) {
              lampInfo = '当前为模拟灯光模式，不控制真实灯带';
            } else if (lamp.connected) {
              lampInfo = '灯：${lamp.rawState ?? '在线'} · 亮度 ${lamp.brightness}% · ${controller.lampHost}';
            } else {
              lampInfo = '灯未连接（${controller.lampHost}），先回到首页配对';
            }
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.moon.withValues(alpha: 0.22)),
                color: AppColors.moon.withValues(alpha: 0.05),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lampInfo,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (controller.isEsp32Mode && lamp.connected)
                              ? () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('正在按当前计划强制同步灯光…'),
                                      backgroundColor: AppColors.cardBg,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 1),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                  );
                                  // 手动按 plan 对应状态发一次 PLANNED 暖光 (lightLevel2)
                                  await controller.debugSyncCurrentStateToLamp();
                                }
                              : null,
                          icon: const Icon(Icons.sync_alt_rounded, size: 18),
                          label: const Text('立即同步灯光'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/lamp'),
                        icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                        label: const Text('灯设置'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            try {
              await controller.confirmPlan();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/session');
              }
            } on PlanNotReadyException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message)),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('启动失败：${e.toString().substring(0, 40)}')),
              );
            }
          },
          child: const Text('开始今晚计划'),
        ),
        TextButton(
          onPressed: () {
            // "再聊一会儿" → 返回聊天页（保留当前 plan，用户还可以继续补充信息覆盖它）
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('再聊一会儿，换一个'),
        ),
      ],
    );
  }
}

/// 单步组件（连接 AI plan 的 time / title / detail）
class _MonitorWindowCard extends StatelessWidget {
  const _MonitorWindowCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final schedule = controller.monitorSchedule;
    final event = controller.lastUsageMonitorEvent;
    final status = event?.type.name ?? 'not_started';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.lake, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              schedule == null
                  ? '监测时间尚未建立；没有权限时仍会执行本地计划。'
                  : '监测：${_fmt(schedule.startAt)} 开始，目标入睡 ${_fmt(schedule.targetBedtime)}\n状态：$status · 同类娱乐连续 20 分钟提醒',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({
    required this.time,
    required this.title,
    required this.detail,
    required this.index,
    required this.total,
  });

  final String time;
  final String title;
  final String detail;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              time,
              style: const TextStyle(color: AppColors.moon, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.dusk.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '第 ${index + 1} / $total 步',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
