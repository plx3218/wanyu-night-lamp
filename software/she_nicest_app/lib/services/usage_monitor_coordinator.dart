import 'dart:async';

import 'android_usage_service.dart';
import 'continuous_usage_engine.dart';
import 'monitor_schedule_service.dart';

abstract interface class UsageMonitorDataSource {
  Future<AndroidUsageQueryResult> querySegments(Duration window);
}

class AndroidUsageDataSource implements UsageMonitorDataSource {
  AndroidUsageDataSource(this.client);

  final AndroidUsageClient client;

  @override
  Future<AndroidUsageQueryResult> querySegments(Duration window) =>
      client.querySegments(window);
}

enum UsageMonitorEventType {
  started,
  snapshot,
  permissionRequired,
  unavailable,
  stopped,
}

class UsageMonitorEvent {
  const UsageMonitorEvent({
    required this.type,
    required this.occurredAt,
    this.schedule,
    this.snapshot,
    this.errorCode,
  });

  final UsageMonitorEventType type;
  final DateTime occurredAt;
  final MonitorSchedule? schedule;
  final UsageSnapshot? snapshot;
  final String? errorCode;
}

class UsageMonitorCoordinator {
  UsageMonitorCoordinator({
    required UsageMonitorDataSource source,
    ContinuousUsageEngine? engine,
    DateTime Function()? now,
    this.pollInterval = const Duration(minutes: 1),
  })  : _source = source,
        _engine = engine ?? ContinuousUsageEngine(),
        _now = now ?? DateTime.now;

  final UsageMonitorDataSource _source;
  final ContinuousUsageEngine _engine;
  final DateTime Function() _now;
  final Duration pollInterval;
  final StreamController<UsageMonitorEvent> _events =
      StreamController<UsageMonitorEvent>.broadcast(sync: true);
  Timer? _timer;
  MonitorSchedule? _currentSchedule;
  bool _running = false;

  Stream<UsageMonitorEvent> get events => _events.stream;
  MonitorSchedule? get currentSchedule => _currentSchedule;
  bool get isRunning => _running;

  Future<void> start(MonitorSchedule schedule) async {
    if (_running) return;
    _currentSchedule = schedule.lock(_now());
    _running = true;
    _events.add(
      UsageMonitorEvent(
        type: UsageMonitorEventType.started,
        occurredAt: _now(),
        schedule: _currentSchedule,
      ),
    );
    await refresh();
    _timer = Timer.periodic(pollInterval, (_) => refresh());
  }

  Future<void> refresh() async {
    if (!_running || _currentSchedule == null) return;
    final schedule = _currentSchedule!;
    final now = _now();
    if (now.isBefore(schedule.startAt)) return;

    final windowEnd = now.isBefore(schedule.targetBedtime)
        ? now
        : schedule.targetBedtime;
    final result = await _source.querySegments(
      windowEnd.difference(schedule.startAt),
    );
    if (!result.hasAccess || result.errorCode == 'usage_access_required') {
      _events.add(
        UsageMonitorEvent(
          type: UsageMonitorEventType.permissionRequired,
          occurredAt: now,
          schedule: schedule,
          errorCode: result.errorCode ?? 'usage_access_required',
        ),
      );
      return;
    }
    if (!result.isAvailable) {
      _events.add(
        UsageMonitorEvent(
          type: UsageMonitorEventType.unavailable,
          occurredAt: now,
          schedule: schedule,
          errorCode: result.errorCode ?? 'usage_monitor_unavailable',
        ),
      );
      return;
    }

    final snapshot = _engine.evaluate(
      result.segments,
      schedule.startAt,
      windowEnd,
    );
    _events.add(
      UsageMonitorEvent(
        type: UsageMonitorEventType.snapshot,
        occurredAt: now,
        schedule: schedule,
        snapshot: snapshot,
      ),
    );
  }

  Future<void> stop() async {
    if (!_running) return;
    _timer?.cancel();
    _timer = null;
    _running = false;
    _events.add(
      UsageMonitorEvent(
        type: UsageMonitorEventType.stopped,
        occurredAt: _now(),
        schedule: _currentSchedule,
      ),
    );
  }

  void dispose() {
    _timer?.cancel();
    _events.close();
  }
}
