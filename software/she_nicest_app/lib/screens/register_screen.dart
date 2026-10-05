import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// 注册建档：5 步 —— 账号 → 入睡时间 → 起床时间 → 睡前常刷 App → 替代活动
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.onRegistered, super.key});
  final VoidCallback onRegistered;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _pageCtrl = PageController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  int _step = 0; // 0=账号 1=入睡 2=起床 3=App 4=活动
  String _bedtime = '23:00';
  String _wakeTime = '07:30';
  final Set<String> _apps = {};
  String _activity = '听音乐';
  bool _loading = false;
  String? _error;

  static const _bedtimeOptions = ['22:30', '23:00', '23:30', '00:00'];
  static const _wakeOptions = ['06:30', '07:00', '07:30', '08:00'];
  static const _appOptions = ['抖音', '小红书', '微信', '哔哩哔哩', '淘宝', '知乎'];
  static const _activityOptions = ['听音乐', '冥想', '阅读', '拉伸', '泡脚'];

  @override
  void dispose() {
    _pageCtrl.dispose();
    _username.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  bool _validateStep() {
    if (_step == 0) {
      final u = _username.text.trim();
      if (u.length < 2) {
        setState(() => _error = '用户名至少 2 个字符');
        return false;
      }
      if (_password.text.length < 4) {
        setState(() => _error = '密码至少 4 位');
        return false;
      }
      if (_password.text != _password2.text) {
        setState(() => _error = '两次输入的密码不一致');
        return false;
      }
    }
    setState(() => _error = null);
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    if (_step < 4) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      _submit();
    }
  }

  void _prev() {
    setState(() => _error = null);
    if (_step > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ApiService.register(
        username: _username.text.trim(),
        password: _password.text,
        bedtime: _bedtime,
        wakeTime: _wakeTime,
        apps: _apps.join(','),
        replacementActivity: _activity,
      );
      await AuthService.save(session);
      widget.onRegistered();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(0);
        setState(() => _step = 0);
      }
    } catch (_) {
      setState(() => _error = '连不上服务器，检查网络后再试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPageChanged(int i) => setState(() {
        _step = i;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/erhai-blue-hour.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33102028), Color(0x22102028), Color(0xF014252B)],
                stops: [0, 0.3, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 顶部：返回 + 进度
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _loading ? null : _prev,
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      Text('第 ${_step + 1} / 5 步',
                          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: List.generate(5, (i) {
                      final done = i <= _step;
                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: done ? AppColors.moon : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    children: [
                      _accountStep(),
                      _timeStep(
                        title: '你通常几点入睡?',
                        subtitle: '我们会按这个时间准备你的睡前节奏',
                        options: _bedtimeOptions,
                        selected: _bedtime,
                        onSelect: (v) => setState(() => _bedtime = v),
                      ),
                      _timeStep(
                        title: '你通常几点起床?',
                        subtitle: '保证你有足够的睡眠时长',
                        options: _wakeOptions,
                        selected: _wakeTime,
                        onSelect: (v) => setState(() => _wakeTime = v),
                      ),
                      _appsStep(),
                      _activityStep(),
                    ],
                  ),
                ),
                // 底部：错误提示 + 按钮
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.dusk),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_error!,
                              style:
                                  const TextStyle(fontSize: 13, color: AppColors.dusk, height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                  child: Row(
                    children: [
                      if (_step > 0)
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _loading ? null : _prev,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('上一步'),
                            ),
                          ),
                        ),
                      if (_step > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: _step == 0 ? 1 : 2,
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _loading ? null : _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.moon,
                              foregroundColor: AppColors.ink,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4, color: AppColors.ink),
                                  )
                                : Text(_step == 4 ? '完成建档' : '下一步',
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }

  Widget _accountStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _stepTitle('先让我认识你', '一个账号，记住你的睡眠习惯，以后不用每晚重复输入'),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: _username,
                style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '给自己起个名字（2~24 字符）',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.quiet),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '设置密码（至少 4 位）',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.quiet),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password2,
                obscureText: true,
                style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '再输入一次密码',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.quiet),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeStep({
    required String title,
    required String subtitle,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _stepTitle(title, subtitle),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: options
                .map((t) => _TimePill(
                      label: t,
                      selected: t == selected,
                      onTap: () => onSelect(t),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _CustomTimeTile(
            onPick: (hhmm) => onSelect(hhmm),
          ),
        ),
      ],
    );
  }

  Widget _appsStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _stepTitle('睡前常刷哪些 App?', '诚实一点也没关系，我们只是想在合适的时间轻轻提醒你'),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: _appOptions.map((a) {
              final on = _apps.contains(a);
              return _TimePill(
                label: a,
                selected: on,
                onTap: () => setState(() {
                  on ? _apps.remove(a) : _apps.add(a);
                }),
              );
            }).toList(),
          ),
        ),
        if (_apps.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('（不选也可以，之后在「个人设置」里随时改）',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          ),
      ],
    );
  }

  Widget _activityStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        _stepTitle('想用什么替代刷手机?', '到了入睡提醒时间，晚屿会用这个活动温柔接住你'),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: _activityOptions.map((a) {
              return _TimePill(
                label: a,
                selected: a == _activity,
                onTap: () => setState(() => _activity = a),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _CustomInputTile(
            hintText: '或者写下你自己的（比如：写日记）',
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) setState(() => _activity = v.trim());
            },
          ),
        ),
      ],
    );
  }
}

/// 时间/选项药丸
class _TimePill extends StatelessWidget {
  const _TimePill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.moon.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.moon : Colors.white.withValues(alpha: 0.14),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.moon : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 自定义时间输入（HH:MM）
class _CustomTimeTile extends StatelessWidget {
  const _CustomTimeTile({required this.onPick});
  final ValueChanged<String> onPick;

  Future<void> _showPicker(BuildContext context) async {
    final controller = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B3037),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('自定义时间', style: TextStyle(fontSize: 18, color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
            LengthLimitingTextInputFormatter(5),
          ],
          style: const TextStyle(fontSize: 18, color: Colors.white, letterSpacing: 2),
          decoration: const InputDecoration(
            hintText: '如 23:40',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.moon, foregroundColor: AppColors.ink),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked == null) return;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(picked);
    if (m != null) {
      final hh = int.parse(m.group(1)!);
      final mm = int.parse(m.group(2)!);
      if (hh <= 23 && mm <= 59) onPick('${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: const [
            Icon(Icons.edit_rounded, size: 18, color: AppColors.textTertiary),
            SizedBox(width: 10),
            Text('都不合适？输入自定义时间',
                style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// 自定义文本输入
class _CustomInputTile extends StatelessWidget {
  const _CustomInputTile({required this.hintText, required this.onSubmitted});
  final String hintText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: TextField(
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
          border: InputBorder.none,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}
