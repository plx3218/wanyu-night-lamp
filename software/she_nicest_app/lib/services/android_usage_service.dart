import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidUsageEntry {
  const AndroidUsageEntry({required this.packageName, required this.duration});

  final String packageName;
  final Duration duration;
}

/// Android App 使用时长能力实验。
///
/// 只读取系统在本机提供的聚合事件，不上传数据，也不负责后台提醒。
class AndroidUsageService {
  static const _channel = MethodChannel('com.shenicest.app/usage_monitor_lab');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> hasAccess() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  static Future<void> openAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  static Future<List<AndroidUsageEntry>> queryLast(Duration window) async {
    if (!isSupported) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = await _channel.invokeListMethod<dynamic>(
          'queryUsage',
          <String, Object>{'sinceMs': now - window.inMilliseconds},
        ) ??
        const [];
    return raw.map((item) {
      final map = Map<Object?, Object?>.from(item as Map);
      return AndroidUsageEntry(
        packageName: map['packageName'] as String,
        duration: Duration(milliseconds: (map['durationMs'] as num).toInt()),
      );
    }).toList();
  }
}
