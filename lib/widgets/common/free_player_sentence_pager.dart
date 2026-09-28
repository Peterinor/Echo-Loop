import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_item.dart';
import '../../models/sentence.dart';
import '../../models/sense_group_range_playback.dart';
import '../../services/subtitle_parser.dart';
import '../../theme/app_theme.dart';
import 'bookmark_toggle_row.dart';
import '../dictionary/dictionary_panel_host.dart';
import '../practice/practice_progress_section.dart';
import '../practice/sentence_explanation_view.dart';

const kFullSingleSentenceSwipeAreaKey = ValueKey(
  'player-single-sentence-swipe-area',
);
const kBookmarkSingleSentenceSwipeAreaKey = ValueKey(
  'player-bookmark-single-sentence-swipe-area',
);

/// 单句视图所在的播放列表，用于隔离全文与收藏两个分页器。
enum FreePlayerSentenceScope { full, bookmarks }

/// 单句视图触发的播放器动作。
///
/// 组件只表达交互意图，不依赖 just_audio 或 media_kit 的 controller。
class FreePlayerSentenceActions {
  const FreePlayerSentenceActions({
    required this.onSentenceSelected,
    required this.onBookmarkToggle,
    required this.onStopMainPlayer,
    required this.onToolbarButtonTapped,
    this.senseGroupRangePlayback,
  });

  final Future<void> Function(int index, {bool autoPlay}) onSentenceSelected;
  final ValueChanged<int> onBookmarkToggle;
  final VoidCallback onStopMainPlayer;
  final VoidCallback onToolbarButtonTapped;

  /// 可选的会话级意群区间播放器；未提供时正文保持原音频路径。
  final SenseGroupRangePlayback? senseGroupRangePlayback;
}

/// 音频与视频随心听共用的单句分页器。
///
/// 仅负责随心听的列表位置映射、左右分页和宿主布局；讲解展示统一由
/// [SentenceExplanationView] 管理。程序化分页期间会屏蔽回调，避免自动推进或
/// 循环回卷反向重启播放。
class FreePlayerSentencePager extends StatefulWidget {
  const FreePlayerSentencePager({
    super.key,
    required this.audioItem,
    required this.sentences,
    required this.currentSentenceIndex,
    required this.bookmarkedSentenceIndices,
    required this.showTranscript,
    required this.isPlaying,
    required this.scope,
    required this.actions,
  });

  final AudioItem audioItem;
  final List<Sentence> sentences;
  final int currentSentenceIndex;
  final Set<int> bookmarkedSentenceIndices;
  final bool showTranscript;
  final bool isPlaying;
  final FreePlayerSentenceScope scope;
  final FreePlayerSentenceActions actions;

  @override
  State<FreePlayerSentencePager> createState() =>
      _FreePlayerSentencePagerState();
}

class _FreePlayerSentencePagerState extends State<FreePlayerSentencePager> {
  final PageController _pageController = PageController();
  bool _pagerSynced = false;
  bool _programmaticPageChange = false;

