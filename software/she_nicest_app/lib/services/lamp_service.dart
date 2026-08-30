import '../models/lamp_models.dart';
import '../models/night_session.dart';

/// 统一的灯光服务抽象。
///
/// P1 状态机新增的能力：
///  - sendCommandV1：参数化命令 + 幂等 request_id + 超时重试（由实现层完成）
///  - getStateV1：查询 current_state + last_ack_request_id
///  - convertLegacy：把老的 startSession/confirmDelay/declineDelay/reset 桥接到新命令
abstract class LampService {
  LampState get state;
  Stream<LampEvent> get events;

  Future<void> connect();
  Future<void> disconnect();
  Future<void> dispose();

  // ============== P1 状态机标准接口（FR-08 11 指令）==============

  /// 参数化命令发送（ESP32 v1 固件会识别）。
  ///
  /// [id] 每个调用方生成唯一 request_id（推荐 uuid v4 格式字符串）；
  /// 实现层需要做：3 秒超时 + 最多 2 次重试 + 幂等检查。
  Future<CommandOutcome> sendCommandV1(
    LampCommandId command, {
    required String requestId,
    int? brightness, // 0-100，仅 LIGHT_LEVEL_* / WIND_DOWN / EXTEND 时使用
    int? durationMinutes, // EXTEND / ENTER_REPLACE / WIND_DOWN 过渡时间
  });

  /// 返回 {current_state, last_ack_request_id, connected, brightness}
  /// 用于 UI 显示"灯光已同步 / 离线"状态和 ack 校验
  Future<Map<String, dynamic>> getStateV1();

  // ============== 兼容旧接口（内部转发到 V1）==============
  Future<void> startSession() => sendCommandV1(
        LampCommandId.lightLevel2,
        requestId: 'legacy-start-${DateTime.now().millisecondsSinceEpoch}',
        brightness: 70,
      ).then((_) => null);
  Future<void> confirmDelay() => sendCommandV1(
        LampCommandId.extend,
        requestId: 'legacy-extend-${DateTime.now().millisecondsSinceEpoch}',
        durationMinutes: 10,
      ).then((_) => null);
  Future<void> declineDelay() => sendCommandV1(
        LampCommandId.finish,
        requestId: 'legacy-finish-${DateTime.now().millisecondsSinceEpoch}',
      ).then((_) => null);
  Future<void> reset() => sendCommandV1(
        LampCommandId.restoreLight,
        requestId: 'legacy-reset-${DateTime.now().millisecondsSinceEpoch}',
      ).then((_) => null);

  /// 手动设置灯光亮度（平滑渐变），仅改亮度不改硬件模式，不干扰睡前流程状态机。
  /// 默认实现返回 false（不支持的实现静默失败，符合"离线无反应"）。
  Future<bool> setBrightness(int level) async => false;
}
