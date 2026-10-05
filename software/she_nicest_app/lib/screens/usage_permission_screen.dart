import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/android_usage_service.dart';
import '../services/usage_monitor_coordinator.dart';
import '../theme/app_theme.dart';

enum UsagePermissionUiState {
  permissionRequired,
  authorizedNotStarted,
  monitoring,
  interrupted,
  completed,
  fallback,
}

String usagePermissionStateLabel(UsagePermissionUiState state) {
  switch (state) {
    case UsagePermissionUiState.permissionRequired:
      return '未授权使用情况访问';
    case UsagePermissionUiState.authorizedNotStarted:
      return '已授权，等待监测窗口';
    case UsagePermissionUiState.monitoring:
      return '监测中';
    case UsagePermissionUiState.interrupted:
      return '监测中断';
    case UsagePermissionUiState.completed:
      return '本次监测已完成';
    case UsagePermissionUiState.fallback:
      return '降级模式：仅执行计划并保存记录';
  }
}

class UsagePermissionScreen extends StatefulWidget {
  const UsagePermissionScreen({required this.controller, super.key, this.client});

  final AppController controller;
  final AndroidUsageClient? client;

  @override
  State<UsagePermissionScreen> createState() => _UsagePermissionScreenState();
}

class _UsagePermissionScreenState extends State<UsagePermissionScreen>
    with WidgetsBindingObserver {
  late final AndroidUsageClient _client = widget.client ?? AndroidUsageClient();
  bool? _hasAccess;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final access = await _client.hasAccess();
    if (!mounted) return;
    setState(() {
      _hasAccess = access;
      _loading = false;
    });
  }

  UsagePermissionUiState _state() {
    if (_hasAccess != true) return UsagePermissionUiState.permissionRequired;
    final event = widget.controller.lastUsageMonitorEvent;
    if (event?.type == UsageMonitorEventType.permissionRequired) {
      return UsagePermissionUiState.permissionRequired;
    }
    if (event?.type == UsageMonitorEventType.unavailable) {
      return UsagePermissionUiState.interrupted;
    }
    if (event?.type == UsageMonitorEventType.stopped) {
      return UsagePermissionUiState.completed;
    }
    if (widget.controller.usageMonitor.isRunning) {
      final schedule = widget.controller.monitorSchedule;
      if (schedule != null && DateTime.now().isBefore(schedule.startAt)) {
        return UsagePermissionUiState.authorizedNotStarted;
      }
      return UsagePermissionUiState.monitoring;
    }
    return UsagePermissionUiState.fallback;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state();
    final event = widget.controller.lastUsageMonitorEvent;
    final schedule = widget.controller.monitorSchedule;
    return Scaffold(
      appBar: AppBar(title: const Text('监测权限与状态')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Icon(Icons.privacy_tip_outlined, size: 56, color: AppColors.lake),
          const SizedBox(height: 16),
          const Text('为什么需要这个权限？', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            '晚屿只读取 Android 的 App 使用时段，用来判断同一类别是否连续刷了 20 分钟。不会上传实际浏览内容；原始记录尽量只保存在手机，测试服务器只接收你同意后的每日汇总。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 24),
          Card(
            color: AppColors.cardBg,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(usagePermissionStateLabel(state), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (schedule != null) ...[
                    Text('监测开始：${_fmt(schedule.startAt)}'),
                    Text('目标入睡：${_fmt(schedule.targetBedtime)}'),
                  ],
                  if (event?.occurredAt != null)
                    Text('最近状态时间：${_fmt(event!.occurredAt)}'),
                  if (_loading) const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _client.isSupported ? () => _client.openAccessSettings() : null,
            icon: const Icon(Icons.settings_outlined),
            label: Text(_hasAccess == true ? '重新检查权限' : '去系统设置开启权限'),
          ),
          if (_hasAccess == false) ...[
            const SizedBox(height: 12),
            const Text('如果你暂时不授权，仍可使用本地睡前计划和今晚记录，但不会有基于 App 使用时长的提醒。', style: TextStyle(color: AppColors.textTertiary, height: 1.5)),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
