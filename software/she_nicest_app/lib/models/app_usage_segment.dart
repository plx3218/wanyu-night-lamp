class AppUsageSegment {
  AppUsageSegment({
    required this.packageName,
    required this.startedAt,
    required this.endedAt,
  }) : assert(!endedAt.isBefore(startedAt));

  final String packageName;
  final DateTime startedAt;
  final DateTime endedAt;

  Duration get duration => endedAt.difference(startedAt);
}
