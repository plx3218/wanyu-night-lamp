import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../services/esp32_lamp_service.dart';
import '../theme/app_theme.dart';

class LampScreen extends StatefulWidget {
  const LampScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<LampScreen> createState() => _LampScreenState();
}

class _LampScreenState extends State<LampScreen> {
  late TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    final lamp = widget.controller.lamp;
    _ipController = TextEditingController(
      text: lamp is Esp32LampService ? lamp.host : '172.20.10.4',
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('我的灯')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final state = widget.controller.lampState;
          final lamp = widget.controller.lamp;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 1.35,
                  child: Image.asset('assets/images/pebble-lamp.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(child: Text('晚风灯', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
                  Icon(
                    state.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: state.connected ? AppColors.lake : AppColors.quiet,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                state.connected ? '已连接 · ${state.rawState ?? 'idle'}' : '未连接',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (state.connected && state.elapsedSeconds != null) ...[
                const SizedBox(height: 6),
                Text('累计计时：${state.elapsedSeconds}s', style: const TextStyle(color: AppColors.lake, fontSize: 14)),
              ],
              const SizedBox(height: 24),
              if (lamp is Esp32LampService) ...[
                const Text('设备 IP 地址', style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '如 172.20.10.4',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.lake.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.lake.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.lake, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    lamp.updateHost(_ipController.text.trim());
                    if (state.connected) {
                      lamp.disconnect();
                    } else {
                      lamp.connect();
                    }
                  },
                  child: Text(state.connected ? '断开连接' : '连接晚风灯'),
                ),
              ] else
                FilledButton(
                  onPressed: state.connected ? lamp.disconnect : lamp.connect,
                  child: Text(state.connected ? '断开连接' : '连接模拟灯'),
                ),
              const SizedBox(height: 28),
              const Text('灯光状态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              // 亮度档位按钮（7档）：睡前流程运行中置灰禁用，离线静默无反应
              _BrightnessButtons(
                brightness: state.brightness,
                enabled: widget.controller.canManualControl,
                onSelect: (level) => widget.controller.manualSetBrightness(level),
              ),
              const SizedBox(height: 20),
              // 亮度滑块
              if (widget.controller.canManualControl) ...[
                Row(
                  children: [
                    const Icon(Icons.brightness_low_rounded, size: 20, color: AppColors.textTertiary),
                    Expanded(
                      child: Slider(
                        value: state.brightness.toDouble().clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        activeColor: AppColors.moon,
                        inactiveColor: AppColors.moon.withValues(alpha: 0.2),
                        label: '${state.brightness}%',
                        onChanged: (v) => widget.controller.manualSetBrightness(v.round()),
                      ),
                    ),
                    const Icon(Icons.brightness_high_rounded, size: 20, color: AppColors.textTertiary),
                  ],
                ),
                const SizedBox(height: 8),
                // 让灯暗一些：快捷降低一档
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      final dims = [0, 5, 20, 40, 50, 70, 100];
                      final cur = state.brightness;
                      int target = 0;
                      for (final d in dims) {
                        if (d < cur - 2) target = d;
                      }
                      widget.controller.manualSetBrightness(target);
                    },
                    icon: const Icon(Icons.brightness_3_rounded, size: 18),
                    label: const Text('让灯暗一些'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.moon),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text('睡前流程进行中，暂不可调',
                    style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 亮度档位按钮组（7档：关闭/5%/20%/40%/50%/70%/强亮）
/// - 选中档位高亮（±2 容差匹配当前 brightness）
/// - enabled=false（睡前流程运行中）→ 按钮置灰禁用
/// - 离线时按钮可点但 setBrightness 静默失败 → 无反应
class _BrightnessButtons extends StatelessWidget {
  const _BrightnessButtons({
    required this.brightness,
    required this.enabled,
    required this.onSelect,
  });
  final int brightness;
  final bool enabled;
  final void Function(int level) onSelect;

  static const _levels = [
    (0, '关闭'),
    (5, '5%'),
    (20, '20%'),
    (40, '40%'),
    (50, '50%'),
    (70, '70%'),
    (100, '强亮'),
  ];

  @override
  Widget build(BuildContext context) {
    // 3 列布局：可用宽度 = 屏宽 - 左右 padding(40) - 2 个间距(20)
    final colWidth = (MediaQuery.of(context).size.width - 60) / 3;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _levels.map((item) {
        final (level, label) = item;
        final selected = (brightness - level).abs() <= 2;
        return SizedBox(
          width: colWidth,
          child: OutlinedButton(
            onPressed: enabled ? () => onSelect(level) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: selected ? AppColors.lake : AppColors.textSecondary,
              backgroundColor: selected
                  ? AppColors.lake.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              side: BorderSide(
                color: selected
                    ? AppColors.lake.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
        );
      }).toList(),
    );
  }
}
