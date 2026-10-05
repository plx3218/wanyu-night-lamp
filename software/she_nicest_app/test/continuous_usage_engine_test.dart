import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/app_usage_segment.dart';
import 'package:she_nicest_app/services/android_usage_service.dart';
import 'package:she_nicest_app/services/continuous_usage_engine.dart';
import 'package:she_nicest_app/services/usage_category_policy.dart';

void main() {
  final windowStart = DateTime(2026, 10, 5, 22);

  AppUsageSegment segment(
    String packageName,
    int startSeconds,
    int durationSeconds,
  ) {
    final startedAt = windowStart.add(Duration(seconds: startSeconds));
    return AppUsageSegment(
      packageName: packageName,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSeconds)),
    );
  }

  test('keeps continuous time when apps in the same category switch', () {
    final result = ContinuousUsageEngine().evaluate(
      [
        segment('tv.danmaku.bili', 0, 10 * 60),
        segment('com.ss.android.ugc.aweme', 10 * 60, 10 * 60),
      ],
      windowStart,
      windowStart.add(const Duration(minutes: 30)),
    );

    expect(result.entertainmentMinutes, 20);
    expect(result.activeCategory, AppCategory.entertainment);
    expect(result.continuousMinutes, 20);
    expect(result.thresholdReached, isTrue);
    expect(result.lastPhoneActivityAt, windowStart.add(const Duration(minutes: 20)));
  });

  test('resets continuous time when the category changes', () {
    final result = ContinuousUsageEngine().evaluate(
      [
        segment('com.tencent.mm', 0, 10 * 60),
        segment('tv.danmaku.bili', 10 * 60, 10 * 60),
      ],
      windowStart,
      windowStart.add(const Duration(minutes: 30)),
    );

    expect(result.entertainmentMinutes, 20);
    expect(result.activeCategory, AppCategory.entertainment);
    expect(result.continuousMinutes, 10);
    expect(result.thresholdReached, isFalse);
  });

  test('resets continuous time after leaving a category for more than 60 seconds', () {
    final result = ContinuousUsageEngine().evaluate(
      [
        segment('tv.danmaku.bili', 0, 10 * 60),
        segment('com.ss.android.ugc.aweme', 10 * 60 + 61, 10 * 60),
      ],
      windowStart,
      windowStart.add(const Duration(minutes: 30)),
    );

    expect(result.entertainmentMinutes, 20);
    expect(result.continuousMinutes, 10);
    expect(result.thresholdReached, isFalse);
  });

  test('ignores events outside the monitoring window and triggers at exactly 20 minutes', () {
    final result = ContinuousUsageEngine().evaluate(
      [
        segment('tv.danmaku.bili', -5 * 60, 5 * 60),
        segment('tv.danmaku.bili', 0, 20 * 60),
        segment('tv.danmaku.bili', 30 * 60, 5 * 60),
      ],
      windowStart,
      windowStart.add(const Duration(minutes: 20)),
    );

    expect(result.entertainmentMinutes, 20);
    expect(result.continuousMinutes, 20);
    expect(result.thresholdReached, isTrue);
    expect(result.lastPhoneActivityAt, windowStart.add(const Duration(minutes: 20)));
  });

  test('supports editable mappings and keeps allowlisted apps out of reminders', () {
    const policy = UsageCategoryPolicy(
      overrides: {
        'com.example.white': AppCategory.allowlisted,
        'com.example.video': AppCategory.entertainment,
      },
    );

    expect(policy.categoryFor('com.tencent.mm'), AppCategory.social);
    expect(policy.categoryFor('com.example.video'), AppCategory.entertainment);
    expect(policy.categoryFor('com.example.white'), AppCategory.allowlisted);
    expect(policy.categoryFor('com.example.unknown'), AppCategory.uncategorized);

    final result = ContinuousUsageEngine(policy: policy).evaluate(
      [
        segment('com.example.white', 0, 30 * 60),
      ],
      windowStart,
      windowStart.add(const Duration(minutes: 30)),
    );

    expect(result.entertainmentMinutes, 0);
    expect(result.activeCategory, AppCategory.allowlisted);
    expect(result.continuousMinutes, 30);
    expect(result.thresholdReached, isFalse);
  });

  test('parses native millisecond segments into the shared usage model', () {
    final startedAt = windowStart.add(const Duration(minutes: 3));
    final endedAt = startedAt.add(const Duration(minutes: 2));
    final segments = AndroidUsageService.parseSegments([
      <String, Object>{
        'packageName': 'tv.danmaku.bili',
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'endedAtMs': endedAt.millisecondsSinceEpoch,
      },
    ]);

    expect(segments.single.packageName, 'tv.danmaku.bili');
    expect(segments.single.startedAt, startedAt);
    expect(segments.single.endedAt, endedAt);
  });
}
