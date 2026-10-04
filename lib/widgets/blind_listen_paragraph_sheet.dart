/// 盲听段落选择底部弹窗
///
/// 复用 [showParagraphSelectionSheet] 通用组件，
/// 增加段间停顿倍数选项。
library;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/blind_listen_settings.dart';
import '../models/sentence.dart';
import '../models/study_stage.dart';
import '../models/stage_settings_overrides.dart' show BriefingPauseChoice;
import 'common/paragraph_selection_sheet.dart';
import 'study/study_stage_visuals.dart';

/// 显示盲听段落选择弹窗
///
/// [stageLabel] 可选的阶段名（如"第三轮复习"），显示在标题下方
/// [estimatedDurationText] 可选的预估时长文本，显示在说明下方
/// [defaultPause] 默认句间停顿(自动/固定间隔/句长倍数)，用于回显已记忆值
/// [skipLabel]/[onSkip] 可选，提供时显示「跳过」按钮，点击直接跳过当前任务
Future<void> showBlindListenParagraphSheet({
  required BuildContext context,
  required List<Sentence> sentences,
  String? stageLabel,
  String? estimatedDurationText,
  int defaultSeconds = -1,
  double defaultPlaybackSpeed = 1.0,
  BriefingPauseChoice defaultPause = const BriefingPauseChoice.smart(),
  required void Function(
    Duration targetDuration,
    BriefingPauseChoice pause,
    double playbackSpeed,
  )
  onStartPractice,
  void Function(
    Duration targetDuration,
    BriefingPauseChoice pause,
    double playbackSpeed,
  )?
  onSelectionChanged,
  String? skipLabel,
  VoidCallback? onSkip,
}) {
  final l10n = AppLocalizations.of(context)!;
  final visual = studyStageVisual(StudyStage.blindListen, l10n);
  return showParagraphSelectionSheet(
    context: context,
    icon: visual.icon,
    iconColor: visual.iconColor,
    title: l10n.blindListenBriefingTitle,
    subtitle: l10n.blindListenBriefingTip,
    sentences: sentences,
    defaultSeconds: defaultSeconds,
    showPauseMultiplier: true,
    showPlaybackSpeed: true,
    defaultPlaybackSpeed: defaultPlaybackSpeed,
    // 与盲听 🔧 面板一致(固定间隔 + 句长倍数)，确保播放器内改过的值回填本弹窗时
    // 不会落在 items 之外。
    fixedPauseOptions: BlindListenSettings.fixedPauseOptions,
    pauseMultiplierOptions: BlindListenSettings.multiplierOptions,
    defaultPause: defaultPause,
    stageLabel: stageLabel,
    estimatedDurationText: estimatedDurationText,
    skipLabel: skipLabel,
    onSkip: onSkip,
    // 盲听不显示可见词比例（仅复述用），第三个回调参数忽略
    onStartPractice: (_, _, _) {},
    onStartPracticeWithPlaybackSpeed: (duration, pause, _, speed) =>
        onStartPractice(duration, pause, speed),
    onSelectionChanged: onSelectionChanged == null
        ? null
        : (duration, pause, _, speed) =>
              onSelectionChanged(duration, pause, speed),
  );
}
