import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app_controller.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lamp_screen.dart';
import 'screens/login_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/profile_choice_screen.dart';
import 'screens/register_screen.dart';
import 'screens/session_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/usage_monitor_lab_screen.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/esp32_lamp_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await NotificationService.init();
  await AuthService.load(); // 恢复登录态（决定进首页还是登录页）

  // 初始化前台服务：App 在后台时时间线继续运行
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'timeline_foreground',
      channelName: '睡前时间线',
      channelDescription: '保证 App 在后台时继续运行时间线',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  final controller = AppController(
    Esp32LampService(host: '10.106.12.6', port: 80),
    AiService(serverUrl: 'http://121.40.96.105:8000'),
  );
  controller.syncProfileContext(); // 已登录用户：档案注入 AI 上下文
  // 2026-08-29 修复「看看今晚的安排」按钮消失：plan 持久化到本地，
  // App 重启后恢复，首页/聊天页按钮不再丢失。
  await controller.restoreCachedPlan();
  await controller.syncUsageMonitoring();
  runApp(WanyuApp(controller: controller));
}

/// 全局 Navigator Key，用于从后台恢复时跳转到 session 页面
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

class WanyuApp extends StatefulWidget {
  const WanyuApp({required this.controller, super.key});
  final AppController controller;

  @override
  State<WanyuApp> createState() => _WanyuAppState();
}

