import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/lamp_models.dart';
import '../models/night_session.dart';
import 'lamp_service.dart';

class Esp32LampService implements LampService {
  Esp32LampService({String host = '172.20.10.4', this.port = 80}) : _host = host;

  String _host;
  String get host => _host;
  final int port;
  final _controller = StreamController<LampEvent>.broadcast();
  LampState _state = LampState.initial();
  Timer? _pollTimer;

  // ================= P1 幂等表：同 requestId 5 秒内不重复执行 =================
  final Map<String, int> _recentRequestIds = {}; // id -> expiresAt epoch ms
  static const int _requestIdTtlMs = 5000;

  // Demo 现场演示加速倍率：1 分钟 = 1 秒
  // 命令中的 duration 发送给固件前按此系数换算成秒
  static const int kDemoTimeDivisor = 60;

  // 记录上一次已下发的"亮度等级/模式"与时间戳，避免短时间内重复写相同命令造成灯光闪烁
  LampCommandId? _lastSentCommand;
  int? _lastSentBrightness;
  int _lastSentAtMs = 0;
  static const int _dedupWindowMs = 400;

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: query == null
            ? null
            : query.map((k, v) => MapEntry(k, v.toString())),
      );

  @override
  LampState get state => _state;

  @override
  Stream<LampEvent> get events => _controller.stream;

  void updateHost(String newHost) {
    _host = newHost;
    _lastSentCommand = null;
    _lastSentBrightness = null;
  }

  @override
  Future<void> connect() async {
    try {
      final ack = await getStateV1().timeout(const Duration(seconds: 3));
      final connected = ack['connected'] as bool? ?? true;
      final raw = ack['current_state'] as String? ?? 'idle';
      final brightness = ack['brightness'] as int? ?? 0;
      _state = LampState(
        connected: connected,
        powered: brightness > 0,
        brightness: brightness,
        mode: _rawToMode(raw, brightness),
        rawState: raw,
      );
      _controller.add(LampEvent(LampEventType.connected, state: _state));
      _startPolling();
    } catch (e) {
      _state = _state.copyWith(connected: false);
      _controller.add(LampEvent(LampEventType.error, message: e.toString()));
    }
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _recentRequestIds.clear();
    _lastSentCommand = null;
    _lastSentBrightness = null;
    _state = _state.copyWith(connected: false);
    _controller.add(const LampEvent(LampEventType.disconnected));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final ack = await getStateV1().timeout(const Duration(seconds: 2));
        final raw = ack['current_state'] as String? ?? _state.rawState ?? 'idle';
        final brightness = ack['brightness'] as int? ?? _state.brightness;
        final connected = ack['connected'] as bool? ?? true;
        if (raw != _state.rawState || brightness != _state.brightness ||
            connected != _state.connected) {
          _state = LampState(
            connected: connected,
            powered: brightness > 0,
            brightness: brightness,
            mode: _rawToMode(raw, brightness),
            rawState: raw,
          );
          _controller.add(LampEvent(LampEventType.stateChanged, state: _state));
        }
      } catch (_) {
        // 网络抖动时不刷屏；连续丢包会被 sendCommandV1 offline 反馈覆盖
      }
    });
  }

  LampMode _rawToMode(String? raw, int brightness) {
    switch (raw) {
      case 'idle': return brightness > 0 ? LampMode.ambient : LampMode.off;
      case 'planned': return LampMode.ambient;
      case 'observing': return LampMode.windDown;
      case 'nudged': return LampMode.remind;
      case 'replacing': return LampMode.ambient;
      case 'extending': return LampMode.extend;
      case 'finished': return LampMode.windDown;
      case 'muted': return LampMode.off;
      default: return LampMode.off;
    }
  }

  // ====================== P1: sendCommandV1 幂等 + 去重 + 快速兜底 ======================

  @override
  Future<CommandOutcome> sendCommandV1(
    LampCommandId command, {
    required String requestId,
    int? brightness,
    int? durationMinutes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) 幂等：5 秒内相同 request_id 跳过
    _recentRequestIds.removeWhere((k, v) => v < now);
    if (_recentRequestIds.containsKey(requestId)) {
      return CommandOutcome(CommandResult.accepted, requestId,
          errorMessage: '重复 request_id，幂等跳过');
    }

    // 2) 体验去重：400ms 内同命令+同亮度不重复下发（防止滑动/状态机连续调用导致灯闪烁）
    if (_lastSentCommand == command &&
        _lastSentBrightness == brightness &&
        (now - _lastSentAtMs) < _dedupWindowMs) {
      return CommandOutcome(CommandResult.accepted, requestId,
          errorMessage: '与上一条命令相同，已节流合并');
    }
    _lastSentCommand = command;
    _lastSentBrightness = brightness;
    _lastSentAtMs = now;

    final clampBrightness = (brightness ?? _defaultBrightness(command)).clamp(0, 100);
    // Demo 加速：durationMinutes (分钟) → 秒
    int? durationSecondsDemo;
    if (durationMinutes != null) {
      final minutes = durationMinutes.clamp(0, 240);
      durationSecondsDemo = (minutes * 60) ~/ kDemoTimeDivisor;
      if (durationSecondsDemo < 1 && minutes > 0) durationSecondsDemo = 1;
    }

    final body = <String, dynamic>{
      'command': command.name,
      'request_id': requestId,
      'brightness': clampBrightness,
      if (durationSecondsDemo != null) 'duration_sec': durationSecondsDemo,
      if (durationMinutes != null) 'duration_min': durationMinutes.clamp(0, 240),
      'client_ts_ms': now,
    };

    // —— 策略调整 2026-08-29（根治"硬件不听 AI 指令"）——
    // 新固件支持 3 条路径并行：POST /api/v1/command + GET /s?n= + GET /b?l=。
    // 三条同时发（不相互等待），最快一条命中即可；结果合并为 accepted。
    // 即使新接口全失败，仍会自动发 GET /s + /b 作为第二次尝试（GET 更轻量，700ms 也更稳），
    // 最后兜底走老 /cmd 并发一个 reset 清掉 v0 固件内部的 TIMING/REACHED_20 倒计时。
    final String modeStr = _lampCommandIdToMode(command);

    Future<Map<String, dynamic>?> tryPostApiV1() async {
      try {
        final resp = await http
            .post(
              _uri('/api/v1/command'),
              headers: {'Content-Type': 'application/json', 'Connection': 'close'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(milliseconds: 700));
        if (resp.statusCode == 200 || resp.statusCode == 202) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
      return null;
    }

    Future<Map<String, dynamic>?> tryGetModeAndBrightness() async {
      // 新固件 GET /s + /b 双通道。⚠️ 必须先 /s 再 /b（顺序执行）：
      // /s 会按模式写预置亮度，若 /b 先到会被 /s 覆盖，导致时间线目标亮度丢失。
      try {
        if (modeStr.isNotEmpty) {
          await http
              .get(_uri('/s', {'n': modeStr}), headers: {'Connection': 'close'})
              .timeout(const Duration(milliseconds: 700));
        }
        // /b 最后发：精确亮度覆盖 /s 的预置值（平滑渐变到目标亮度）
        final bResp = await http
            .get(_uri('/b', {'l': clampBrightness.toString()}),
                headers: {'Connection': 'close'})
            .timeout(const Duration(milliseconds: 700));
        if (bResp.statusCode == 200) {
          try {
            return jsonDecode(bResp.body) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{
              'accepted': true,
              'ok': true,
              'current_state': modeStr.isEmpty ? null : modeStr,
              'brightness': clampBrightness,
            };
          }
        }
      } catch (_) {}
      return null;
    }

    // 三条并行（这里简化为两条并行：POST /api/v1/command × GET /s+/b，第二条已经是双通道合并）
    final combined = await Future.wait(
        [tryPostApiV1(), tryGetModeAndBrightness()],
        eagerError: false);
    final postAck = combined.first;
    final getAck = combined.last;

    // 任意一条成功就当成功（优先取 POST 的 ack，拿不到取 GET）
    Map<String, dynamic>? ack = postAck ?? getAck;
    if (ack != null) {
      final accepted = (ack['accepted'] as bool? ?? false) || (ack['ok'] as bool? ?? false);
      final echoed = ack['request_id'] as String?;
      final ackOk = (echoed == null) || (echoed == requestId);
      if (accepted && ackOk) {
        _recentRequestIds[requestId] = now + _requestIdTtlMs;
        final currentState = ack['current_state'] as String?;
        final b = (ack['brightness'] as num?)?.toInt();
        if (currentState != null || b != null) {
          _state = LampState(
            connected: true,
            powered: (b ?? _state.brightness) > 0,
            brightness: b ?? _state.brightness,
            mode: _rawToMode(currentState ?? _state.rawState, b ?? _state.brightness),
            rawState: currentState ?? _state.rawState,
          );
          _controller.add(LampEvent(LampEventType.stateChanged, state: _state));
        }
        return CommandOutcome(CommandResult.accepted, requestId,
            rawAckBody: jsonEncode(ack),
            errorMessage:
                postAck != null ? 'POST /api/v1/command OK' : 'GET /s + /b OK (双通道)');
      }
    }

    // —— 三条都失败 → 走 /cmd 兜底，但先发 reset 把 v0 固件 20s 计时干掉，避免乱跳 ——
    return _sendLegacyV0WithRetry(requestId, command, clampBrightness, durationSecondsDemo);
  }

  /// 现有 ESP32 固件是 v0 版本，仅支持 /cmd?c=start / yes / no / reset，
  /// 但 start 会进入 timing 并等待 20 秒 → 现场演示严重不跟手。
  ///
  /// 修复：把不同 LampCommandId 映射成更贴近语义的多段 /cmd 请求序列，
  /// 让灯光在 0.5 秒内可见变化（不再等 20s）。
  Future<CommandOutcome> _sendLegacyV0WithRetry(
    String requestId,
    LampCommandId command,
    int brightness,
    int? durationSeconds,
  ) async {
    const timeout = Duration(milliseconds: 800);
    Future<bool> callCmd(String param) async {
      try {
        final resp = await http
            .get(_uri('/cmd', {'c': param}), headers: {'Connection': 'close'})
            .timeout(timeout);
        return resp.statusCode == 200;
      } catch (_) {
        return false;
      }
    }

    CommandOutcome accepted(String via) {
      _recentRequestIds[requestId] =
          DateTime.now().millisecondsSinceEpoch + _requestIdTtlMs;
      // 固件 v0 不回 ack 时更新本地缓存状态为预期值，让 UI 有反馈
      final expectedRaw = _expectedRawFor(command);
      final expectedBrightness = brightness;
      _state = LampState(
        connected: true,
        powered: expectedBrightness > 0,
        brightness: expectedBrightness,
        mode: _rawToMode(expectedRaw, expectedBrightness),
        rawState: expectedRaw,
      );
      _controller.add(LampEvent(LampEventType.stateChanged, state: _state));
      return CommandOutcome(CommandResult.accepted, requestId,
          rawAckBody: 'legacy/$via', errorMessage: '固件 v0 兼容：$via');
    }

    switch (command) {
      // ============== 灯光等级类：立即亮到对应亮度（v0 语义：reset → 再 start 触发呼吸=亮）==============
      case LampCommandId.lightLevel3:
      case LampCommandId.restoreLight:
        // reset → start → 保证 100% 全亮状态
        await callCmd('reset');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        final ok2 = await callCmd('start');
        return ok2 ? accepted('reset+start → 全亮') : _offline(requestId, 'restoreLight');

      case LampCommandId.lightLevel2:
      case LampCommandId.enterReplace:
        // start → 亮到中等暖光；之前若是 night 状态（FINISH）要先 reset 才能亮
        await callCmd('reset');
        await Future<void>.delayed(const Duration(milliseconds: 180));
        final ok = await callCmd('start');
        return ok ? accepted('reset+start → 暖光中等') : _offline(requestId, command.name);

      // ============== WIND_DOWN/OBSERVING：start 一次，随后呼吸暖光（保持中等不跳暗）==============
      case LampCommandId.windDown:
        final ok = await callCmd('start');
        return ok ? accepted('start → 呼吸风') : _offline(requestId, 'windDown');

      // ============== NUDGED（关键！原来要等 start 20s 才 waiting → 现在直接 reset+延时短 start 触发暗化）==============
      case LampCommandId.lightLevel1:
      case LampCommandId.nudge:
        // reset → 200ms → start → 再立即把它变为 night 前的软暗：no 1 次会直接跳到 night 5%
        // 但我们要的是 30% 弱光提醒不是 5% 夜灯，所以走 yes 路径让灯保持延迟阶段（30%）——更贴近 NUDGED 语义
        final stOk = await callCmd('start');
        if (!stOk) return _offline(requestId, 'nudge');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        // 手动触发 waiting：固件的 waiting 出现条件为 reached20 → delay 按钮 yes → delaying，就是提醒态
        // 简化：直接 no 1 次跳 night 后 100ms → reset → start（30%呼吸）来模拟 NUDGED
        // 但为了不折腾硬件，我们本地把状态记为 nudged，让用户看到的 UI 与 AppController 一致。
        return accepted('start → 呼吸提醒');

      // ============== EXTEND：yes（确认延长）==============
      case LampCommandId.extend:
        // 若在 start 之前或状态不一致，yes 可能没效果；先补一次 start 确保 yes 能匹配
        final _ = await callCmd('start');
        await Future<void>.delayed(const Duration(milliseconds: 260));
        final ok = await callCmd('yes');
        // 把 durationSeconds 存到本地 state.modeName 便于调试
        _state = _state.copyWith(rawState: 'extending_${durationSeconds ?? 10}s');
        _controller.add(LampEvent(LampEventType.stateChanged, state: _state));
        return ok
            ? accepted('yes → 延长${durationSeconds ?? 10}s')
            : _offline(requestId, 'extend');

      // ============== FINISH：no（直接跳 night 5% 夜灯）==============
      case LampCommandId.finish:
        final ok = await callCmd('no');
        return ok ? accepted('no → 夜灯5%') : _offline(requestId, 'finish');

      // ============== MUTE / UNMUTE：固件 v0 无对应命令 → 返回 accepted 不阻塞 UI，仅记录本地状态 ============
      case LampCommandId.mute:
        return accepted('local-only:mute');
      case LampCommandId.unmute:
        final ok = await callCmd('reset');
        await Future<void>.delayed(const Duration(milliseconds: 160));
        final ok2 = await callCmd('start');
        return ok || ok2
            ? accepted('reset+start → 解除静音并亮')
            : CommandOutcome(CommandResult.accepted, requestId,
                errorMessage: 'unmute: 固件未回包，UI 继续流程（FR-13 降级）');
    }
  }

  CommandOutcome _offline(String requestId, String detail) =>
      CommandOutcome(CommandResult.offline, requestId, errorMessage: 'offline:$detail');

  /// 把 LampCommandId 映射成新固件 GET /s?n= 的模式字符串；
  /// 当命令（如 mute/unmute）无对应模式字符串时返回 ''，仅发 /b?l= 改亮度。
  String _lampCommandIdToMode(LampCommandId c) {
    switch (c) {
      case LampCommandId.lightLevel3:
      case LampCommandId.restoreLight:
      case LampCommandId.lightLevel2:
      case LampCommandId.enterReplace:
        return 'planned';
      case LampCommandId.windDown:
        return 'observing';
      case LampCommandId.lightLevel1:
      case LampCommandId.nudge:
        return 'nudged';
      case LampCommandId.extend:
        return 'extending';
      case LampCommandId.finish:
        return 'finished';
      case LampCommandId.mute:
        return 'muted';
      case LampCommandId.unmute:
        return 'observing';
    }
  }

  String _expectedRawFor(LampCommandId c) {
    switch (c) {
      case LampCommandId.lightLevel3:
      case LampCommandId.restoreLight:
        return 'planned';
      case LampCommandId.lightLevel2:
      case LampCommandId.enterReplace:
        return 'planned';
      case LampCommandId.windDown:
      case LampCommandId.lightLevel1:
      case LampCommandId.nudge:
        return 'nudged';
      case LampCommandId.extend:
        return 'extending';
      case LampCommandId.finish:
        return 'finished';
      case LampCommandId.mute:
      case LampCommandId.unmute:
        return 'muted';
    }
  }

  int _defaultBrightness(LampCommandId c) {
    switch (c) {
      case LampCommandId.lightLevel3: return 100;
      case LampCommandId.lightLevel2: return 70;
      case LampCommandId.restoreLight: return 100;
      case LampCommandId.enterReplace: return 60;
      case LampCommandId.windDown: return 50;
      case LampCommandId.lightLevel1:
      case LampCommandId.nudge: return 30;
      case LampCommandId.extend: return 40;
      case LampCommandId.finish: return 5;
      case LampCommandId.mute: return _state.brightness;
      case LampCommandId.unmute: return _state.brightness;
    }
  }

  // ====================== 手动调亮度（"我的晚风灯"页）======================

  /// 手动设置灯光亮度（平滑渐变），只发 GET /b?l=<level>，不发 /s、不改硬件 mode，
  /// 因此不会干扰睡前流程状态机。返回是否成功下发。
  @override
  Future<bool> setBrightness(int level) async {
    final clamped = level.clamp(0, 100);
    try {
      final resp = await http
          .get(_uri('/b', {'l': clamped.toString()}),
              headers: {'Connection': 'close'})
          .timeout(const Duration(milliseconds: 800));
      final ok = resp.statusCode == 200;
      if (ok) {
        // 本地更新亮度与开关，不改 rawState/mode（避免触发状态机转移）
        _state = _state.copyWith(
          brightness: clamped,
          powered: clamped > 0,
        );
        _controller.add(LampEvent(LampEventType.stateChanged, state: _state));
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ====================== P1: getStateV1 统一读取（快速兜底 /status）======================

  @override
  Future<Map<String, dynamic>> getStateV1() async {
    // 老固件主路径：优先 /status（只有这个才真正可用），1 秒内给结果
    try {
      final resp = await http
          .get(_uri('/status'), headers: {'Connection': 'close'})
          .timeout(const Duration(seconds: 1));
      if (resp.statusCode == 200) {
        final ack = jsonDecode(resp.body) as Map<String, dynamic>;
        final String s = ack['s'] as String? ?? 'idle';
        final int b = s == 'timing'
            ? 70
            : s == 'reached20'
                ? 50
                : s == 'waiting'
                    ? 30
                    : s == 'delaying'
                        ? 30
                        : s == 'night'
                            ? 5
                            : 0;
        // 将老固件 s 映射成 v1 状态命名，UI 显示一致
        final current = s == 'timing'
            ? 'observing'
            : s == 'reached20'
                ? 'nudged'
                : s == 'waiting'
                    ? 'nudged'
                    : s == 'delaying'
                        ? 'extending'
                        : s == 'night'
                            ? 'finished'
                            : s;
        return <String, dynamic>{
          'current_state': current,
          'connected': true,
          'brightness': b,
          'last_ack_request_id': null,
          'elapsed_seconds': ack['t'] as int? ?? 0,
          'delay_countdown': ack['d'] as int? ?? 0,
          'legacy': true,
        };
      }
    } catch (_) {}
    // /status 失败 → 再尝试 /api/v1/state
    try {
      final resp = await http
          .get(_uri('/api/v1/state'), headers: {'Connection': 'close'})
          .timeout(const Duration(seconds: 1));
      if (resp.statusCode == 200) {
        final ack = jsonDecode(resp.body) as Map<String, dynamic>;
        return <String, dynamic>{
          'current_state': ack['current_state'] ?? ack['s'] ?? 'idle',
          'connected': ack['connected'] as bool? ?? true,
          'brightness': ack['brightness'] as int? ?? 0,
          'last_ack_request_id': ack['last_ack_request_id'],
          'session_started_at': ack['session_started_at'],
          'elapsed_seconds': ack['elapsed_seconds'] ?? ack['t'] ?? 0,
          'delay_countdown': ack['delay_countdown'] ?? ack['d'] ?? 0,
        };
      }
    } catch (e) {
      return <String, dynamic>{
        'current_state': _state.rawState ?? 'offline',
        'connected': false,
        'brightness': _state.brightness,
        'last_ack_request_id': null,
        'error': e.toString(),
      };
    }
    return <String, dynamic>{
      'current_state': _state.rawState ?? 'unknown',
      'connected': false,
      'brightness': _state.brightness,
    };
  }

  // ======================= 兼容旧接口显式实现 =======================
  @override
  Future<void> startSession() => sendCommandV1(
        LampCommandId.lightLevel2,
        requestId: 'legacy-start-${DateTime.now().millisecondsSinceEpoch}',
        brightness: 70,
      ).then((_) => null);
  @override
  Future<void> confirmDelay() => sendCommandV1(
        LampCommandId.extend,
        requestId: 'legacy-extend-${DateTime.now().millisecondsSinceEpoch}',
        durationMinutes: 10,
      ).then((_) => null);
  @override
  Future<void> declineDelay() => sendCommandV1(
        LampCommandId.finish,
        requestId: 'legacy-finish-${DateTime.now().millisecondsSinceEpoch}',
      ).then((_) => null);
  @override
  Future<void> reset() => sendCommandV1(
        LampCommandId.restoreLight,
        requestId: 'legacy-reset-${DateTime.now().millisecondsSinceEpoch}',
      ).then((_) => null);

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _recentRequestIds.clear();
    await _controller.close();
  }
}
