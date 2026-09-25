import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/podcast/models/podcast_catalog.dart';
import 'package:echo_loop/features/podcast/podcast_preview_provider.dart';
import 'package:echo_loop/features/podcast/podcast_models.dart';
import 'package:echo_loop/features/podcast/podcast_repository.dart';
import 'package:echo_loop/features/podcast/podcast_search_provider.dart';
import 'package:echo_loop/features/podcast/podcast_search_service.dart';
import 'package:echo_loop/features/podcast/providers/discover_podcasts_provider.dart';
import 'package:echo_loop/features/podcast/screens/podcast_discovery_screen.dart';
import 'package:echo_loop/features/podcast/widgets/podcast_subscribe_tile.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mock_providers.dart';
import '../../helpers/test_app.dart';

class _FakeSearchService extends PodcastSearchService {
  _FakeSearchService(this.results);

  final List<PodcastSearchResult> results;
  String? lastTerm;

  @override
  Future<List<PodcastSearchResult>> search(
    String term, {
    int limit = 25,
  }) async {
    lastTerm = term;
    return results;
  }
}

class _FakePodcastRepository extends Fake implements PodcastRepository {
  final List<String> subscribed = [];
  final List<String?> knownFeedUrls = [];

  @override
  Future<Collection> createAndFetch(
    String inputUrl, {
    String? knownFeedUrl,
  }) async {
    subscribed.add(inputUrl);
    knownFeedUrls.add(knownFeedUrl);
    return Collection(
      id: 'subscribed',
      name: 'Subscribed',
      createdDate: DateTime(2026, 1, 1),
      source: CollectionSource.podcast,
      podcastInputUrl: inputUrl,
      podcastFeedUrl: knownFeedUrl ?? inputUrl,
    );
  }
}

PodcastCatalogItem _featuredPodcast({
  String id = 'featured-1',
  String title = 'Featured English',
  String applePodcastUrl = '',
  String rssUrl = 'https://example.com/feed.xml',
}) => PodcastCatalogItem(
  id: id,
  applePodcastUrl: applePodcastUrl,
  rssUrl: rssUrl,
  imageUrl: null,
  title: title,
  description: 'Short English lessons',
);

void main() {
  testWidgets('空搜索词展示精选目录空态，不加载 Apple 搜索', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [discoverPodcastsProvider.overrideWithValue(const [])],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No curated podcasts yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('空搜索词恢复展示精选 Podcast', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue([
            const PodcastCatalogItem(
              id: 'featured-1',
              applePodcastUrl: 'https://podcasts.apple.com/example',
              rssUrl: 'https://example.com/feed.xml',
              imageUrl: null,
              title: 'Featured English',
              description: 'Short English lessons',
            ),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Featured English'), findsOneWidget);
    expect(find.text('Short English lessons'), findsOneWidget);
    expect(find.text('Search podcasts or paste a link'), findsOneWidget);
  });

  testWidgets('精选 Podcast 订阅优先使用 Apple URL 且停留在本页', (tester) async {
    final fakeRepo = _FakePodcastRepository();
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue([
            _featuredPodcast(
              applePodcastUrl: 'https://podcasts.apple.com/example',
            ),
          ]),
          isAuthenticatedProvider.overrideWithValue(true),
          podcastRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    expect(fakeRepo.subscribed, ['https://podcasts.apple.com/example']);
    expect(fakeRepo.knownFeedUrls, ['https://example.com/feed.xml']);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Added to My Collections'), findsWidgets);
  });

  testWidgets('已订阅的精选 Podcast 显示静态对勾而不是去学习', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue([_featuredPodcast()]),
          collectionListProvider.overrideWith(
            () => TestCollectionList(
              CollectionState(
                rawCollections: [
                  Collection(
                    id: 'existing',
                    name: 'Existing Podcast',
                    createdDate: DateTime(2026, 1, 1),
                    source: CollectionSource.podcast,
                    podcastFeedUrl: 'https://example.com/feed.xml',
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
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Start Practicing'), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);

    final tileRect = tester.getRect(find.byType(PodcastSubscribeTile));
    final badgeRect = tester.getRect(find.text('Added'));
    final checkRect = tester.getRect(
      find.byIcon(Icons.check_circle_outline_rounded),
    );
    expect(badgeRect.top, greaterThanOrEqualTo(tileRect.top));
    expect(badgeRect.bottom, lessThan(checkRect.top));
  });

  testWidgets('未登录订阅精选 Podcast 显示登录提示且不调用仓库', (tester) async {
    final fakeRepo = _FakePodcastRepository();
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue([_featuredPodcast()]),
          isAuthenticatedProvider.overrideWithValue(false),
          podcastRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fakeRepo.subscribed, isEmpty);
  });

  testWidgets('进入页面时搜索框不会自动聚焦', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [discoverPodcastsProvider.overrideWithValue(const [])],
      ),
    );
    await tester.pumpAndSettle();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isFalse);
  });

  testWidgets('输入关键词展示 Apple 搜索结果', (tester) async {
    final fakeSearch = _FakeSearchService([
      const PodcastSearchResult(
        id: 's1',
        title: 'BBC Global News',
        author: 'BBC',
        feedUrl: 'https://feeds.bbc.co.uk/news.xml',
      ),
    ]);
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue(const []),
          podcastSearchServiceProvider.overrideWithValue(fakeSearch),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bbc');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('BBC Global News'), findsOneWidget);
    expect(fakeSearch.lastTerm, 'bbc');
  });

  testWidgets('输入链接解析为可订阅 item', (tester) async {
    const url = 'https://example.com/feed.xml';
    await tester.pumpWidget(
      createTestApp(
        const PodcastDiscoveryScreen(),
        overrides: [
          discoverPodcastsProvider.overrideWithValue(const []),
          podcastPreviewProvider(url).overrideWith(
            (ref) async => const PodcastPreviewData(
              meta: PodcastFeedMeta(
                title: 'Example Cast',
                feedUrl: url,
                author: 'Example Author',
              ),
              episodes: [],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), url);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Example Cast'), findsOneWidget);
    expect(find.text('Subscribe to this link'), findsNothing);
  });
}
