import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../services/auth_service.dart';
import '../services/esp32_lamp_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TextEditingController _ipController;
  bool _isConnecting = false;
  String? _connectMessage;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.controller.lampHost);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _handleConnectToggle() async {
    if (!widget.controller.isEsp32Mode) {
      // 模拟模式下直接走模拟灯
      setState(() => _isConnecting = true);
      await widget.controller.toggleLampConnection();
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectMessage = widget.controller.lampState.connected ? '已进入模拟灯光模式' : '已断开';
        });
      }
      return;
    }

    // ESP32 模式
    final host = _ipController.text.trim();
    if (host.isEmpty) {
      setState(() => _connectMessage = '请先输入 ESP32 的 IP 地址');
      return;
    }
    // 保存 IP
    widget.controller.updateLampHost(host);

    setState(() {
      _isConnecting = true;
      _connectMessage = null;
    });

    try {
      if (widget.controller.lampState.connected) {
        await widget.controller.disconnectLamp();
        if (mounted) {
          setState(() {
            _connectMessage = '已断开晚风灯连接';
          });
        }
      } else {
        await widget.controller.connectLamp();
        if (mounted) {
          final ok = widget.controller.lampState.connected;
          setState(() {
            _connectMessage = ok ? '晚风灯已连接 ✦' : '连接失败，请确认 IP 和同一热点后重试';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectMessage = '连接出错：${e.toString().characters.take(40).toString()}';
        });
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _AppDrawer(controller: widget.controller),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // === 环境层：洱海蓝小时自然场景 ===
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33102028), Color(0x22102028), Color(0xE614252B)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === 顶部：侧边栏入口 + 灯光状态 ===
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Builder(
                        builder: (context) => IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            foregroundColor: AppColors.textPrimary,
                          ),
                          onPressed: Scaffold.of(context).openDrawer,
                          icon: const Icon(Icons.menu_rounded, size: 22),
                          tooltip: '打开菜单',
                        ),
                      ),
                      AnimatedBuilder(
                        animation: widget.controller,
                        builder: (_, __) {
                          final st = widget.controller.lampState;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: st.connected
                                  ? AppColors.lake.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: st.connected
                                    ? AppColors.lake.withValues(alpha: 0.45)
                                    : Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  st.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                                  size: 16,
                                  color: st.connected ? AppColors.lake : Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  st.connected ? '晚风灯在线' : '灯未连接',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: st.connected ? AppColors.lake : AppColors.textTertiary,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // === Badge: AI 睡前陪伴 · 软硬协同 ===
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.moon.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.moon.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'AI 睡前陪伴 · 软硬协同',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.moon, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // === 设备配对输入框（按 UI-Design-Final 02 规范） ===
                  _IpPairingCard(
                    controller: _ipController,
                    isEsp32Mode: widget.controller.isEsp32Mode,
                    isConnecting: _isConnecting,
                    connected: widget.controller.lampState.connected,
                    message: _connectMessage,
                    onConnect: _handleConnectToggle,
                  ),
                  // === 主空间：时间 + 欢迎语 ===
                  const Spacer(),
                  StreamBuilder(
                    stream: Stream.periodic(const Duration(seconds: 1)),
                    builder: (context, _) {
                      final now = DateTime.now();
                      final hh = now.hour.toString().padLeft(2, '0');
                      final mm = now.minute.toString().padLeft(2, '0');
                      return Text(
                        '$hh:$mm',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w300,
                          height: 1.0,
                          color: AppColors.textPrimary.withValues(alpha: 0.9),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '今晚想从哪里说起?',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '我在这里，慢慢说就好',
                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  // === 轻触画面开始（进入 AI 对话） ===
                  Semantics(
                    button: true,
                    label: '进入 AI 对话，获取今日睡前规划',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () => Navigator.pushNamed(context, '/chat'),
                      child: Ink(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          color: const Color(0xD91B3037),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.moon.withValues(alpha: 0.06),
                              blurRadius: 28,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.mic_rounded, color: AppColors.moon, size: 22),
                            SizedBox(width: 10),
                            Text('轻触画面开始', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // === 新增：当 AI 已生成 plan 时，首页直接显示「看看今晚安排」大按钮（不再藏在抽屉里） ===
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (_, __) {
                      final hasPlan = widget.controller.hasTonightPlan;
                      final plan = widget.controller.tonightPlan;
                      if (!hasPlan) return const SizedBox.shrink();
                      String sub;
                      try {
                        sub = '明早 ${plan!.wakeTime.replaceFirst(RegExp(r'^0'), '')} 起 · ${plan.steps.length} 步睡前安排';
                      } catch (_) {
                        sub = '已生成专属睡前安排';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Semantics(
                          button: true,
                          label: '查看 AI 生成的今晚安排',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => Navigator.pushNamed(context, '/plan'),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                              decoration: BoxDecoration(
                                color: AppColors.moon.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: AppColors.moon.withValues(alpha: 0.42)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      color: AppColors.moon.withValues(alpha: 0.2),
                                    ),
                                    child: const Icon(Icons.nights_stay_rounded, color: AppColors.moon),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('看看今晚的安排',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(sub,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors.textSecondary,
                                                height: 1.3)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      size: 18, color: AppColors.moon),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: widget.controller,
                    builder: (_, __) {
                      final st = widget.controller.lampState;
                      return Row(
                        children: [
                          Icon(
                            st.connected ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: st.connected ? AppColors.moon : Colors.white60,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              st.connected
                                  ? '灯光就绪 · 当前状态 ${st.rawState ?? 'idle'}'
                                  : widget.controller.isEsp32Mode
                                      ? '上方输入 ESP32 IP 后连接晚风灯'
                                      : '模拟灯光运行中 · 可直接进入对话',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========== IP 配对卡片（对应 UI-Design-Final 02：灯具连接页主组件） ==========
class _IpPairingCard extends StatelessWidget {
  const _IpPairingCard({
    required this.controller,
    required this.isEsp32Mode,
    required this.isConnecting,
    required this.connected,
    required this.message,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool isEsp32Mode;
  final bool isConnecting;
  final bool connected;
  final String? message;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.router_rounded, size: 18, color: AppColors.lake),
              SizedBox(width: 8),
              Text('晚风灯配对', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Spacer(),
              Text('ESP32 · HTTP LAN', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: isEsp32Mode,
                  keyboardType: TextInputType.numberWithOptions(signed: false, decimal: true),
                  style: TextStyle(
                    fontSize: 15,
                    color: isEsp32Mode ? AppColors.textPrimary : AppColors.textTertiary,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                  decoration: InputDecoration(
                    hintText: '如 172.20.10.4 （手机热点给 ESP32 的 IP）',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13, fontFamily: null),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    prefixIcon: const Icon(Icons.settings_ethernet_rounded, size: 18, color: AppColors.quiet),
                  ),
                  onSubmitted: (_) => onConnect(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: isConnecting ? null : onConnect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    backgroundColor: connected ? AppColors.lake : AppColors.moon,
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink),
                        )
                      : Text(
                          connected ? '断开' : '连接',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: connected ? AppColors.lake : AppColors.textTertiary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              '连接前请确保：iPhone 个人热点开启「最大兼容性」，ESP32 与手机在同一热点下。',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

// ========== 侧边栏（对应 UI-Design-Final 08：Profile / App 管理 / Demo 控制） ==========
class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF162930),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.lake.withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.bedtime_rounded, color: AppColors.lake),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('晚屿', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('WANYU · 睡前陪伴', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const _DrawerLabel('主空间'),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textSecondary),
                title: const Text('和 AI 聊聊 · 生成今晚计划'),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/chat');
                },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined, color: AppColors.textSecondary),
                title: const Text('今晚的安排'),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/plan');
                },
              ),
              ListTile(
                leading: const Icon(Icons.hourglass_top_outlined, color: AppColors.textSecondary),
                title: const Text('进行中 / 提醒'),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/session');
                },
              ),
              const SizedBox(height: 12),
              const _DrawerLabel('设备与设置'),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                title: const Text('个人设置 · 睡眠档案'),
                subtitle: Text(
                  AuthService.isLoggedIn
                      ? (AuthService.isAdmin ? '${AuthService.user!.username} · 管理员' : AuthService.user!.username)
                      : '未登录',
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.light_outlined, color: AppColors.textSecondary),
                title: const Text('我的晚风灯'),
                subtitle: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => Text(
                    controller.lampState.connected
                        ? '已连接 · ${controller.lampHost}'
                        : controller.isEsp32Mode
                            ? '未连接 · ${controller.lampHost}'
                            : '模拟模式',
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/lamp');
                },
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded, color: AppColors.textSecondary),
                title: const Text('重置今晚状态'),
                minLeadingWidth: 0,
                contentPadding: EdgeInsets.zero,
                horizontalTitleGap: 12,
                onTap: () async {
                  Navigator.pop(context);
                  await controller.resetSession();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('已重置今晚所有状态'),
                        backgroundColor: AppColors.cardBg,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    );
                  }
                },
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lake.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.lake.withValues(alpha: 0.22)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, size: 16, color: AppColors.lake),
                        SizedBox(width: 6),
                        Text('关于本 Demo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.lake)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'MVP 演示版本：AI 对话生成睡前规划、本地通知轻提醒、ESP32 晚风灯联动、延长 & 替代活动。',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '不提供医疗诊断 / 疗效承诺 / 睡眠评分。',
                      style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('v2.2.1 · WANYU', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
