import 'package:echo_loop/config/app_capabilities.dart';
import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/community_collections/providers/community_enrollment_provider.dart';
import 'package:echo_loop/features/community_collections/widgets/community_collection_card.dart';
import 'package:flutter/material.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_paging.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/screens/discover_collections_screen.dart';
import 'package:echo_loop/features/podcast/models/podcast_catalog.dart';
import 'package:echo_loop/features/podcast/providers/discover_podcasts_provider.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import '../../helpers/mock_providers.dart';

void main() {
  for (final catalog in <List<PodcastCatalogItem>?>[null, const []]) {
    for (final failCommunity in [false, true]) {
      testWidgets('Podcast 入口不依赖精选目录 $catalog 或合集成功 ${!failCommunity}', (
        tester,
      ) async {
        await tester.pumpWidget(
          createTestApp(
            const DiscoverCommunityCollectionsScreen(),
            overrides: [
              discoverPodcastsProvider.overrideWithValue(catalog),
              discoverCommunityCollectionsProvider.overrideWith(
                () => _EmptyDiscover(failCommunity),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Apple Podcasts'), findsOneWidget);
      });
    }
  }
  testWidgets('匿名加入合集：本地版直接加入，官方版仍要求登录', (tester) async {
    final enrollment = _TestEnrollment();
    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        overrides: [
          isAuthenticatedProvider.overrideWithValue(false),
          discoverPodcastsProvider.overrideWithValue(const []),
          communityEnrollmentProvider.overrideWith(() => enrollment),
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Public resource',
                description: null,
                coverUrl: null,
                fileCount: 1,
                publishedAt: DateTime(2026),
                updatedAt: DateTime(2026),
                authorNickname: null,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CommunityCollectionCard),
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(enrollment.enrolled, isLocalEdition ? ['collection-1'] : isEmpty);
    expect(
      find.byType(AlertDialog),
      isLocalEdition ? findsNothing : findsOneWidget,
    );
  });
  testWidgets('中文发现页标题显示发现资源', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        locale: const Locale('zh'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: '共享合集',
                description: null,
                coverUrl: null,
                fileCount: 1,
                publishedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
          discoverPodcastsProvider.overrideWithValue(const []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现资源'), findsOneWidget);
  });

  testWidgets('已加入的社区合集显示圆形对勾和已添加角标', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        locale: const Locale('zh'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: '共享合集',
                description: null,
                coverUrl: null,
                fileCount: 1,
                publishedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
          discoverPodcastsProvider.overrideWithValue(const []),
          collectionListProvider.overrideWith(
            () => TestCollectionList(
              CollectionState(
                rawCollections: [
                  Collection(
                    id: 'local-collection-1',
                    name: '共享合集',
                    createdDate: DateTime(2026, 1, 1),
                    source: CollectionSource.community,
                    remoteId: 'collection-1',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('去学习'), findsNothing);
  });

  testWidgets('/discover 始终显示 Podcast 搜索入口', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Community Collection',
                description: null,
                coverUrl: null,
                fileCount: 1,
                publishedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
          discoverPodcastsProvider.overrideWithValue([
            const PodcastCatalogItem(
              id: 'podcast-1',
              applePodcastUrl: 'https://podcasts.apple.com/example',
              rssUrl: 'https://example.com/feed.xml',
              imageUrl: null,
              title: 'Featured podcast',
              description: null,
            ),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discover Resources'), findsOneWidget);
    expect(find.text('Apple Podcasts'), findsOneWidget);
    expect(find.text('Search podcasts'), findsNothing);
  });
}

class _TestDiscoverCommunityCollections extends DiscoverCommunityCollections {
  final PublicCollectionCatalogEntry catalogEntry;

  _TestDiscoverCommunityCollections(this.catalogEntry);

  @override
  Future<CommunityCollectionPagedState<PublicCollectionCatalogEntry>>
  build() async {
    return CommunityCollectionPagedState.fromFirstPage(
      CommunityCollectionCatalogPage(
        cursor: null,
        items: [catalogEntry],
        nextCursor: null,
      ),
    );
  }
}

class _EmptyDiscover extends DiscoverCommunityCollections {
  _EmptyDiscover(this.failCommunity);
  final bool failCommunity;

  @override
  Future<CommunityCollectionPagedState<PublicCollectionCatalogEntry>>
  build() async {
    if (failCommunity) throw StateError('catalog offline');
    return const CommunityCollectionPagedState(pages: []);
  }
}

class _TestEnrollment extends CommunityEnrollment {
  final enrolled = <String>[];
  @override
  Future<CommunityEnrollResult> enroll(String remoteId) async {
    enrolled.add(remoteId);
    return const CommunityEnrollResult(
      localCollectionId: 'local-1',
      createdNew: true,
    );
  }
}
