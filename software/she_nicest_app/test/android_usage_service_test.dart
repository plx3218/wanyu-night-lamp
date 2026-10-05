import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/services/android_usage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.shenicest.app/usage_monitor_lab');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns foreground segments and the native sampling timestamp', () async {
    final sampledAt = DateTime(2026, 10, 5, 23).millisecondsSinceEpoch;
    final startedAt = sampledAt - const Duration(minutes: 20).inMilliseconds;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'queryUsageSegments');
      expect(call.arguments, containsPair('sinceMs', isA<int>()));
      return <String, Object?>{
        'permissionGranted': true,
        'sampledAtMs': sampledAt,
        'segments': <Object?>[
          <String, Object?>{
            'packageName': 'tv.danmaku.bili',
            'startedAtMs': startedAt,
            'endedAtMs': sampledAt,
          },
        ],
      };
    });

    final result = await AndroidUsageClient(
      channel: channel,
      supported: true,
    ).querySegments(const Duration(minutes: 30));

    expect(result.isAvailable, isTrue);
    expect(result.errorCode, isNull);
    expect(result.sampledAt, DateTime.fromMillisecondsSinceEpoch(sampledAt));
    expect(result.segments.single.packageName, 'tv.danmaku.bili');
    expect(result.segments.single.startedAt,
        DateTime.fromMillisecondsSinceEpoch(startedAt));
  });

  test('surfaces usage access denial instead of treating it as empty usage', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'usage_access_required',
        message: 'Usage access is required',
      );
    });

    final result = await AndroidUsageClient(
      channel: channel,
      supported: true,
    ).querySegments(const Duration(minutes: 30));

    expect(result.isAvailable, isFalse);
    expect(result.hasAccess, isFalse);
    expect(result.errorCode, 'usage_access_required');
    expect(result.segments, isEmpty);
  });

  test('keeps permission and settings method names stable', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return call.method == 'hasUsageAccess';
    });
    final client = AndroidUsageClient(channel: channel, supported: true);

    expect(await client.hasAccess(), isTrue);
    await client.openAccessSettings();

    expect(methods, <String>['hasUsageAccess', 'openUsageAccessSettings']);
  });
}
