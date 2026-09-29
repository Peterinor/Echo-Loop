/// 段落句子列表卡片
///
/// 统一渲染段落内句子列表，供全文盲听和段落复述共用。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../models/retell_settings.dart';
import '../../models/sentence.dart';
import '../../models/sentence_focus_reason.dart';
import '../../theme/app_theme.dart';
import '../guide_flow.dart';
import 'masked_sentence_tile.dart';

/// 计算自动跟随当前播放句时 [ItemScrollController.scrollTo] 的锚定 alignment。
///
/// 纯函数，便于单元测试。列表统一使用 [ClampingScrollPhysics]，越界滚动会被逐帧
/// clamp 到自然边界（详见 [_ParagraphSentenceListCardState.build]），因此边界句的
/// 贴边交给物理处理，这里只需决定锚点：
/// - **目标可见**：命中 `scrollTo` 的「可见分支」（不改底层 `anchor`），返回 0.4
///   让中间句与首次定位保持一致；靠边时会被 clamp 到自然边缘（末句贴底 / 首句贴顶，
///   无留白、无回弹）。
/// - **目标不可见**（大跳转，命中 else 分支会把底层 `anchor` 设为传入 alignment）：
///   返回 0.0，令 `anchor` 维持 0（普通列表语义），目标落到顶部、若为末句则被
///   clamp 到底部，均无留白。
double autoFollowAlignment({required bool targetVisible}) {
  return targetVisible ? 0.4 : 0.0;
}

/// 自动跟随的「目标定位容差带」半宽（占视口比例）。
///
/// 目标句的 leading edge 落在 `[0.4 - 容差, 0.4 + 容差]` 内即视为已大致定位。
const double kAutoFollowCenterTolerance = 0.08;

/// 目标句当前是否已大致位于 0.4 锚点附近，已定位则无需再滚动。
///
/// 纯函数，便于单元测试。仅用 leading edge 判断：随播放逐句推进，下一句的 leading
/// edge 会比当前句更靠下；一旦越出容差带就重新居中，避免「当前句逐句下移直到贴底、
/// 再突然跳回顶部」的漂移（参见 [_ParagraphSentenceListCardState._focusPlayingSentence]）。
///
/// [leadingEdge] 为目标 item 顶边相对视口的比例（[ItemPosition.itemLeadingEdge]）。
bool isTargetWellCentered({
  required double leadingEdge,
  double tolerance = kAutoFollowCenterTolerance,
}) {
  return (leadingEdge - 0.4).abs() <= tolerance;
}

/// 判断列表中的句子集合或顺序是否真正变化。
///
/// provider 的派生 getter 可能在每次播放进度更新时返回新 List；不能
/// 用 List 实例身份判断段落变化，否则会持续重启自动滚动并吞掉 item 点击。
bool _sentenceSequenceChanged(List<Sentence> previous, List<Sentence> next) {
  if (previous.length != next.length) return true;
  for (var i = 0; i < previous.length; i += 1) {
    if (previous[i].index != next[i].index) return true;
  }
  return false;
}

/// 初次定位可见性容器的 key（供测试断言定位完成前列表不可见）。
@visibleForTesting
const Key kParagraphListInitialFocusKey = ValueKey(
  'paragraph-list-initial-focus',
);

/// 段落句子列表卡片
class ParagraphSentenceListCard extends StatefulWidget {
  final List<Sentence> sentences;
  final RetellDisplayMode displayMode;
  final Map<int, Set<int>> keywordMap;
  final int playingSentenceIndex;
  final bool autoFocusEnabled;
  final bool focusActive;
  final int? focusRequestRevision;
  final SentenceFocusReason? focusReason;
  final int focusRestoreRevision;

  /// 是否在定位完成前隐藏列表并在完成后瞬时显示，供需要无初始动画的播放器使用。
  final bool directInitialPositioning;
  final Duration autoFocusResumeDelay;

  /// 已收藏句子索引集合（用于显示只读标记）
  final Set<int> bookmarkedSentenceIndices;

