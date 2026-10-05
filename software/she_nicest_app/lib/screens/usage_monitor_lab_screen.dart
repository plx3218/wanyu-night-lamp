import 'package:flutter/material.dart';

import '../services/android_usage_service.dart';
import '../theme/app_theme.dart';

class UsageMonitorLabScreen extends StatefulWidget {
  const UsageMonitorLabScreen({super.key});

  @override
  State<UsageMonitorLabScreen> createState() => _UsageMonitorLabScreenState();
}

class _UsageMonitorLabScreenState extends State<UsageMonitorLabScreen>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _hasAccess = false;
  String? _error;
  List<AndroidUsageEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAccess();
  }

  Future<void> _refreshAccess() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final granted = await AndroidUsageService.hasAccess();
      if (!mounted) return;
      setState(() {
        _hasAccess = granted;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '权限检查失败：$error';
      });
    }
  }

  Future<void> _readUsage() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final entries =
          await AndroidUsageService.queryLast(const Duration(minutes: 30));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '读取失败：$error';
      });
    }
  }

  String _durationText(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes} 分 ${duration.inSeconds.remainder(60)} 秒';
    }
    return '${duration.inSeconds} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安卓监测实验室')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              '这里只验证手机能否提供 App 使用时长。读取结果仅显示在本机，'
              '不会上传；通过实验后，才会设计正式提醒。',
              style: TextStyle(height: 1.55, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _hasAccess
                  ? Icons.check_circle_rounded
                  : Icons.lock_outline_rounded,
              color: _hasAccess ? AppColors.lake : AppColors.moon,
            ),
            title: Text(_hasAccess ? '已允许查看使用时长' : '尚未授权'),
            subtitle: const Text('需要在系统设置中允许“晚屿”访问使用情况'),
          ),
          if (!_hasAccess)
            FilledButton(
              onPressed: AndroidUsageService.isSupported
                  ? AndroidUsageService.openAccessSettings
                  : null,
              child: const Text('前往系统设置授权'),
            )
          else
            FilledButton(
              onPressed: _checking ? null : _readUsage,
              child: const Text('读取最近 30 分钟'),
            ),
          if (_checking) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.dusk)),
          ],
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('本机读取结果',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._entries.take(20).map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.packageName),
                    trailing: Text(_durationText(entry.duration)),
                  ),
                ),
          ],
          const SizedBox(height: 18),
          const Text(
            '实验通过标准：打开一个娱乐 App 约 2 分钟，再回来读取时，'
            '对应包名的累计时长与实际相近。',
            style: TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
