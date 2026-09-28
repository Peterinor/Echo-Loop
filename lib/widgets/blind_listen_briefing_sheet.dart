/// 全文盲听简报底部弹窗
///
/// 显示当前阶段信息、练习提示和音频时长，
/// 点击"开始练习"后进入盲听播放器。
library;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/study_stage.dart';
import '../theme/app_theme.dart';
import 'common/learning_briefing_sheet_content.dart';
import 'study/study_stage_visuals.dart';

/// 显示盲听简报底部弹窗
///
/// [isFirstStudy] 为 true 时显示"首次学习"标题，否则显示复习轮次。
/// [reviewRound] 复习轮次（仅复习时使用）。
/// [audioDuration] 音频总时长。
/// [onStartPractice] 点击"开始练习"的回调。
Future<void> showBlindListenBriefingSheet({
  required BuildContext context,
  required bool isFirstStudy,
  int reviewRound = 0,
  Duration? audioDuration,
  Duration? estimatedDuration,
  required VoidCallback onStartPractice,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => BlindListenBriefingSheet(
      isFirstStudy: isFirstStudy,
      reviewRound: reviewRound,
      audioDuration: audioDuration,
      estimatedDuration: estimatedDuration,
      onStartPractice: onStartPractice,
    ),
  );
}

/// 盲听简报弹窗内容
class BlindListenBriefingSheet extends StatelessWidget {
  /// 是否为首次学习
  final bool isFirstStudy;

  /// 复习轮次（仅复习时使用）
  final int reviewRound;

  /// 音频总时长
  final Duration? audioDuration;

  /// 预估练习时长
  final Duration? estimatedDuration;

  /// 开始练习回调
  final VoidCallback onStartPractice;

  const BlindListenBriefingSheet({
    super.key,
    required this.isFirstStudy,
    this.reviewRound = 0,
    this.audioDuration,
    this.estimatedDuration,
    required this.onStartPractice,
  });

  /// 格式化时长为 mm:ss
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化预估时长为"预计 X 分钟"
  String _formatEstimatedDuration(AppLocalizations l10n, Duration duration) {
    final minutes = (duration.inSeconds / 60).ceil();
    if (minutes < 1) return l10n.estimatedLessThanOneMinute;
    return l10n.estimatedMinutes(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final visual = studyStageVisual(StudyStage.blindListen, l10n);

    // 阶段副标题
    final subtitle = isFirstStudy
        ? l10n.blindListenBriefingSubtitle
        : l10n.blindListenBriefingReviewSubtitle(reviewRound);

    return LearningBriefingSheetContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // 与学习任务列表共用阶段图标和颜色。
          Icon(
            visual.icon,
            size: 56,
            color: visual.iconColor ?? theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.m),

          // 标题
          Text(
            l10n.blindListenBriefingTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // 副标题
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.l),

          // 练习提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    l10n.blindListenBriefingTip,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          // 音频时长 + 预估时长
          if (audioDuration != null || estimatedDuration != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.l),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (audioDuration != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(audioDuration!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  if (audioDuration != null && estimatedDuration != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s,
                      ),
                      child: Text(
                        '·',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (estimatedDuration != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatEstimatedDuration(l10n, estimatedDuration!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

          // 开始练习按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onStartPractice();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.startPractice),
            ),
          ),
        ],
      ),
    );
  }
}
