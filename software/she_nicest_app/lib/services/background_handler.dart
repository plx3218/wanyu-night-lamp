import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(EyeCareTaskHandler());
}

class EyeCareTaskHandler extends TaskHandler {
  String? _baseUrl;
  String? _lastState;

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      final url = data['baseUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        _baseUrl = url;
      }
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'usage_monitor_tick',
      'timestampMs': timestamp.millisecondsSinceEpoch,
    });
    if (_baseUrl == null) return;

    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body);
      final state = json['s'] ?? 'idle';
      final elapsed = json['t'] ?? 0;
      final delayLeft = json['d'] ?? 0;

      FlutterForegroundTask.sendDataToMain({
        'state': state,
        'elapsed': elapsed,
        'delayLeft': delayLeft,
        'shouldStopService': state == 'idle' || state == 'night',
      });

      if (state != _lastState) {
        _lastState = state;
        final (title, text) = _stateToNotification(state, elapsed, delayLeft);
        FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  (String, String) _stateToNotification(String state, int elapsed, int delayLeft) {
    switch (state) {
      case 'idle':
        return ('护眼灯', '待机中');
      case 'timing':
        return ('护眼灯运行中', '环境呼吸 · ${elapsed}s');
      case 'reached20':
        return ('护眼灯运行中', '暖光模式 · ${elapsed}s');
      case 'waiting':
        return ('⏰ 休息提醒', '您已使用 30 秒，该休息了！点击返回 App');
      case 'delaying':
        return ('护眼灯运行中', '延长中 · ${delayLeft}s');
      case 'night':
        return ('护眼灯', '夜灯模式');
      default:
        return ('护眼灯', '运行中');
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _lastState = null;
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
