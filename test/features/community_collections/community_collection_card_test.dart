import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/widgets/community_collection_card.dart';
import 'package:echo_loop/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  final item = PublicCollectionCatalogEntry(
    id: 'collection-1',
    name: 'Shared collection',
    description: null,
    coverUrl: null,
    fileCount: 1,
    publishedAt: DateTime(2026, 1, 1),
  );

  testWidgets('已加入状态显示不可点击的绿色圆形对勾，且详情仍可打开', (tester) async {
    var detailTapCount = 0;

    await tester.pumpWidget(
      createTestApp(
        Scaffold(
          body: CommunityCollectionCard(
            item: item,
            enrolled: true,
            enrolling: false,
            onOpenDetail: () => detailTapCount++,
            onEnroll: () {},
          ),
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已添加'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '已添加',
      ),
      findsOneWidget,
    );
    expect(find.text('去学习'), findsNothing);
    final checkFinder = find.byIcon(Icons.check_circle_outline_rounded);
    final check = tester.widget<Icon>(checkFinder);
    expect(check.color, AppTheme.successColor);

    final cardRect = tester.getRect(find.byType(CommunityCollectionCard));
    final checkRect = tester.getRect(checkFinder);
    expect(checkRect.center.dy, closeTo(cardRect.center.dy, 1));
    expect(checkRect.center.dx, greaterThan(cardRect.center.dx));

    await tester.tap(checkFinder);
    await tester.pump();
    expect(detailTapCount, 0);

    await tester.tap(find.text('Shared collection'));
    await tester.pump();
    expect(detailTapCount, 1);
  });

  testWidgets('未加入合集仍显示添加入口', (tester) async {
    var enrollTapCount = 0;

    await tester.pumpWidget(
      createTestApp(
        Scaffold(
          body: CommunityCollectionCard(
            item: item,
            enrolled: false,
            enrolling: false,
            onOpenDetail: () {},
            onEnroll: () => enrollTapCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.text('Added'), findsNothing);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(enrollTapCount, 1);
  });

  testWidgets('已加入与未加入图标尺寸和右侧边距一致', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommunityCollectionCard(
                key: const ValueKey('enrolled-card'),
                item: item,
                enrolled: true,
                enrolling: false,
                onOpenDetail: () {},
                onEnroll: () {},
              ),
              CommunityCollectionCard(
                key: const ValueKey('not-enrolled-card'),
                item: item,
                enrolled: false,
                enrolling: false,
                onOpenDetail: () {},
                onEnroll: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('enrolled-card')),
        matching: find.byIcon(Icons.check_circle_outline_rounded),
      ),
    );
    final addRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('not-enrolled-card')),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    final enrolledCardRect = tester.getRect(
      find.byKey(const ValueKey('enrolled-card')),
    );
    final notEnrolledCardRect = tester.getRect(
      find.byKey(const ValueKey('not-enrolled-card')),
    );

    expect(checkRect.size, addRect.size);
    expect(
      enrolledCardRect.right - checkRect.center.dx,
      closeTo(notEnrolledCardRect.right - addRect.center.dx, 1),
    );
  });

  testWidgets('英文已加入状态通过无障碍标签说明为 Added', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        Scaffold(
          body: CommunityCollectionCard(
            item: item,
            enrolled: true,
            enrolling: false,
            onOpenDetail: () {},
            onEnroll: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Added'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Added',
      ),
      findsOneWidget,
    );
    expect(find.text('Start Practicing'), findsNothing);
  });
}
