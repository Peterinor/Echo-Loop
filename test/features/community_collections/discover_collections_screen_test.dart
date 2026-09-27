import 'package:flutter/material.dart';
import 'package:echo_loop/features/community_collections/data/community_sync_service.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_paging.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/screens/discover_collections_screen.dart';
import 'package:echo_loop/features/podcast/data/podcast_catalog_service.dart';
import 'package:echo_loop/features/podcast/models/podcast_catalog.dart';
import 'package:echo_loop/features/podcast/providers/discover_podcasts_provider.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_app.dart';
import '../../helpers/mock_providers.dart';

void main() {
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

  testWidgets('发现页下拉只强制刷新社区合集目录', (tester) async {
    final catalogProvider = _TestDiscoverCommunityCollections(
      PublicCollectionCatalogEntry(
        id: 'collection-1',
        name: 'Community Collection',
        description: null,
        coverUrl: null,
        fileCount: 1,
        publishedAt: DateTime(2026, 1, 1),
      ),
      extraEntries: List.generate(
        12,
        (index) => PublicCollectionCatalogEntry(
          id: 'collection-$index',
          name: 'Community Collection $index',
          description: null,
          coverUrl: null,
          fileCount: 1,
          publishedAt: DateTime(2026, 1, 1),
        ),
      ),
    );
    final syncService = _MockCommunitySyncService();
    final podcastService = _MockPodcastCatalogService();
    when(() => syncService.syncAll(force: true)).thenAnswer(
      (_) async => const CommunitySyncCompleted(
        collectionsScanned: 0,
        collectionsDeprecated: 0,
        collectionsUndeprecated: 0,
        filesAdded: 0,
        filesRemoved: 0,
      ),
    );
    when(
      () => podcastService.refresh(force: true),
    ).thenAnswer((_) async => const PodcastCatalogUnchanged());

    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => catalogProvider,
          ),
          discoverPodcastsProvider.overrideWithValue(const []),
          communitySyncServiceProvider.overrideWithValue(syncService),
          podcastCatalogServiceProvider.overrideWithValue(podcastService),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final callsBeforePull = catalogProvider.refreshCalls;

    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(catalogProvider.refreshCalls, callsBeforePull + 1);
    expect(catalogProvider.refreshForces.last, isTrue);
    verifyNever(() => syncService.syncAll(force: any(named: 'force')));
    verifyNever(() => podcastService.refresh(force: any(named: 'force')));
  });
}

class _TestDiscoverCommunityCollections extends DiscoverCommunityCollections {
  final PublicCollectionCatalogEntry catalogEntry;
  final List<PublicCollectionCatalogEntry> extraEntries;
  int refreshCalls = 0;
  final List<bool> refreshForces = [];

  _TestDiscoverCommunityCollections(
    this.catalogEntry, {
    this.extraEntries = const [],
  });

  @override
  Future<CommunityCollectionPagedState<PublicCollectionCatalogEntry>>
  build() async {
    return CommunityCollectionPagedState.fromFirstPage(
      CommunityCollectionCatalogPage(
        cursor: null,
        items: [catalogEntry, ...extraEntries],
        nextCursor: null,
      ),
    );
  }

  @override
  Future<void> refresh({bool force = false}) async {
    refreshCalls++;
    refreshForces.add(force);
  }
}

class _MockCommunitySyncService extends Mock implements CommunitySyncService {}

class _MockPodcastCatalogService extends Mock
    implements PodcastCatalogService {}