  /// 点击左侧讲解按钮回调：进入句子讲解页
  final ValueChanged<Sentence>? onSentenceExplanationTap;

  /// 点击句子主体回调：从该句开始播放
  final ValueChanged<Sentence>? onSentencePlayFrom;

  /// 点击句子右侧收藏按钮回调：直接切换收藏状态
  final ValueChanged<Sentence>? onSentenceBookmarkToggle;

  /// 新手引导：挂引导 step 的句子本地索引（默认挂在 idx=1，回退到 idx=0）
  final int? guideTargetLocalIdx;

  /// 新手引导：左侧讲解按钮 step
  final GuideStep? explanationAreaGuideStep;

  /// 新手引导：句子主体播放 step
  final GuideStep? bodyAreaGuideStep;

  const ParagraphSentenceListCard({
    super.key,
    required this.sentences,
    required this.displayMode,
    required this.keywordMap,
    required this.playingSentenceIndex,
    this.autoFocusEnabled = false,
    this.focusActive = true,
    this.focusRequestRevision,
    this.focusReason,
    this.focusRestoreRevision = 0,
    this.directInitialPositioning = false,
    this.autoFocusResumeDelay = const Duration(seconds: 2),
    this.bookmarkedSentenceIndices = const {},
    this.onSentenceExplanationTap,
    this.onSentencePlayFrom,
    this.onSentenceBookmarkToggle,
    this.guideTargetLocalIdx,
    this.explanationAreaGuideStep,
    this.bodyAreaGuideStep,
  });

  @override
  State<ParagraphSentenceListCard> createState() =>
      _ParagraphSentenceListCardState();
}

