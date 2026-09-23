import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_paging.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/screens/discover_collections_screen.dart';
import 'package:echo_loop/features/podcast/models/podcast_catalog.dart';
import 'package:echo_loop/features/podcast/providers/discover_podcasts_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('/discover 始终显示 Podcast 搜索入口', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const DiscoverCommunityCollectionsScreen(),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionSummary(
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

    expect(find.text('Apple Podcasts'), findsOneWidget);
    expect(find.text('Search podcasts'), findsNothing);
  });
}

class _TestDiscoverCommunityCollections extends DiscoverCommunityCollections {
  final PublicCollectionSummary summary;

  _TestDiscoverCommunityCollections(this.summary);

  @override
  Future<CommunityCollectionPagedState<PublicCollectionSummary>> build() async {
    return CommunityCollectionPagedState.fromFirstPage(
      CommunityCollectionCatalogPage(
        cursor: null,
        items: [summary],
        nextCursor: null,
      ),
    );
  }
}
