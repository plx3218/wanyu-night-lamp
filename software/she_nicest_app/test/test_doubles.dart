import 'dart:async';

import 'package:she_nicest_app/models/app_usage_segment.dart';
import 'package:she_nicest_app/models/lamp_models.dart';
import 'package:she_nicest_app/models/night_session.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/services/ai_service.dart';
import 'package:she_nicest_app/services/lamp_service.dart';
import 'package:she_nicest_app/services/usage_monitor_coordinator.dart';
import 'package:she_nicest_app/services/android_usage_service.dart';
import 'package:she_nicest_app/services/fallback_plan_service.dart';

class FakeLampService extends LampService {
  FakeLampService() : _events = StreamController<LampEvent>.broadcast();

  final StreamController<LampEvent> _events;
  final LampState _state = LampState.initial();
  final List<LampCommandId> commands = <LampCommandId>[];

  @override
  LampState get state => _state;

  @override
  Stream<LampEvent> get events => _events.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async => _events.close();

  @override
  Future<CommandOutcome> sendCommandV1(
    LampCommandId command, {
    required String requestId,
    int? brightness,
    int? durationMinutes,
  }) async {
    commands.add(command);
    return CommandOutcome(CommandResult.accepted, requestId);
  }

  @override
  Future<Map<String, dynamic>> getStateV1() async => <String, dynamic>{};
}

class FakeAiService extends AiService {
  FakeAiService() : super(serverUrl: 'http://fake.invalid');

  @override
  Future<TonightPlan> generatePlan({
    required String prompt,
    required String bedtime,
    required String wakeTime,
    Object? scenario,
    String? replacementActivity,
    DateTime? now,
  }) async =>
      FallbackPlanService.create(
        now: now ?? DateTime(2026, 10, 5, 20),
        bedtime: bedtime,
        wakeTime: wakeTime,
        scenario: scenario ?? BedtimeScenario.normalWorkday,
        replacementActivity: replacementActivity,
      );
}

class FakeUsageDataSource implements UsageMonitorDataSource {
  FakeUsageDataSource(this.result);

  AndroidUsageQueryResult result;

  @override
  Future<AndroidUsageQueryResult> querySegments(Duration window) async => result;
}

AppUsageSegment segment(String packageName, DateTime start, DateTime end) =>
    AppUsageSegment(packageName: packageName, startedAt: start, endedAt: end);
