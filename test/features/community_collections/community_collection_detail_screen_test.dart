import 'package:dio/dio.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_paging.dart';
import 'package:echo_loop/features/community_collections/providers/community_collection_detail_provider.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/screens/community_collection_detail_screen.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mock_providers.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('详情失败显示重试按钮且重试后恢复素材列表', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionSummary(
                id: 'collection-1',
                name: 'Example',
                description: null,
                coverUrl: null,
                fileCount: 0,
                publishedAt: DateTime(2026),
              ),
            ),
          ),
          communityCollectionFilesProvider(
            'collection-1',
          ).overrideWith(() => _RetryFiles(() => ++attempts)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DioException'), findsNothing);
    await tester.tap(find.text('Failed to load, tap to retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('0 items'), findsOneWidget);
    expect(find.text('Failed to load, tap to retry'), findsNothing);
  });
  final files = [
    const CommunityCollectionFile(
      id: 'file-1',
      title: 'Track 1',
      description: null,
      mediaType: CommunityMediaType.audio,
      durationSec: 65,
      fileSizeBytes: null,
      difficulty: null,
      publishedAt: null,
      sortOrder: 0,
      mediaUrl: 'https://example.com/track-1.m4a',
    ),
    const CommunityCollectionFile(
      id: 'file-2',
      title: 'Track 2',
      description: null,
      mediaType: CommunityMediaType.audio,
      durationSec: null,
      fileSizeBytes: null,
      difficulty: null,
      publishedAt: null,
      sortOrder: 1,
      mediaUrl: 'https://example.com/track-2.m4a',
    ),
  ];

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionSummary(
                id: 'collection-1',
                name: 'Community English',
                description: 'A short collection',
                coverUrl: null,
                fileCount: files.length,
                publishedAt: DateTime(2026, 9, 22),
              ),
            ),
          ),
          communityCollectionFilesProvider(
            'collection-1',
          ).overrideWith(() => _TestCommunityCollectionFiles(files)),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未加入合集详情显示素材数量和可用时长', (tester) async {
    await pumpDetail(tester);

    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('0s'), findsNothing);
  });

  testWidgets('未加入合集时点击素材提示先添加合集', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('Track 1'));
    await tester.pumpAndSettle();

    expect(find.text('Add Collection First'), findsOneWidget);
    expect(
      find.text(
        'Add this collection to My Collection, then you can start practicing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add Collection First'), findsNothing);
  });

  testWidgets('已加入合集详情直接使用本地列表，不等待远端文件请求', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionSummary(
                id: 'collection-1',
                name: 'Community English',
                description: 'A short collection',
                coverUrl: null,
                fileCount: 2,
                publishedAt: DateTime(2026, 9, 22),
              ),
            ),
          ),
          collectionListProvider.overrideWith(
            () => TestCollectionList(
              CollectionState(
                rawCollections: [
                  Collection(
                    id: 'local-1',
                    name: 'Community English',
                    createdDate: DateTime(2026, 9, 22),
                    source: CollectionSource.community,
                    remoteId: 'collection-1',
                  ),
                ],
                audioIdsMap: const {'local-1': []},
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 items'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _RetryFiles extends CommunityCollectionFiles {
  _RetryFiles(this.attempt);
  final int Function() attempt;

  @override
  Future<CommunityCollectionPagedState<CommunityCollectionFile>> build(
    String collectionId,
  ) async {
    if (attempt() == 1) {
      final request = RequestOptions(path: '/api/v2/collections/collection-1');
      throw DioException.badResponse(
        statusCode: 404,
        requestOptions: request,
        response: Response<Object?>(requestOptions: request, statusCode: 404),
      );
    }
    return const CommunityCollectionPagedState(pages: []);
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

class _TestCommunityCollectionFiles extends CommunityCollectionFiles {
  final List<CommunityCollectionFile> files;

  _TestCommunityCollectionFiles(this.files);

  @override
  Future<CommunityCollectionPagedState<CommunityCollectionFile>> build(
    String collectionId,
  ) async {
    return CommunityCollectionPagedState.fromFirstPage(
      CommunityCollectionCatalogPage(
        cursor: null,
        items: files,
        nextCursor: null,
      ),
    );
  }
}
