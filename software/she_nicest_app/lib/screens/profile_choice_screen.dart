import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// 建档完成后的选择页：直接用习惯生成计划 vs 和 AI 聊聊优化
class ProfileChoiceScreen extends StatefulWidget {
  const ProfileChoiceScreen({required this.controller, super.key});
  final AppController controller;

  @override
  State<ProfileChoiceScreen> createState() => _ProfileChoiceScreenState();
}

class _ProfileChoiceScreenState extends State<ProfileChoiceScreen> {
  bool _generating = false;

  Future<void> _generateDirect() async {
    setState(() => _generating = true);
    final ok = await widget.controller.generatePlanFromProfile();
    if (!mounted) return;
    if (ok) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
      // 回首页后用户点「看看今晚的安排」进入 /plan
      if (mounted) {
        Navigator.pushNamed(context, '/plan');
      }
    } else {
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('生成失败了，可以重试，或者选择和 AI 聊聊'),
          backgroundColor: AppColors.cardBg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  void _goChat() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
    Navigator.pushNamed(context, '/chat');
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.user;
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.moon.withValues(alpha: 0.12),
                        border: Border.all(color: AppColors.moon.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.nights_stay_rounded, size: 32, color: AppColors.moon),
                    ),
                    const SizedBox(height: 16),
                    Text('${user?.username ?? '你'}，你的档案建好了',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('今晚想怎么开始？',
                        style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                    const SizedBox(height: 22),
                    // 档案摘要卡片
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Column(
                        children: [
                          _summaryRow(Icons.bedtime_rounded, '通常入睡', user?.bedtime ?? '23:00'),
                          const Divider(height: 18, color: Color(0x22FFFFFF)),
                          _summaryRow(Icons.wb_sunny_outlined, '通常起床', user?.wakeTime ?? '07:30'),
                          const Divider(height: 18, color: Color(0x22FFFFFF)),
                          _summaryRow(Icons.apps_rounded, '睡前常刷',
                              (user?.apps.isEmpty ?? true) ? '无特别偏好' : user!.apps),
                          const Divider(height: 18, color: Color(0x22FFFFFF)),
                          _summaryRow(
                              Icons.music_note_rounded, '替代活动', user?.replacementActivity ?? '音乐'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    // 选项 A：直接生成
                    SizedBox(
                      width: double.infinity,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _generating ? null : _generateDirect,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: AppColors.moon.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.moon.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: AppColors.moon.withValues(alpha: 0.2),
                                ),
                                child: _generating
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.moon),
                                      )
                                    : const Icon(Icons.auto_awesome_rounded, color: AppColors.moon),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _generating ? '正在为你生成今晚计划…' : '直接用我的习惯生成计划',
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.moon),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '不用聊天，按档案直接安排三步睡前安排',
                                      style: const TextStyle(
                                          fontSize: 12.5, color: AppColors.textSecondary, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 选项 B：和 AI 聊聊
                    SizedBox(
                      width: double.infinity,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _generating ? null : _goChat,
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                child: const Icon(Icons.chat_bubble_outline_rounded,
                                    color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text('和 AI 聊聊，优化一下',
                                        style: TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.w700)),
                                    SizedBox(height: 2),
                                    Text('今晚状态不一样？告诉它，它会更懂你',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textSecondary,
                                            height: 1.3)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _generating
                          ? null
                          : () => Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
                      child: const Text('先不急，回首页看看',
                          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.quiet),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textTertiary)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
