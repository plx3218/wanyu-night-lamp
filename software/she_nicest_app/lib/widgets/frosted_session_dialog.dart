import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 毛玻璃弹窗 — 对应设计稿"入睡提醒弹窗 · 毛玻璃版"
/// 通过参数区分不同状态（第一次问 / 再问 / 信息弹窗）
class FrostedSessionDialog extends StatelessWidget {
  const FrostedSessionDialog({
    super.key,
    required this.title,
    required this.subtitle,
    this.brightness,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.lampStatus,
    this.demoHint,
    this.icon = Icons.nightlight_round,
  });

  final String title;
  final String subtitle;
  final int? brightness;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? lampStatus;
  final String? demoHint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (brightness != null) ...[
                const SizedBox(height: 14),
                _buildBrightnessBadge(),
              ],
              const SizedBox(height: 24),
              _buildPrimaryButton(),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel!,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                ),
              ],
              if (lampStatus != null || demoHint != null) ...[
                const SizedBox(height: 16),
                _buildBottomBar(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.moon.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.moon.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 28, color: AppColors.moon),
    );
  }

  Widget _buildBrightnessBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.moon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.moon.withValues(alpha: 0.2)),
      ),
      child: Text(
        '当前亮度 $brightness%',
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.moon,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPrimary,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.moon,
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          primaryLabel,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          if (lampStatus != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_rounded, size: 14, color: AppColors.lake),
                const SizedBox(width: 6),
                Text(
                  lampStatus!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          if (demoHint != null) ...[
            if (lampStatus != null) const SizedBox(height: 4),
            Text(
              demoHint!,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
