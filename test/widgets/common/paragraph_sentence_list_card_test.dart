/// [ParagraphSentenceListCard] 自动跟随滚动行为测试
///
/// 重点验证到头/尾时不再自动越界回弹（用 ClampingScrollPhysics 硬停）：
/// - 末句贴底、首句贴顶，无大片留白（非居中）；
/// - 自动滚动过程中滚动位置始终落在 [min, max] 区间内（不越界）；
/// - [autoFollowAlignment] 纯函数的锚点决策。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:echo_loop/models/retell_settings.dart';
import 'package:echo_loop/models/sentence_focus_reason.dart';
import 'package:echo_loop/providers/saved_word_provider.dart';
import 'package:echo_loop/utils/saved_text_index.dart';
import 'package:echo_loop/widgets/common/masked_sentence_tile.dart';
import 'package:echo_loop/widgets/common/paragraph_sentence_list_card.dart';

import '../../helpers/shared/test_fixtures.dart';

void main() {
  group('autoFollowAlignment', () {
    test('目标可见 → 0.4（与首次定位一致）', () {
      expect(autoFollowAlignment(targetVisible: true), 0.4);
    });

    test('目标不可见 → 0.0（保持 anchor 0，避免留白）', () {
      expect(autoFollowAlignment(targetVisible: false), 0.0);
    });
  });

  group('isTargetWellCentered', () {
    test('leading edge 位于 0.4 锚点 → 已定位', () {
      expect(isTargetWellCentered(leadingEdge: 0.4), isTrue);
    });

    test('leading edge 在容差带内 → 已居中', () {
      expect(isTargetWellCentered(leadingEdge: 0.4 + 0.05), isTrue);
      expect(isTargetWellCentered(leadingEdge: 0.4 - 0.05), isTrue);
    });

    test('0.5 位置不再视作已定位于 0.4 锚点', () {
      expect(isTargetWellCentered(leadingEdge: 0.5), isFalse);
    });

    test('leading edge 越出容差带 → 需重新居中', () {
      // 逐句下移漂移到底部：leading edge 偏大，应触发重新居中。
      expect(isTargetWellCentered(leadingEdge: 0.7), isFalse);
      // 贴顶：leading edge 接近 0，应触发重新居中。
      expect(isTargetWellCentered(leadingEdge: 0.0), isFalse);
    });
  });

  group('ParagraphSentenceListCard 自动跟随', () {
    const sentenceCount = 24;

    // 在固定高度容器内构建列表，强制内容溢出以产生滚动空间。
    Widget buildHost({
      required int playingIndex,
      bool directInitialPositioning = false,
      bool focusActive = true,
      int? focusRequestRevision,
      SentenceFocusReason? focusReason,
      int focusRestoreRevision = 0,
    }) {
      // MaskedSentenceTile 监听收藏索引 provider，需要 ProviderScope；
      // 收藏标记与滚动行为无关，固定为空索引。
      return ProviderScope(
        overrides: [
          savedTextIndexProvider.overrideWithValue(
            const SavedTextIndex.empty(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 220,
                child: ParagraphSentenceListCard(
                  sentences: createTestSentences(count: sentenceCount),
                  displayMode: RetellDisplayMode.showAll,
                  keywordMap: const {},
                  playingSentenceIndex: playingIndex,
                  autoFocusEnabled: true,
                  focusActive: focusActive,
                  focusRequestRevision: focusRequestRevision,
                  focusReason: focusReason,
                  focusRestoreRevision: focusRestoreRevision,
                  directInitialPositioning: directInitialPositioning,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 列表视口矩形。
    Rect viewportRect(WidgetTester tester) =>
        tester.getRect(find.byType(ScrollablePositionedList));

    // 指定句子对应的 tile 矩形（须在屏内已构建）。
    Rect tileRect(WidgetTester tester, int sentenceIndex) {
      final finder = find.byWidgetPredicate(
        (w) => w is MaskedSentenceTile && w.sentence.index == sentenceIndex,
      );
      expect(finder, findsOneWidget, reason: '第 $sentenceIndex 句应已渲染在屏内');
      return tester.getRect(finder);
    }

    // 边界容差：内边距(8) + 分隔线 + 行高取整。
    const edgeTol = 24.0;

    testWidgets('末句：贴底停住，不居中留白', (tester) async {
      await tester.pumpWidget(buildHost(playingIndex: sentenceCount - 1));
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final last = tileRect(tester, sentenceCount - 1);
      // 末句底边贴近视口底边（而非居中：居中时底边会落在视口中部）。
      expect(
        last.bottom,
        closeTo(list.bottom, edgeTol),
        reason: '最后一句应贴底，下方无大片留白',
      );
      expect(last.bottom, lessThanOrEqualTo(list.bottom + 1));
    });

    testWidgets('首句：贴顶停住', (tester) async {
      // 先定位到末句，再切回首句，制造一次向上的自动跟随。
      await tester.pumpWidget(buildHost(playingIndex: sentenceCount - 1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(buildHost(playingIndex: 0));
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final first = tileRect(tester, 0);
      expect(first.top, closeTo(list.top, edgeTol), reason: '第一句应贴顶，上方无留白');
      expect(first.top, greaterThanOrEqualTo(list.top - 1));
    });

    testWidgets('首次进入恢复进度：中部句居中，不卡在顶部', (tester) async {
      // 直接以中部句进入（模拟恢复进度），目标句首帧未渲染。
      const restored = sentenceCount ~/ 2;
      await tester.pumpWidget(buildHost(playingIndex: restored));
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final tile = tileRect(tester, restored);
      final viewportCenter = list.center.dy;
      final tileCenter = tile.center.dy;
      // 中部句应落在视口中段，而非贴顶。
      expect(tile.top, greaterThan(list.top + 24), reason: '恢复进度的中部句不应贴在顶部');
      expect(
        (tileCenter - viewportCenter).abs(),
        lessThan(list.height / 2),
        reason: '中部句中心应靠近视口中心',
      );
    });

    testWidgets('初次定位：居中完成前隐藏、完成后淡入且已居中（无可见滚动）', (tester) async {
      // 初次定位（首次进入 / 切 Tab）应在「列表不可见」时把目标句滚到中部，
      // 用户看不到从顶部到中部的滚动；完成后才淡入显示，等同「直接显示在中间」。
      const restored = sentenceCount ~/ 2;
      await tester.pumpWidget(buildHost(playingIndex: restored));

      double opacity() => tester
          .widget<AnimatedOpacity>(find.byKey(kParagraphListInitialFocusKey))
          .opacity;

      // 居中完成前列表隐藏（滚动过程不可见）。
      await tester.pump();
      expect(opacity(), 0, reason: '居中完成前列表应隐藏，滚动过程不可见');

      // 完成并淡入后：可见且目标句紧贴视口中心、不贴顶。
      await tester.pumpAndSettle();
      expect(opacity(), 1, reason: '居中完成后列表应淡入可见');
      final list = viewportRect(tester);
      final tile = tileRect(tester, restored);
      expect(tile.top, greaterThan(list.top + 24), reason: '中部句应居中而非贴顶');
      expect(
        (tile.center.dy - list.center.dy).abs(),
        lessThan(24),
        reason: '中部句中心应紧贴视口中心',
      );
    });

    testWidgets('直接初始定位：首帧已按 0.4 顶边锚点显示中间句', (tester) async {
      const selectedIndex = sentenceCount ~/ 2;
      await tester.pumpWidget(
        buildHost(playingIndex: selectedIndex, directInitialPositioning: true),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(kParagraphListInitialFocusKey))
            .opacity,
        0,
        reason: '定位完成前列表应保持不可见',
      );
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final selected = tileRect(tester, selectedIndex);
      expect(
        selected.top,
        closeTo(list.top + list.height * 0.4, 3),
        reason: '直接定位应在首次绘制时将目标句顶边放在视口约 40% 处',
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(kParagraphListInitialFocusKey))
            .opacity,
        1,
        reason: '定位完成后应瞬时显示，不经过淡入动画',
      );
    });

    testWidgets('直接初始定位：靠近开头时自然贴顶', (tester) async {
      await tester.pumpWidget(
        buildHost(playingIndex: 1, directInitialPositioning: true),
      );
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final first = tileRect(tester, 0);
      expect(first.top, closeTo(list.top, edgeTol));
      expect(first.top, greaterThanOrEqualTo(list.top - 1));
    });

    testWidgets('直接初始定位：靠近结尾时自然贴底', (tester) async {
      await tester.pumpWidget(
        buildHost(
          playingIndex: sentenceCount - 2,
          directInitialPositioning: true,
        ),
      );
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final last = tileRect(tester, sentenceCount - 1);
      expect(last.bottom, closeTo(list.bottom, edgeTol));
      expect(last.bottom, lessThanOrEqualTo(list.bottom + 1));
    });

    testWidgets('播放中自动跟随：目标句移动到 0.4 锚点', (tester) async {
      const initialIndex = 5;
      const selectedIndex = 6;
      await tester.pumpWidget(
        buildHost(
          playingIndex: initialIndex,
          directInitialPositioning: true,
          focusRequestRevision: 1,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      await tester.pumpAndSettle();

      // 自然播放推进时使用短动画，随后落在与首次定位相同的 0.4 锚点。
      await tester.pumpWidget(
        buildHost(
          playingIndex: selectedIndex,
          directInitialPositioning: true,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.playback,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final listDuringAnimation = viewportRect(tester);
      final selectedDuringAnimation = tileRect(tester, selectedIndex);
      expect(
        selectedDuringAnimation.top,
        isNot(
          closeTo(
            listDuringAnimation.top + listDuringAnimation.height * 0.4,
            3,
          ),
        ),
        reason: '播放中自动聚焦应保留短动画过程',
      );
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      final selected = tileRect(tester, selectedIndex);
      expect(
        selected.top,
        closeTo(list.top + list.height * 0.4, 3),
        reason: '播放中自动跟随应与首次定位使用相同的 0.4 顶边锚点',
      );
    });

    testWidgets('列表不活动时忽略播放变化，重新活动后立即定位最新句', (tester) async {
      await tester.pumpWidget(
        buildHost(
          playingIndex: 5,
          directInitialPositioning: true,
          focusRequestRevision: 1,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        buildHost(
          playingIndex: 9,
          directInitialPositioning: true,
          focusActive: false,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.playback,
        ),
      );
      final list = viewportRect(tester);
      final oldTile = tileRect(tester, 5);
      expect(oldTile.top, closeTo(list.top + list.height * 0.4, 3));

      await tester.pumpWidget(
        buildHost(
          playingIndex: 9,
          directInitialPositioning: true,
          focusActive: true,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.playback,
          focusRestoreRevision: 1,
        ),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(kParagraphListInitialFocusKey))
            .opacity,
        1,
        reason: '列表恢复定位时保持可见',
      );
      await tester.pumpAndSettle();

      final restoredList = viewportRect(tester);
      final latestTile = tileRect(tester, 9);
      expect(
        latestTile.top,
        closeTo(restoredList.top + restoredList.height * 0.4, 3),
      );
    });

    testWidgets('显式切句时列表保持可见并平滑聚焦', (tester) async {
      await tester.pumpWidget(
        buildHost(
          playingIndex: 5,
          directInitialPositioning: true,
          focusRequestRevision: 1,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        buildHost(
          playingIndex: 6,
          directInitialPositioning: true,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.navigation,
        ),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(kParagraphListInitialFocusKey))
            .opacity,
        1,
        reason: '切句时不应先隐藏字幕列表',
      );
      await tester.pump(const Duration(milliseconds: 100));
      final list = viewportRect(tester);
      final selected = tileRect(tester, 6);
      expect(selected.top, isNot(closeTo(list.top + list.height * 0.4, 3)));

      await tester.pumpAndSettle();
      final settledList = viewportRect(tester);
      expect(
        tileRect(tester, 6).top,
        closeTo(settledList.top + settledList.height * 0.4, 3),
      );
    });

    testWidgets('进度 seek 直接定位且列表保持可见', (tester) async {
      await tester.pumpWidget(
        buildHost(
          playingIndex: 5,
          directInitialPositioning: true,
          focusRequestRevision: 1,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        buildHost(
          playingIndex: 14,
          directInitialPositioning: true,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      expect(
        tester
            .widget<Opacity>(find.byKey(kParagraphListInitialFocusKey))
            .opacity,
        1,
        reason: 'seek 后保持列表可见，直接切换到目标句',
      );
      await tester.pumpAndSettle();

      final list = viewportRect(tester);
      expect(
        tileRect(tester, 14).top,
        closeTo(list.top + list.height * 0.4, 3),
      );
    });

    testWidgets('播放焦点远距离跳转到末句时不播放跨列表滚动', (tester) async {
      await tester.pumpWidget(
        buildHost(
          playingIndex: 0,
          directInitialPositioning: true,
          focusRequestRevision: 1,
          focusReason: SentenceFocusReason.immediate,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        buildHost(
          playingIndex: sentenceCount - 1,
          directInitialPositioning: true,
          focusRequestRevision: 2,
          focusReason: SentenceFocusReason.playback,
        ),
      );
      await tester.pumpAndSettle();
      final list = viewportRect(tester);
      final last = tileRect(tester, sentenceCount - 1);
      expect(
        last.bottom,
        closeTo(list.bottom, edgeTol),
        reason: '远距离切到末句时应直接定位，不经过整列表滚动动画',
      );
    });

    testWidgets('自动跟随到末句过程中：滚动位置始终不越界（防回弹回归）', (tester) async {
      await tester.pumpWidget(buildHost(playingIndex: 0));
      await tester.pumpAndSettle();

      // 触发到末句的自动跟随，逐帧推进动画。ClampingScrollPhysics 下任一可滚动
      // 列表的位置都不应越过自身 [min, max]；越界即说明发生了回弹。
      await tester.pumpWidget(buildHost(playingIndex: sentenceCount - 1));
      const eps = 0.5;
      var checkedFrames = 0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final positions = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .map((s) => s.position)
            .where((p) => p.hasContentDimensions);
        for (final pos in positions) {
          expect(
            pos.pixels,
            greaterThanOrEqualTo(pos.minScrollExtent - eps),
            reason: '第 $i 帧越过了顶部边界（出现回弹）',
          );
          expect(
            pos.pixels,
            lessThanOrEqualTo(pos.maxScrollExtent + eps),
            reason: '第 $i 帧越过了底部边界（出现回弹）',
          );
          checkedFrames++;
        }
      }
      expect(checkedFrames, greaterThan(0), reason: '应至少检查到若干帧的滚动位置');
      await tester.pumpAndSettle();
    });
  });
}
