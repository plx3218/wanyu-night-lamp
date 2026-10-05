import '../models/app_usage_segment.dart';
import 'usage_category_policy.dart';

class UsageSnapshot {
  const UsageSnapshot({
    required this.entertainmentMinutes,
    required this.activeCategory,
    required this.continuousMinutes,
    required this.thresholdReached,
    required this.lastPhoneActivityAt,
  });

  final int entertainmentMinutes;
  final AppCategory? activeCategory;
  final int continuousMinutes;
  final bool thresholdReached;
  final DateTime? lastPhoneActivityAt;
}

class ContinuousUsageEngine {
  ContinuousUsageEngine({UsageCategoryPolicy? policy})
      : policy = policy ?? const UsageCategoryPolicy();

  static const continuousThreshold = Duration(minutes: 20);
  static const allowedCategoryGap = Duration(seconds: 60);

  final UsageCategoryPolicy policy;

  UsageSnapshot evaluate(
    List<AppUsageSegment> segments,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    if (!windowEnd.isAfter(windowStart)) {
      return const UsageSnapshot(
        entertainmentMinutes: 0,
        activeCategory: null,
        continuousMinutes: 0,
        thresholdReached: false,
        lastPhoneActivityAt: null,
      );
    }

    final clipped = <_CategorizedSegment>[];
    for (final segment in segments) {
      final startedAt = _laterOf(segment.startedAt, windowStart);
      final endedAt = _earlierOf(segment.endedAt, windowEnd);
      if (!endedAt.isAfter(startedAt)) continue;
      clipped.add(
        _CategorizedSegment(
          startedAt: startedAt,
          endedAt: endedAt,
          category: policy.categoryFor(segment.packageName),
        ),
      );
    }
    clipped.sort((a, b) => a.startedAt.compareTo(b.startedAt));

    var entertainmentSeconds = 0;
    AppCategory? activeCategory;
    DateTime? sequenceStartedAt;
    DateTime? sequenceEndedAt;
    DateTime? lastPhoneActivityAt;

    for (final segment in clipped) {
      final durationSeconds = segment.endedAt.difference(segment.startedAt).inSeconds;
      if (_countsAsEntertainment(segment.category)) {
        entertainmentSeconds += durationSeconds;
      }

      final sameCategory = activeCategory == segment.category;
      final gap = sequenceEndedAt == null
          ? null
          : segment.startedAt.difference(sequenceEndedAt);
      final previousSequenceEnd = sequenceEndedAt;

      if (previousSequenceEnd != null &&
          sameCategory &&
          gap != null &&
          gap <= allowedCategoryGap) {
        sequenceEndedAt = _laterOf(previousSequenceEnd, segment.endedAt);
      } else {
        activeCategory = segment.category;
        sequenceStartedAt = segment.startedAt;
        sequenceEndedAt = segment.endedAt;
      }
      final previousActivityAt = lastPhoneActivityAt;
      lastPhoneActivityAt = previousActivityAt == null
          ? segment.endedAt
          : _laterOf(previousActivityAt, segment.endedAt);
    }

    final started = sequenceStartedAt;
    final ended = sequenceEndedAt;
    final continuousDuration = started == null || ended == null
        ? Duration.zero
        : ended.difference(started);
    final continuousMinutes = continuousDuration.inMinutes;

    return UsageSnapshot(
      entertainmentMinutes: entertainmentSeconds ~/ 60,
      activeCategory: activeCategory,
      continuousMinutes: continuousMinutes,
      thresholdReached: _countsAsEntertainment(activeCategory) &&
          continuousDuration >= continuousThreshold,
      lastPhoneActivityAt: lastPhoneActivityAt,
    );
  }

  bool _countsAsEntertainment(AppCategory? category) {
    return category == AppCategory.social ||
        category == AppCategory.entertainment ||
        category == AppCategory.gaming;
  }

  DateTime _laterOf(DateTime first, DateTime second) {
    return first.isAfter(second) ? first : second;
  }

  DateTime _earlierOf(DateTime first, DateTime second) {
    return first.isBefore(second) ? first : second;
  }
}

class _CategorizedSegment {
  const _CategorizedSegment({
    required this.startedAt,
    required this.endedAt,
    required this.category,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final AppCategory category;
}
