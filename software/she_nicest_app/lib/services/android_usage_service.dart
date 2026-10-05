import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_usage_segment.dart';

class AndroidUsageEntry {
  const AndroidUsageEntry({required this.packageName, required this.duration});

  final String packageName;
  final Duration duration;
}

class AndroidUsageQueryResult {
  const AndroidUsageQueryResult({
    required this.hasAccess,
    required this.segments,
    this.sampledAt,
    this.errorCode,
  });

  final bool hasAccess;
  final List<AppUsageSegment> segments;
  final DateTime? sampledAt;
  final String? errorCode;

  bool get isAvailable => hasAccess && errorCode == null;
}

class AndroidUsageClient {
  AndroidUsageClient({MethodChannel? channel, bool? supported})
      : _channel = channel ??
            const MethodChannel(AndroidUsageService.channelName),
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _supported;

  bool get isSupported => _supported;

  Future<bool> hasAccess() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  Future<void> openAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<List<AndroidUsageEntry>> queryLast(Duration window) async {
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

  Future<AndroidUsageQueryResult> querySegments(Duration window) async {
    if (!isSupported) {
      return const AndroidUsageQueryResult(
        hasAccess: false,
        segments: <AppUsageSegment>[],
        errorCode: 'unsupported_platform',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'queryUsageSegments',
        <String, Object>{'sinceMs': now - window.inMilliseconds},
      );
      final payload = Map<Object?, Object?>.from(raw as Map);
      final hasAccess = payload['permissionGranted'] as bool? ?? false;
      final errorCode = payload['errorCode'] as String?;
      final sampledAtMs = (payload['sampledAtMs'] as num?)?.toInt();
      final rawSegments = payload['segments'] as List<dynamic>? ?? const [];

      return AndroidUsageQueryResult(
        hasAccess: hasAccess,
        errorCode: hasAccess ? errorCode : errorCode ?? 'usage_access_required',
        sampledAt: sampledAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(sampledAtMs),
        segments: hasAccess ? AndroidUsageService.parseSegments(rawSegments) : const [],
      );
    } on PlatformException catch (error) {
      return AndroidUsageQueryResult(
        hasAccess: false,
        segments: const [],
        errorCode: error.code,
      );
    }
  }
}

/// Android App 使用情况访问能力；原始片段只在本机处理，不上传浏览内容。
class AndroidUsageService {
  static const channelName = 'com.shenicest.app/usage_monitor_lab';
  static final AndroidUsageClient _defaultClient = AndroidUsageClient();

  static bool get isSupported => _defaultClient.isSupported;

  static Future<bool> hasAccess() => _defaultClient.hasAccess();

  static Future<void> openAccessSettings() =>
      _defaultClient.openAccessSettings();

  static Future<List<AndroidUsageEntry>> queryLast(Duration window) =>
      _defaultClient.queryLast(window);

  static Future<AndroidUsageQueryResult> querySegments(Duration window) =>
      _defaultClient.querySegments(window);

  static List<AppUsageSegment> parseSegments(Iterable<dynamic> raw) {
    return raw.map((item) {
      final map = Map<Object?, Object?>.from(item as Map);
      return AppUsageSegment(
        packageName: map['packageName'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['startedAtMs'] as num).toInt(),
        ),
        endedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['endedAtMs'] as num).toInt(),
        ),
      );
    }).toList();
  }
}
