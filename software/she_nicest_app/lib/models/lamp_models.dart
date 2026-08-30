enum LampMode { ambient, remind, extend, windDown, off }

enum LampEventType { connected, disconnected, tap, hold, stateChanged, error }

class LampEvent {
  const LampEvent(this.type, {this.message, this.state});
  final LampEventType type;
  final String? message;
  final LampState? state;
}

class LampState {
  const LampState({
    required this.connected,
    required this.powered,
    required this.brightness,
    required this.mode,
    this.elapsedSeconds,
    this.delayCountdown,
    this.rawState,
  });

  factory LampState.initial() => const LampState(
        connected: false,
        powered: false,
        brightness: 0,
        mode: LampMode.off,
        elapsedSeconds: 0,
        delayCountdown: 0,
        rawState: 'idle',
      );

  final bool connected;
  final bool powered;
  final int brightness;
  final LampMode mode;
  final int? elapsedSeconds;
  final int? delayCountdown;
  final String? rawState;

  LampState copyWith({
    bool? connected,
    bool? powered,
    int? brightness,
    LampMode? mode,
    int? elapsedSeconds,
    int? delayCountdown,
    String? rawState,
  }) =>
      LampState(
        connected: connected ?? this.connected,
        powered: powered ?? this.powered,
        brightness: brightness ?? this.brightness,
        mode: mode ?? this.mode,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        delayCountdown: delayCountdown ?? this.delayCountdown,
        rawState: rawState ?? this.rawState,
      );
}