class _ParagraphSentenceListCardState extends State<ParagraphSentenceListCard>
    with AutomaticKeepAliveClientMixin {
  // 在 TabBarView（底层 PageView）中保活：切 Tab 不销毁本列表 State，避免回到全文/
  // 收藏 Tab 时重跑「初次定位 + 淡入」造成的列表重渲染闪烁，并保留滚动位置。
  @override
  bool get wantKeepAlive => true;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _resumeFocusTimer;
  bool _userSuspendedFocus = false;
  int _focusRequestGeneration = 0;

  /// 初始定位时当前句在列表中的 item 索引。
  int _initialScrollIndex = 0;

  /// 「初次定位」是否完成。完成前列表不可见，避免用户看到定位过程；直接定位模式
  /// 完成后瞬时显出，其他复用场景沿用原有淡入。
  bool _initialFocusDone = false;

  @override
  void initState() {
    super.initState();
    // 按当前索引初始化，并在列表不可见时完成边界校正。
    final localSentenceIndex = _playingSentenceLocalIndex();
    final shouldCenter = widget.autoFocusEnabled && localSentenceIndex != null;
    if (shouldCenter) {
      _initialScrollIndex = localSentenceIndex * 2;
      // 保持列表 anchor=0；非零 initialAlignment 在首尾会产生空白，故通过可见 item
      // 的滚动分支校正后再瞬时显示。
      if (widget.focusActive) _centerInitialFocus(localSentenceIndex * 2);
    } else {
      // 无需自动居中（如段落复述）：列表直接可见，从顶部开始。
      _initialFocusDone = true;
    }
  }

  /// 在不可见状态下把当前句定位到视口锚点，完成后更新 [_initialFocusDone]。
  ///
  /// 先 [ItemScrollController.jumpTo]（alignment=0）把目标放到顶边并保持普通列表 anchor；
  /// 下一帧目标已可见，再由 [scrollTo] 的可见分支调整偏移。随心听定位用 1ms 完成校正，
  /// 且校正期间列表不可见；初次定位与后续自动跟随统一使用 0.4 锚点。首尾边界由滚动
  /// 范围自然约束。
  void _centerInitialFocus(int targetIndex) {
    final generation = ++_focusRequestGeneration;
    _hideWhilePositioning();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.autoFocusEnabled ||
          !widget.focusActive ||
          generation != _focusRequestGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0);
      _schedulePositionCorrection(targetIndex, generation);
    });
  }

  /// 确保安全跳转后的下一次布局执行 0.4 对齐校正。
  ///
  /// post-frame 回调自身不会请求新帧；恢复页面时若没有其他状态变化，单纯注册回调
  /// 会让定位停在安全顶边位置，因此这里显式安排下一帧。
  void _schedulePositionCorrection(int targetIndex, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _correctPositionImmediately(targetIndex, generation);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _hideWhilePositioning() {
    if (widget.directInitialPositioning && _initialFocusDone) {
      setState(() => _initialFocusDone = false);
    }
  }

  void _correctPositionImmediately(int targetIndex, int generation) {
    if (!mounted ||
        !widget.autoFocusEnabled ||
        !widget.focusActive ||
        generation != _focusRequestGeneration ||
        !_itemScrollController.isAttached) {
      return;
    }
    if (widget.directInitialPositioning) {
      _itemScrollController.jumpTo(
        index: targetIndex,
        alignment: autoFollowAlignment(targetVisible: true),
      );
      if (mounted && generation == _focusRequestGeneration) {
        setState(() => _initialFocusDone = true);
      }
      return;
    }

    _itemScrollController
        .scrollTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 1),
          curve: Curves.easeInOut,
          alignment: autoFollowAlignment(targetVisible: true),
        )
        .whenComplete(() {
          if (mounted && generation == _focusRequestGeneration) {
            setState(() => _initialFocusDone = true);
          }
        });
  }

  /// 无动画定位到指定当前句；仅首次定位和页面恢复需要暂时隐藏列表。
  void _focusImmediately({bool hideWhilePositioning = true}) {
    if (!widget.autoFocusEnabled || !widget.focusActive) return;
    final localSentenceIndex = _playingSentenceLocalIndex();
    if (localSentenceIndex == null) return;
    final targetIndex = localSentenceIndex * 2;
    final generation = ++_focusRequestGeneration;
    if (hideWhilePositioning) _hideWhilePositioning();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.autoFocusEnabled ||
          !widget.focusActive ||
          generation != _focusRequestGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0);
      _schedulePositionCorrection(targetIndex, generation);
    });
  }

  void _focusWithPlaybackAnimation() {
    if (!widget.autoFocusEnabled ||
        !widget.focusActive ||
        _userSuspendedFocus) {
      return;
    }
    final localSentenceIndex = _playingSentenceLocalIndex();
    if (localSentenceIndex == null) return;
    final targetIndex = localSentenceIndex * 2;
    final generation = ++_focusRequestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.autoFocusEnabled ||
          !widget.focusActive ||
          _userSuspendedFocus ||
          generation != _focusRequestGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      final position = _targetPosition(targetIndex);
      if (position == null) {
        // 远距离跳转直接定位，避免 scrollTo 的双列表淡入淡出和整段滚动动画。
        _focusImmediately(hideWhilePositioning: false);
        return;
      }
      if (isTargetWellCentered(leadingEdge: position.itemLeadingEdge)) {
        return;
      }
      _itemScrollController.scrollTo(
        index: targetIndex,
        alignment: autoFollowAlignment(targetVisible: true),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didUpdateWidget(covariant ParagraphSentenceListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final playingChanged =
        widget.playingSentenceIndex != oldWidget.playingSentenceIndex;
    final paragraphChanged = _sentenceSequenceChanged(
      oldWidget.sentences,
      widget.sentences,
    );
    final focusReenabled =
        !oldWidget.autoFocusEnabled && widget.autoFocusEnabled;
    final becameFocusActive = !oldWidget.focusActive && widget.focusActive;
    final focusRestoreRequested =
        widget.focusRestoreRevision != oldWidget.focusRestoreRevision;
    final focusRequestChanged =
        widget.focusRequestRevision != null &&
        widget.focusRequestRevision != oldWidget.focusRequestRevision;

    if (!widget.autoFocusEnabled) {
      _resumeFocusTimer?.cancel();
      _userSuspendedFocus = false;
      return;
    }

    if (!widget.focusActive) return;

    if (becameFocusActive || focusRestoreRequested) {
      _userSuspendedFocus = false;
      _focusImmediately(hideWhilePositioning: false);
      return;
    }

    if (focusReenabled) {
      _userSuspendedFocus = false;
      if (widget.focusRequestRevision != null) {
        _focusImmediately();
      } else {
        _focusPlayingSentence();
      }
      return;
    }

    if (paragraphChanged) {
      if (widget.focusRequestRevision != null) {
        _focusImmediately();
      } else if (!_userSuspendedFocus) {
        _focusPlayingSentence();
      }
      return;
    }

    if (playingChanged || focusRequestChanged) {
      if (widget.focusRequestRevision != null &&
          widget.focusReason == SentenceFocusReason.immediate) {
        _focusImmediately(hideWhilePositioning: false);
      } else if (widget.focusRequestRevision != null &&
          widget.focusReason == SentenceFocusReason.navigation) {
        _resumeFocusTimer?.cancel();
        _userSuspendedFocus = false;
        _focusWithPlaybackAnimation();
      } else if (!_userSuspendedFocus && widget.focusRequestRevision != null) {
        _focusWithPlaybackAnimation();
      } else if (!_userSuspendedFocus) {
        _focusPlayingSentence();
      }
    }
  }

  @override
  void dispose() {
    _resumeFocusTimer?.cancel();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.autoFocusEnabled || notification is! UserScrollNotification) {
      return false;
    }

    if (notification.direction == ScrollDirection.idle) {
      if (_userSuspendedFocus) {
        _resumeFocusTimer?.cancel();
        _resumeFocusTimer = Timer(widget.autoFocusResumeDelay, () {
          if (!mounted || !widget.autoFocusEnabled || !widget.focusActive) {
            return;
          }
          _userSuspendedFocus = false;
          if (widget.focusRequestRevision != null &&
              widget.focusReason == SentenceFocusReason.immediate) {
            _focusImmediately(hideWhilePositioning: false);
          } else if (widget.focusRequestRevision != null &&
              widget.focusReason == SentenceFocusReason.navigation) {
            _focusWithPlaybackAnimation();
          } else if (widget.focusRequestRevision != null) {
            _focusWithPlaybackAnimation();
          } else {
            _focusPlayingSentence();
          }
        });
      }
      return false;
    }

    _resumeFocusTimer?.cancel();
    _userSuspendedFocus = true;
    return false;
  }

  /// 自动跟随当前播放句，同时尊重用户手动滚动后的短暂停留。
  ///
  /// 仅用于「播放中逐句推进」的平滑跟随（[didUpdateWidget] / 手动滚动后恢复）。
  /// 「初次定位」（首次进入 / 切 Tab）不走这里，而是由 [initState] /
  /// [_centerInitialFocus] 在列表不可见时完成，再按定位模式淡入或瞬时显出。
  void _focusPlayingSentence() {
    if (!widget.autoFocusEnabled ||
        !widget.focusActive ||
        _userSuspendedFocus) {
      return;
    }
    final localSentenceIndex = _playingSentenceLocalIndex();
    if (localSentenceIndex == null) return;
    final targetIndex = localSentenceIndex * 2;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.autoFocusEnabled ||
          !widget.focusActive ||
          _userSuspendedFocus ||
          !_itemScrollController.isAttached) {
        return;
      }
      final position = _targetPosition(targetIndex);
      if (position == null) {
        // 目标尚未渲染（首次进入恢复进度 / 大跳转）。此时不能直接 scrollTo 居中：
        // 不可见分支会把底层 anchor 设为 alignment，居中会在边界留白。改为先即时
        // jumpTo 到 clamp 安全的 anchor=0 位置把目标渲染出来，下一帧再走可见分支
        // 居中，避免恢复进度时把当前句卡在顶部。
        _itemScrollController.jumpTo(
          index: targetIndex,
          alignment: autoFollowAlignment(targetVisible: false),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusPlayingSentence();
        });
        return;
      }
      // 已大致位于 0.4 锚点附近则不动，否则重新定位——边界句滚到自然边缘被 clamp 硬停。
      if (isTargetWellCentered(leadingEdge: position.itemLeadingEdge)) {
        return;
      }
      _itemScrollController.scrollTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: autoFollowAlignment(targetVisible: true),
      );
    });
  }

  /// 目标元素当前的可见位置；不在可见集合中（大跳转/未渲染）时返回 null。
  ///
  /// 用于：① 判断是否已居中（[isTargetWellCentered]）；② 决定 [scrollTo] 走
  /// 「可见分支」还是「跳转分支」，据此选 alignment（见 [autoFollowAlignment]）。
  ItemPosition? _targetPosition(int targetIndex) {
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index == targetIndex) return position;
    }
    return null;
  }

  int? _playingSentenceLocalIndex() {
    if (widget.sentences.isEmpty || widget.playingSentenceIndex < 0) {
      return null;
    }
    return _clampLocalSentenceIndex(widget.playingSentenceIndex);
  }

  int _clampLocalSentenceIndex(int index) {
    if (index < 0) return 0;
    final lastIndex = widget.sentences.length - 1;
    if (index > lastIndex) return lastIndex;
    return index;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求调用
    final theme = Theme.of(context);
    return Card(
      // 列表贴边铺满：去左右边距与圆角，读作整块内容区而非浮起卡片。
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      child: _buildInitialFocusVisibility(
        NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            initialScrollIndex: _initialScrollIndex,
            // 保持普通列表 anchor，居中校正时边界才会自然贴顶/贴底。
            initialAlignment: 0,
            // 硬停物理：自动跟随滚到自然边界即停，越界被逐帧 clamp，杜绝到头/尾时
            // 的自动回弹（详见 [autoFollowAlignment]）。
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
            itemCount: widget.sentences.isEmpty
                ? 0
                : widget.sentences.length * 2 - 1,
            itemBuilder: (context, index) {
              if (index.isOdd) {
                return Divider(
                  height: 1,
                  indent: AppSpacing.m,
                  endIndent: AppSpacing.m,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                );
              }

              final sentenceIndex = index ~/ 2;
              final sentence = widget.sentences[sentenceIndex];
              final isGuideTarget = widget.guideTargetLocalIdx == sentenceIndex;
              final onSentenceExplanationTap = widget.onSentenceExplanationTap;
              final onSentencePlayFrom = widget.onSentencePlayFrom;
              final onSentenceBookmarkToggle = widget.onSentenceBookmarkToggle;
              return MaskedSentenceTile(
                sentence: sentence,
                displayMode: widget.displayMode,
                keywordIndices: widget.keywordMap[sentence.index] ?? const {},
                isPlayingSentence: sentenceIndex == widget.playingSentenceIndex,
                isBookmarked: widget.bookmarkedSentenceIndices.contains(
                  sentence.index,
                ),
                onDetailTap: onSentenceExplanationTap == null
                    ? null
                    : () => onSentenceExplanationTap(sentence),
                onPlayFromTap: onSentencePlayFrom == null
                    ? null
                    : () => onSentencePlayFrom(sentence),
                onBookmarkTap: onSentenceBookmarkToggle == null
                    ? null
                    : () => onSentenceBookmarkToggle(sentence),
                explanationAreaGuideStep: isGuideTarget
                    ? widget.explanationAreaGuideStep
                    : null,
                bodyAreaGuideStep: isGuideTarget
                    ? widget.bodyAreaGuideStep
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInitialFocusVisibility(Widget child) {
    if (widget.directInitialPositioning) {
      return Opacity(
        key: kParagraphListInitialFocusKey,
        opacity: _initialFocusDone ? 1 : 0,
        child: child,
      );
    }
    return AnimatedOpacity(
      key: kParagraphListInitialFocusKey,
      opacity: _initialFocusDone ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: child,
    );
  }
}
