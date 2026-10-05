import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/app_controller.dart';
import 'package:she_nicest_app/models/lamp_models.dart';
import 'package:she_nicest_app/models/night_session.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/screens/home_screen.dart';
import 'package:she_nicest_app/screens/plan_screen.dart';
import 'package:she_nicest_app/services/ai_service.dart';
import 'package:she_nicest_app/services/lamp_service.dart';
import 'package:she_nicest_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drawer fits a phone viewport without vertical overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: HomeScreen(controller: controller),
    ));
    await tester.tap(find.byTooltip('打开菜单'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('plan step title and badge fit without horizontal overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final controller = _controller();
    addTearDown(controller.dispose);
    controller.setTonightPlan(const TonightPlan(
      wakeTime: '07:30',
      recommendedBedtime: '23:00',
      windDownTime: '22:40',
      reminderTime: '22:50',
      steps: [
        PlanStepItem(time: '22:40', action: '放下手边的事，靠一靠'),
        PlanStepItem(time: '22:50', action: '听点轻音乐，什么都不想'),
        PlanStepItem(time: '23:00', action: '准备结束今天'),
      ],
      replacementActivity: '音乐',
      extensionMinutes: 10,
      assumptions: [],
      reply: '今晚可以在 23:00 左右准备入睡。',
    ));

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PlanScreen(controller: controller),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

AppController _controller() =>
    AppController(_FakeLampService(), AiService(serverUrl: 'http://localhost'));

class _FakeLampService extends LampService {
  final StreamController<LampEvent> _events =
      StreamController<LampEvent>.broadcast();
  LampState _state = LampState.initial();

  @override
  LampState get state => _state;

  @override
  Stream<LampEvent> get events => _events.stream;

  @override
  Future<void> connect() async {
    _state = _state.copyWith(connected: true);
  }

  @override
  Future<void> disconnect() async {
    _state = _state.copyWith(connected: false);
  }

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<Map<String, dynamic>> getStateV1() async => {
        'connected': _state.connected,
        'brightness': _state.brightness,
      };

  @override
  Future<CommandOutcome> sendCommandV1(
    LampCommandId command, {
    required String requestId,
    int? brightness,
    int? durationMinutes,
  }) async =>
      CommandOutcome(CommandResult.accepted, requestId);
}