  /// 切句即结束查词会话（本视图由播放器真相源的 [currentSentenceIndex] 驱动，
  /// 横滑 / 自动推进 / 进度条跳句 / 底部切句最终都收敛到这里，是单一入口）。
  ///
  /// 面板与选区绑定在同一个句子上：`PageView` 每页是独立实例，跨句存活会让
  /// 已离屏的旧 owner 继续把焦点和操作条投影到离屏页的几何上。
  @override
  void didUpdateWidget(FreePlayerSentencePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSentenceIndex != widget.currentSentenceIndex) {
      DictionaryPanelHost.maybeOf(context)?.closeIfOpen();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetPosition = widget.sentences.indexWhere(
      (sentence) => sentence.index == widget.currentSentenceIndex,
    );
    if (targetPosition < 0) return const SizedBox.shrink();

    _syncPage(targetPosition);

    final currentSentence = widget.sentences[targetPosition];
    return Column(
      children: [
        PracticeSentenceInfoRow(
          progressText: AppLocalizations.of(context)!.intensiveListenProgress(
            targetPosition + 1,
            widget.sentences.length,
          ),
          durationText: AppLocalizations.of(context)!.sentenceDuration(
            (currentSentence.duration.inMilliseconds / 1000).toStringAsFixed(1),
          ),
          timestampText:
              '${SubtitleParser.formatDuration(currentSentence.startTime)} - '
              '${SubtitleParser.formatDuration(currentSentence.endTime)}',
          trailing: BookmarkToggleRow(
            isDifficult: widget.bookmarkedSentenceIndices.contains(
              currentSentence.index,
            ),
            onTap: () => widget.actions.onBookmarkToggle(currentSentence.index),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: PageView.builder(
              key: widget.scope == FreePlayerSentenceScope.bookmarks
                  ? kBookmarkSingleSentenceSwipeAreaKey
                  : kFullSingleSentenceSwipeAreaKey,
              // 面板开着时不接受滑动：屏障按区域放行正文文本以支持连续点词，而触屏的
              // 水平拖拽不被文本消费，会穿到这里造成「切句了但面板还开着」。
              // 文本区域的 tap / 长按 / 手柄拖拽不受影响。
              physics: DictionaryPanelHost.isPanelOpenOf(context)
                  ? const NeverScrollableScrollPhysics()
                  : null,
              controller: _pageController,
              itemCount: widget.sentences.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, position) => _buildSentencePage(
                widget.sentences[position],
                isActivePage: position == targetPosition,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 将播放器真相源同步到分页器；相邻句动画过渡，跨多句直接跳转。
  void _syncPage(int targetPosition) {
    final firstSync = !_pagerSynced;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_pageController.page?.round() == targetPosition) return;

      _programmaticPageChange = true;
      final currentPage = _pageController.page?.round();
      final isAdjacent =
          !firstSync &&
          currentPage != null &&
          (targetPosition - currentPage).abs() == 1;
      if (isAdjacent) {
        _pageController
            .animateToPage(
              targetPosition,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _programmaticPageChange = false);
      } else {
        _pageController.jumpToPage(targetPosition);
        _programmaticPageChange = false;
      }
    });
    _pagerSynced = true;
  }

  /// 用户翻页时把列表位置映射回全局句子索引，并保持当前播放/暂停状态。
  void _onPageChanged(int position) {
    if (_programmaticPageChange ||
        position < 0 ||
        position >= widget.sentences.length) {
      return;
    }
    final index = widget.sentences[position].index;
    if (index == widget.currentSentenceIndex) return;
    unawaited(
      widget.actions.onSentenceSelected(index, autoPlay: widget.isPlaying),
    );
  }

  Widget _buildSentencePage(Sentence sentence, {required bool isActivePage}) {
    // 分页页填满视口，讲解组件只滚动工具栏和正文。
    return Column(
      children: [
        Expanded(
          // 滑动区已由宿主提供水平留白，内容无需再次缩进。
          child: SentenceExplanationView(
            key: ValueKey(sentence.index),
            text: sentence.text,
            audioItemId: widget.audioItem.id,
            sentenceIndex: sentence.index,
            sentenceStartMs: sentence.startTime.inMilliseconds,
            sentenceEndMs: sentence.endTime.inMilliseconds,
            explanationContext: const SentenceExplanationContext(
              source: 'freePlayer',
            ),
            onStopMainPlayer: widget.actions.onStopMainPlayer,
            senseGroupRangePlayback: widget.actions.senseGroupRangePlayback,
            onToolbarButtonTapped: widget.actions.onToolbarButtonTapped,
            enableGuide: isActivePage,
            isActiveSentence: isActivePage,
            showTranscript: widget.showTranscript,
          ),
        ),
      ],
    );
  }
}
