import 'package:dio/dio.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_paging.dart';
import 'package:echo_loop/features/community_collections/providers/community_collection_detail_provider.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/screens/community_collection_detail_screen.dart';
import 'package:echo_loop/features/community_collections/widgets/community_collection_header.dart';
import 'package:echo_loop/models/collection.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/mock_providers.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('详情失败显示重试按钮且重试后恢复素材列表', (tester) async {
    var attempts = 0;
    final notifier = _RetryFiles(() => ++attempts);
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Example',
                description: null,
                coverUrl: null,
                fileCount: 0,
                publishedAt: DateTime(2026),
                updatedAt: DateTime(2026),
                authorNickname: null,
              ),
            ),
          ),
          communityCollectionFilesProvider(
            'collection-1',
          ).overrideWith(() => notifier),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DioException'), findsNothing);
    await tester.tap(find.text('Failed to load, tap to retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(notifier.refreshForces, [true]);
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

  Future<void> pumpDetail(
    WidgetTester tester, {
    bool subscribed = false,
    _TestCommunityCollectionFiles? detailNotifier,
  }) async {
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Community English',
                description: 'A short collection',
                coverUrl: null,
                authorNickname: 'Echo Studio',
                fileCount: files.length,
                publishedAt: DateTime(2026, 9, 22),
                updatedAt: DateTime(2026, 9, 24, 15, 7),
              ),
            ),
          ),
          if (subscribed)
            collectionListProvider.overrideWith(
              () => TestCollectionList(
                CollectionState(
                  rawCollections: [
                    Collection(
                      id: 'local-1',
                      name: 'Stale local name',
                      createdDate: DateTime(2026, 9, 22),
                      source: CollectionSource.community,
                      remoteId: 'collection-1',
                    ),
                  ],
                  audioIdsMap: const {
                    'local-1': ['local-only-file'],
                  },
                ),
              ),
            ),
          communityCollectionFilesProvider('collection-1').overrideWith(
            () => detailNotifier ?? _TestCommunityCollectionFiles(files),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未加入合集详情显示素材数量和可用时长', (tester) async {
    await pumpDetail(tester);

    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Echo Studio'), findsOneWidget);
    expect(find.text('2026-09-24 15:07'), findsOneWidget);
    expect(find.text('9/22/2026'), findsNothing);
    expect(
      find.ancestor(
        of: find.byType(CommunityCollectionHeader),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(CommunityCollectionHeader)).width,
      closeTo(tester.getSize(find.byType(ListView)).width, 1),
    );
    expect(
      tester.getTopLeft(find.byType(CommunityCollectionHeader)).dy,
      closeTo(tester.getBottomLeft(find.byType(AppBar)).dy, 1),
    );
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('Add to My Collections'), findsOneWidget);
    expect(find.text('0s'), findsNothing);
    expect(
      find.ancestor(of: find.text('Name'), matching: find.byType(ListView)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byType(CommunityCollectionHeader)).dy,
      lessThan(tester.getTopLeft(find.text('Name')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Name')).dy,
      lessThan(tester.getTopLeft(find.text('Track 1')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Name')).dx,
      closeTo(tester.getTopLeft(find.text('Track 1')).dx, 1),
    );
    expect(
      tester.getTopRight(find.text('Duration')).dx,
      closeTo(tester.getTopRight(find.text('1:05')).dx, 1),
    );
  });

  testWidgets('详情接口返回的合集元数据更新信息头部和标题', (tester) async {
    final latest = PublicCollectionCatalogEntry(
      id: 'collection-1',
      name: 'Latest collection name',
      description: 'Latest collection description',
      coverUrl: null,
      authorNickname: 'Latest author',
      fileCount: 9,
      publishedAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 10, 1, 9, 5),
    );
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Stale collection name',
                description: 'Stale description',
                coverUrl: null,
                authorNickname: 'Old author',
                fileCount: 2,
                publishedAt: DateTime(2026, 8, 1),
              ),
            ),
          ),
          communityCollectionFilesProvider(
            'collection-1',
          ).overrideWith(() => _TestCommunityCollectionFiles(files, latest)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Latest collection name'), findsOneWidget);
    expect(find.text('Latest collection description'), findsOneWidget);
    expect(find.text('Latest author'), findsOneWidget);
    expect(find.text('9 items'), findsOneWidget);
    expect(find.text('2026-10-01 09:05'), findsOneWidget);
    expect(find.text('Stale description'), findsNothing);
  });

  testWidgets('未加入合集时点击预览素材不会触发加入操作', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.text('Track 1'));
    await tester.pumpAndSettle();

    expect(find.text('Add Collection First'), findsNothing);
    expect(find.text('Track 1'), findsOneWidget);
  });

  testWidgets('未加入合集详情下拉时强制刷新且缓存内容仍可见', (tester) async {
    final detailNotifier = _TestCommunityCollectionFiles(files);
    await tester.pumpWidget(
      createTestApp(
        const CommunityCollectionDetailScreen(remoteId: 'collection-1'),
        overrides: [
          discoverCommunityCollectionsProvider.overrideWith(
            () => _TestDiscoverCommunityCollections(
              PublicCollectionCatalogEntry(
                id: 'collection-1',
                name: 'Community English',
                description: 'A short collection',
                coverUrl: null,
                authorNickname: 'Echo Studio',
                fileCount: files.length,
                publishedAt: DateTime(2026, 9, 22),
              ),
            ),
          ),
          communityCollectionFilesProvider(
            'collection-1',
          ).overrideWith(() => detailNotifier),
        ],
      ),
    );
    await tester.pumpAndSettle();
    detailNotifier.refreshCalls = 0;
    detailNotifier.forceRefreshCalls = 0;

    await tester.drag(find.byType(ListView), const Offset(0, 320));
    await tester.pumpAndSettle();

    expect(detailNotifier.forceRefreshCalls, 1);
    expect(find.text('Track 1'), findsOneWidget);
  });

  testWidgets('已加入合集详情仍展示公开文件列表，仅底部按钮改为开始学习', (tester) async {
    final detailNotifier = _TestCommunityCollectionFiles(
      files,
      PublicCollectionCatalogEntry(
        id: 'collection-1',
        name: 'Remote public name',
        description: 'Public description',
        coverUrl: null,
        authorNickname: 'Public author',
        fileCount: files.length,
        publishedAt: DateTime(2026, 9, 22),
      ),
    );
    await pumpDetail(tester, subscribed: true, detailNotifier: detailNotifier);

    expect(detailNotifier.buildCalls, greaterThan(0));
    expect(find.text('Remote public name'), findsOneWidget);
    expect(find.text('Stale local name'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('Start Practicing'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Track 1'));
    await tester.pumpAndSettle();
    expect(find.text('Add Collection First'), findsNothing);
    expect(find.text('Track 1'), findsOneWidget);
  });
}

class _RetryFiles extends CommunityCollectionFiles {
  _RetryFiles(this.attempt);
  final int Function() attempt;
  final refreshForces = <bool>[];

  /// 模拟强制刷新后的远端恢复；与上游刷新接口保持一致。
  @override
  Future<void> refresh({bool force = false}) async {
    refreshForces.add(force);
    state = AsyncData(await build('collection-1'));
  }

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

class _TestCommunityCollectionFiles extends CommunityCollectionFiles {
  final List<CommunityCollectionFile> files;
  final PublicCollectionCatalogEntry? collection;
  var buildCalls = 0;
  var refreshCalls = 0;
  var forceRefreshCalls = 0;

  _TestCommunityCollectionFiles(this.files, [this.collection]);

  @override
  Future<CommunityCollectionPagedState<CommunityCollectionFile>> build(
    String collectionId,
  ) async {
    buildCalls++;
    return CommunityCollectionPagedState.fromFirstPage(
      CommunityCollectionCatalogPage(
        cursor: null,
        collection: collection,
        items: files,
        nextCursor: null,
      ),
    );
  }

  @override
  Future<void> refresh({bool force = false}) async {
    refreshCalls++;
    if (force) forceRefreshCalls++;
  }
}