class _WanyuAppState extends State<WanyuApp> with WidgetsBindingObserver {
  bool _isResumed = true;
  bool _askDialogShowing = false;
  bool _stageDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 通知点击回调：用户点通知 → 跳转 session 页面 → 检查 pending 弹窗
    NotificationService.onNotificationTap = (_) {
      _navigateToSession();
      // 即使跳转失败，也用 PostFrameCallback 确保检查 pending
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkPendingDialogs());
    };

    // 全局注册时间线回调：不管在哪个页面、前台后台都尝试弹窗
    // controller 已经把弹窗存入 pending 队列，回调负责检查并显示
    widget.controller.onAskExtend = () {
      // 不管前台后台，都用 PostFrameCallback 尝试检查 pending
      // 前台：PostFrameCallback 立即执行 → 检查 pending → 显示弹窗
      // 后台：PostFrameCallback 可能延迟到 App 恢复前台时执行 → 检查 pending → 显示弹窗
      // pending 在 consumePendingAskExtend 之前不会被清空
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkPendingDialogs());
    };
    widget.controller.onShowStageInfo = (title, body) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkPendingDialogs());
    };

    // 冷启动：App 被系统杀死后从通知重新打开 → 跳转 session 页面
    if (NotificationService.launchedFromNotification) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToSession();
        _checkPendingDialogs();
      });
    }
    // App 启动时检查 pending
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingDialogs());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.onNotificationTap = null;
    widget.controller.onAskExtend = null;
    widget.controller.onShowStageInfo = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isResumed) {
      // App 从后台恢复前台：用 PostFrameCallback 确保在 frame 渲染后检查 pending
      // 避免在 context 还没准备好时就检查
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkPendingDialogs());
    }
  }

  /// 登录成功：回首页（'/' 会按登录态重建为 HomeScreen），并把档案注入 AI 上下文
  void _onLoggedIn() {
    widget.controller.syncProfileContext();
    unawaited(widget.controller.syncUsageMonitoring());
    globalNavigatorKey.currentState?.pushNamedAndRemoveUntil('/', (r) => false);
  }

  /// 注册建档成功：进入「直接生成 vs 和 AI 聊聊」选择页
  void _onRegistered() {
    widget.controller.syncProfileContext();
    unawaited(widget.controller.syncUsageMonitoring());
    globalNavigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/profile-choice', (r) => false);
  }

  /// 点击通知（或冷启动从通知打开）→ 跳转 session 页面
  void _navigateToSession() {
    final nav = globalNavigatorKey.currentState;
    if (nav != null) {
      final currentRoute = ModalRoute.of(nav.context)?.settings.name;
      if (currentRoute != '/session') {
        nav.pushNamedAndRemoveUntil('/session', (route) => route.isFirst);
      }
    }
    // 不管跳转是否成功，都用 PostFrameCallback 检查 pending
    // 如果 context 有效就能弹窗，无效就等下一次检查
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingDialogs());
  }

  /// 检查并显示 pending 队列中的弹窗
  void _checkPendingDialogs() {
    // 先检查 context 是否有效，无效就不消费 pending，等下次检查
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;

    // 优先显示延时询问弹窗
    if (widget.controller.hasPendingAskExtend &&
        !_askDialogShowing &&
        !_stageDialogShowing) {
      widget.controller.consumePendingAskExtend(); // 现在才消费
      _showExtendDialogGlobally();
      return;
    }
    // 再显示阶段信息弹窗
    if (widget.controller.hasPendingStageInfo &&
        !_stageDialogShowing &&
        !_askDialogShowing) {
      final pending = widget.controller.consumePendingStageInfo();
      if (pending != null) {
        _showStageInfoDialogGlobally(pending.title, pending.body);
      }
    }
  }

  /// 全局延时询问弹窗
  Future<void> _showExtendDialogGlobally() async {
    final context = globalNavigatorKey.currentContext;
    if (context == null || _askDialogShowing) return;
    _askDialogShowing = true;
    final plan = widget.controller.tonightPlan;
    final extMin = plan?.extensionMinutes ?? 10;
    final extSec = AppController.minutesToDemoSeconds(extMin);
    final extendCount = widget.controller.extensionCount;
    // 根据 extendCount 选择弹窗主文案
    String mainText;
    String lightHint;
    if (extendCount == 0) {
      mainText = '到了入睡提醒时间，需要延时么？';
      lightHint = '当前亮度 50%，选"延时"保持 50%，选"准备入睡"调至 5%';
    } else if (extendCount == 1) {
      mainText = '还需要延时么？';
      lightHint = '当前亮度 5%，选"延时"恢复 50%，选"准备入睡"保持 5%';
    } else if (extendCount == 2) {
      mainText = '你已经用手机时间很长了，快休息吧';
      lightHint = '当前亮度 5%，选"延时"恢复 50%，选"准备入睡"保持 5%';
    } else {
      mainText = '到了入睡提醒时间，需要延时么？';
      lightHint = '';
    }
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B3037),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.nights_stay_rounded, color: Color(0xFFFFC107), size: 26),
            SizedBox(width: 10),
            Text('到了入睡提醒时间',
                style: TextStyle(fontSize: 20, color: Colors.white)),
          ],
        ),
        content: Text(
          '$mainText\n\n$lightHint\n\n需要再延时 $extMin 分钟吗？\n\n（演示加速：延时 $extMin 分钟 ≈ $extSec 秒）',
          style: const TextStyle(color: Colors.white70, height: 1.6),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'no'),
            child:
                const Text('不用了，准备入睡', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107)),
            onPressed: () => Navigator.pop(context, 'yes'),
            child: Text('再延时 $extMin 分钟'),
          ),
        ],
      ),
    );
    _askDialogShowing = false;
    if (choice == 'yes') {
      widget.controller.timelineExtend();
    } else if (choice == 'no') {
      widget.controller.timelineFinish();
    }
    // 检查是否还有 pending
    _checkPendingDialogs();
  }

  /// 全局阶段信息弹窗
  Future<void> _showStageInfoDialogGlobally(String title, String body) async {
    final context = globalNavigatorKey.currentContext;
    if (context == null || _stageDialogShowing) return;
    _stageDialogShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B3037),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.nights_stay_rounded,
                color: Color(0xFFFFC107), size: 26),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(fontSize: 20, color: Colors.white)),
          ],
        ),
        content: Text(
          body,
          style:
              const TextStyle(color: Colors.white70, height: 1.6, fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107)),
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    _stageDialogShowing = false;
    // 检查是否还有 pending
    _checkPendingDialogs();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalNavigatorKey,
      title: '晚屿',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      initialRoute: '/',
      routes: {
        // 登录态决定首页：未登录 → 登录页；已登录 → 主页
        '/': (_) => AuthService.isLoggedIn
            ? HomeScreen(controller: widget.controller)
            : LoginScreen(onLoggedIn: _onLoggedIn),
        '/login': (_) => LoginScreen(onLoggedIn: _onLoggedIn),
        '/register': (_) => RegisterScreen(onRegistered: _onRegistered),
        '/profile-choice': (_) =>
            ProfileChoiceScreen(controller: widget.controller),
        '/settings': (_) => SettingsScreen(controller: widget.controller),
        '/usage-monitor-lab': (_) => const UsageMonitorLabScreen(),
        '/chat': (_) => ChatScreen(controller: widget.controller),
        '/plan': (_) => PlanScreen(controller: widget.controller),
        '/session': (_) => SessionScreen(controller: widget.controller),
        '/lamp': (_) => LampScreen(controller: widget.controller),
      },
    );
  }
}
