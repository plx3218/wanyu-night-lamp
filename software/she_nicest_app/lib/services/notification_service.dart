import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static int _id = 100;

  /// 通知点击回调（由 main.dart 设置：点击通知 → 跳转 session 页面 → 弹 pending 弹窗）
  static void Function(String? payload)? onNotificationTap;

  /// 冷启动标记：App 被系统杀死后用户点通知重新打开
  static bool launchedFromNotification = false;
  static String? launchPayload;

  // 通知渠道 ID（用新 ID 避免旧渠道 importance 被用户在系统设置里降低后无法恢复）
  static const _channelId = 'timeline_stage_v2';

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // 冷启动检查：App 从通知启动时拿到 payload，供 main.dart 跳转
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      launchedFromNotification = true;
      launchPayload = launchDetails.notificationResponse?.payload;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    onNotificationTap?.call(response.payload);
  }

  /// 阶段性推送通知（类似微信横幅通知）
  /// Importance.max + Priority.max → 触发 heads-up 横幅
  /// 用户点击通知 → 打开 App → 自动跳转 session 页面 → 弹 pending 弹窗
  ///
  /// [id] 指定通知 id，相同 id 会更新已存在的通知（用于"先发降级、AI 成功后更新"）。
  /// 不传则自增新 id（新建通知）。
  static Future<void> showStage({required String title, required String body, int? id}) async {
    const android = AndroidNotificationDetails(
      _channelId,
      '晚屿 · 睡前提醒',
      channelDescription: '时间线各阶段推送（横幅通知）',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: true,
      showWhen: true,
      autoCancel: true,
      ticker: '晚屿',
      fullScreenIntent: false,
      subText: '晚屿',
      icon: '@mipmap/ic_launcher',
    );
    const platform = NotificationDetails(android: android);
    final notifyId = id ?? _id++;
    debugPrint('[NotificationService] showStage: id=$notifyId, title=$title, body=$body');
    await _plugin.show(notifyId, title, body, platform, payload: 'navigate_session');
    debugPrint('[NotificationService] showStage sent: id=$notifyId');
  }

  static Future<void> cancel() => _plugin.cancel(0);
  static Future<void> cancelAll() => _plugin.cancelAll();
}
