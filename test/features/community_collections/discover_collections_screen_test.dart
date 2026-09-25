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
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
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
              PublicCollectionSummary(
                id: 'collection-1',
                name: 'Public resource',
                description: null,
                coverUrl: null,
                fileCount: 1,
                publishedAt: DateTime(2026),
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
