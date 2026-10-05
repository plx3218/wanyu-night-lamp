import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// 个人设置：查看/编辑睡眠档案 + 管理员状态 + 退出登录
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  late String _bedtime;
  late String _wakeTime;
  late String _apps;
  late String _activity;
  bool _initialized = false;

  static const _bedtimeOptions = ['22:30', '23:00', '23:30', '00:00'];
  static const _wakeOptions = ['06:30', '07:00', '07:30', '08:00'];
  static const _appOptions = ['抖音', '小红书', '微信', '哔哩哔哩', '淘宝', '知乎'];
  static const _activityOptions = ['听音乐', '冥想', '阅读', '拉伸', '泡脚'];

  @override
  void initState() {
    super.initState();
    final u = AuthService.user;
    _bedtime = u?.bedtime ?? '23:00';
    _wakeTime = u?.wakeTime ?? '07:30';
    _apps = u?.apps ?? '';
    _activity = u?.replacementActivity ?? '听音乐';
    _initialized = true;
  }

  bool get _dirty {
    final u = AuthService.user;
    if (u == null) return false;
    return _bedtime != u.bedtime ||
        _wakeTime != u.wakeTime ||
        _apps != u.apps ||
        _activity != u.replacementActivity;
  }

  Set<String> get _selectedApps =>
      _apps.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

  void _toggleApp(String a) {
    setState(() {
      final s = _selectedApps;
      s.contains(a) ? s.remove(a) : s.add(a);
      _apps = s.join(',');
    });
  }

  Future<void> _save() async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final updated = await ApiService.updateProfile(
        token,
        bedtime: _bedtime,
        wakeTime: _wakeTime,
        apps: _apps,
        replacementActivity: _activity,
      );
      AuthService.updateCachedUser(updated);
      widget.controller.syncProfileContext();
      setState(() {
        _saving = false;
        _message = '档案已保存，今晚开始生效';
        _messageIsError = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _message = e.message;
        _messageIsError = true;
      });
    } catch (_) {
      setState(() {
        _saving = false;
        _message = '网络异常，稍后再试';
        _messageIsError = true;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B3037),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('退出登录？',
            style: TextStyle(fontSize: 18, color: Colors.white)),
        content: const Text('档案保存在云端，下次登录还在。',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.dusk, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.user;
    if (!_initialized)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                colors: [
                  Color(0x55102028),
                  Color(0x22102028),
                  Color(0xF014252B)
                ],
                stops: [0, 0.25, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 顶栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 4),
                      const Text('个人设置',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (_dirty && !_saving)
                        TextButton(
                          onPressed: _save,
                          child: const Text('保存',
                              style: TextStyle(color: AppColors.moon)),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      // 用户卡片
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.lake.withValues(alpha: 0.16),
                                border: Border.all(
                                    color:
                                        AppColors.lake.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.person_rounded,
                                  color: AppColors.lake, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user?.username ?? '未登录',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      if (user?.isAdmin == true) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.moon
                                                .withValues(alpha: 0.16),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: AppColors.moon
                                                    .withValues(alpha: 0.45)),
                                          ),
                                          child: const Text('管理员',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.moon,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (user?.isAdmin ?? false)
                                        ? '时间快进已开启（1 分钟 = 1 秒）'
                                        : '档案云端同步中',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('睡眠习惯'),
                      _settingCard(
                        Icons.bedtime_rounded,
                        '通常入睡时间',
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _bedtimeOptions
                              .map((t) => _chip(t, t == _bedtime,
                                  () => setState(() => _bedtime = t)))
                              .toList(),
                        ),
                        allowCustom: true,
                        onCustom: (v) => setState(() => _bedtime = v),
                        customHint: '自定义入睡时间（如 23:40）',
                      ),
                      _settingCard(
                        Icons.wb_sunny_outlined,
                        '通常起床时间',
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _wakeOptions
                              .map((t) => _chip(t, t == _wakeTime,
                                  () => setState(() => _wakeTime = t)))
                              .toList(),
                        ),
                        allowCustom: true,
                        onCustom: (v) => setState(() => _wakeTime = v),
                        customHint: '自定义起床时间（如 6:45）',
                      ),
                      _settingCard(
                        Icons.apps_rounded,
                        '睡前常刷的 App',
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _appOptions
                              .map((a) => _chip(a, _selectedApps.contains(a),
                                  () => _toggleApp(a)))
                              .toList(),
                        ),
                      ),
                      _settingCard(
                        Icons.music_note_rounded,
                        '睡前替代活动',
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _activityOptions
                              .map((a) => _chip(a, a == _activity,
                                  () => setState(() => _activity = a)))
                              .toList(),
                        ),
                        allowCustom: true,
                        onCustom: (v) => setState(() => _activity = v),
                        customHint: '自定义活动（如 写日记）',
                      ),
                      _settingCard(
                        Icons.privacy_tip_outlined,
                        '监测权限与数据说明',
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.security_rounded,
                              color: AppColors.lake),
                          title: const Text('使用情况访问权限'),
                          subtitle: const Text('查看授权、监测窗口和降级状态'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pushNamed(
                              context, '/usage-permission'),
                        ),
                      ),
                      _settingCard(
                        Icons.science_outlined,
                        'AfterHack 技术实验',
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.android_rounded,
                              color: AppColors.lake),
                          title: const Text('安卓 App 使用时长监测'),
                          subtitle: const Text('仅验证系统能力，数据不上传'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pushNamed(
                              context, '/usage-monitor-lab'),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _messageIsError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                              color: _messageIsError
                                  ? AppColors.dusk
                                  : AppColors.lake,
                            ),
                            const SizedBox(width: 6),
                            Text(_message!,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: _messageIsError
                                        ? AppColors.dusk
                                        : AppColors.lake)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_dirty)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.moon,
                              foregroundColor: AppColors.ink,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4, color: AppColors.ink),
                                  )
                                : const Text('保存修改',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded,
                            size: 18, color: AppColors.textTertiary),
                        label: const Text('退出登录',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 14)),
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _settingCard(
    IconData icon,
    String title,
    Widget content, {
    bool allowCustom = false,
    ValueChanged<String>? onCustom,
    String? customHint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.quiet),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          content,
          if (allowCustom && onCustom != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () =>
                  _showCustomDialog(context, customHint ?? '', onCustom),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded,
                        size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(customHint ?? '自定义',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textTertiary)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showCustomDialog(
      BuildContext context, String hint, ValueChanged<String> onDone) async {
    final controller = TextEditingController();
    final isTime = hint.contains('时间');
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B3037),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(hint,
            style: const TextStyle(fontSize: 17, color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: isTime ? TextInputType.datetime : TextInputType.text,
          inputFormatters: isTime
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                  LengthLimitingTextInputFormatter(5)
                ]
              : null,
          style: const TextStyle(fontSize: 17, color: Colors.white),
          decoration: const InputDecoration(
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.moon,
                foregroundColor: AppColors.ink),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked == null || picked.isEmpty) return;
    if (isTime) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(picked);
      if (m != null) {
        final hh = int.parse(m.group(1)!);
        final mm = int.parse(m.group(2)!);
        if (hh <= 23 && mm <= 59) {
          onDone(
              '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
        }
      }
    } else {
      onDone(picked);
    }
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.moon.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.moon
                : Colors.white.withValues(alpha: 0.14),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.moon : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
