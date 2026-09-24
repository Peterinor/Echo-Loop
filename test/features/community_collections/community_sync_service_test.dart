import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/features/community_collections/data/community_collection_api.dart';
import 'package:echo_loop/features/community_collections/data/community_sync_service.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCommunityApi extends CommunityCollectionApi {
  _FakeCommunityApi(this.catalogEntries, this.filesByCollection, {this.failId})
    : super.withDio(Dio());

  final List<PublicCollectionCatalogEntry> catalogEntries;
  final Map<String, List<CommunityCollectionFile>> filesByCollection;
  final String? failId;
  var collectionsCalls = 0;
  final detailCalls = <String>[];

  @override
  Future<PublicCollectionPage> getCollections({
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    collectionsCalls++;
    return PublicCollectionPage(items: catalogEntries, nextCursor: null);
  }

  @override
  Future<CommunityCollectionDetailPage> getCollectionDetail(
    String collectionId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    detailCalls.add(collectionId);
    if (collectionId == failId) {
      throw StateError('collection failed: $collectionId');
    }
    return CommunityCollectionDetailPage(
      collection: catalogEntries.firstWhere((item) => item.id == collectionId),
      items: filesByCollection[collectionId] ?? const [],
      nextCursor: null,
    );
  }
}

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('一个合集请求失败不会阻止其它已订阅合集更新', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    await _insertCollection(database, 'local-2', 'remote-2', 'Two');
    await _insertFile(database, 'local-1', 'file-1', 'Old one');
    await _insertFile(database, 'local-2', 'file-2', 'Old two');

    final api = _FakeCommunityApi(
      [_catalogEntry('remote-1', 'One'), _catalogEntry('remote-2', 'Two')],
      {
        'remote-2': [_file('file-2', 'Updated two')],
      },
      failId: 'remote-1',
    );
    final service = CommunitySyncService(database: database, api: api);

    final outcome = await service.syncAll(force: true);
    final updated = await database.audioItemDao.getByRemoteAudioId('file-2');

    expect(outcome, isA<CommunitySyncCompleted>());
    final completed = outcome as CommunitySyncCompleted;
    expect(completed.failedCollections, 1);
    expect(updated?.name, 'Updated two');
    expect(api.collectionsCalls, 0);
    expect(api.detailCalls, unorderedEquals(['remote-1', 'remote-2']));
  });

  test('已加入合集从详情接口判断下架，不依赖公开合集目录', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    final api = _NotFoundCommunityApi();

    final outcome = await CommunitySyncService(
      database: database,
      api: api,
    ).syncAll(force: true);

    final collection = await (database.select(
      database.collections,
    )..where((row) => row.id.equals('local-1'))).getSingle();
    expect(outcome, isA<CommunitySyncCompleted>());
    expect(collection.deprecatedAt, isNotNull);
    expect(api.collectionsCalls, 0);
    expect(api.detailCalls, ['remote-1']);
  });

  test('已有文件的远端空时长不会覆盖本地时长', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    await _insertFile(database, 'local-1', 'file-1', 'Old one', duration: 42);

    final api = _FakeCommunityApi(
      [_catalogEntry('remote-1', 'One')],
      {
        'remote-1': [_file('file-1', 'Updated one', duration: null)],
      },
    );

    await CommunitySyncService(
      database: database,
      api: api,
    ).syncAll(force: true);

    final row = await database.audioItemDao.getByRemoteAudioId('file-1');
    expect(row?.totalDuration, 42);
  });

  test('后台同步会持久化社区合集作者昵称', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    final api = _FakeCommunityApi(
      [
        _catalogEntry(
          'remote-1',
          'One',
          authorNickname: 'Echo Studio',
          updatedAt: DateTime(2026, 2, 1),
        ),
      ],
      {'remote-1': const []},
    );

    await CommunitySyncService(
      database: database,
      api: api,
    ).syncAll(force: true);

    final collection = await (database.select(
      database.collections,
    )..where((row) => row.id.equals('local-1'))).getSingle();
    expect(collection.authorNickname, 'Echo Studio');
    expect(collection.publishedAt, DateTime(2026, 1, 1));
    expect(collection.updatedAt, DateTime(2026, 2, 1));
  });

  test('后台同步节流，force 可以绕过节流', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    final api = _FakeCommunityApi(
      [_catalogEntry('remote-1', 'One')],
      {'remote-1': const []},
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final service = CommunitySyncService(
      database: database,
      api: api,
      preferences: preferences,
      now: () => DateTime(2026, 1, 1, 12),
    );

    await service.syncAll(force: true);
    final throttled = await service.syncAll();
    await service.syncAll(force: true);

    expect(throttled, isA<CommunitySyncThrottled>());
    expect(api.collectionsCalls, 0);
    expect(api.detailCalls, ['remote-1', 'remote-1']);
  });
}

class _NotFoundCommunityApi extends _FakeCommunityApi {
  _NotFoundCommunityApi() : super(const [], const {});

  @override
  Future<CommunityCollectionDetailPage> getCollectionDetail(
    String collectionId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    detailCalls.add(collectionId);
    throw CommunityCollectionNotFound(collectionId);
  }
}

PublicCollectionCatalogEntry _catalogEntry(
  String id,
  String name, {
  String? authorNickname,
  DateTime? updatedAt,
}) {
  return PublicCollectionCatalogEntry(
    id: id,
    name: name,
    description: null,
    coverUrl: null,
    authorNickname: authorNickname,
    fileCount: 1,
    publishedAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
  );
}

CommunityCollectionFile _file(String id, String title, {int? duration = 10}) {
  return CommunityCollectionFile(
    id: id,
    title: title,
    description: null,
    mediaType: CommunityMediaType.audio,
    durationSec: duration,
    fileSizeBytes: null,
    difficulty: null,
    publishedAt: null,
    sortOrder: 0,
    mediaUrl: 'https://example.com/$id.m4a',
  );
}

Future<void> _insertCollection(
  db.AppDatabase database,
  String localId,
  String remoteId,
  String name,
) {
  return database.collectionDao.upsert(
    db.CollectionsCompanion(
      id: Value(localId),
      name: Value(name),
      createdDate: Value(DateTime(2026, 1, 1)),
      updatedAt: Value(DateTime(2026, 1, 1)),
      source: const Value('community'),
      remoteId: Value(remoteId),
    ),
  );
}

Future<void> _insertFile(
  db.AppDatabase database,
  String collectionId,
  String remoteId,
  String name, {
  int duration = 10,
}) async {
  await database.audioItemDao.upsert(
    db.AudioItemsCompanion(
      id: Value('local-$remoteId'),
      name: Value(name),
      addedDate: Value(DateTime(2026, 1, 1)),
      updatedAt: Value(DateTime(2026, 1, 1)),
      totalDuration: Value(duration),
      remoteAudioId: Value(remoteId),
    ),
  );
  await database
      .into(database.collectionAudioItems)
      .insert(
        db.CollectionAudioItemsCompanion(
          collectionId: Value(collectionId),
          audioItemId: Value('local-$remoteId'),
          addedAt: Value(DateTime(2026, 1, 1)),
          sortOrder: const Value(0),
        ),
      );
}
