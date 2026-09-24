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
  _FakeCommunityApi(this.summaries, this.filesByCollection, {this.failId})
    : super.withDio(Dio());

  final List<PublicCollectionSummary> summaries;
  final Map<String, List<CommunityCollectionFile>> filesByCollection;
  final String? failId;
  var collectionsCalls = 0;

  @override
  Future<PublicCollectionPage> getCollections({
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    collectionsCalls++;
    return PublicCollectionPage(items: summaries, nextCursor: null);
  }

  @override
  Future<CommunityCollectionFilesPage> getCollectionFiles(
    String collectionId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    if (collectionId == failId) {
      throw StateError('collection failed: $collectionId');
    }
    return CommunityCollectionFilesPage(
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
      [_summary('remote-1', 'One'), _summary('remote-2', 'Two')],
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
  });

  test('已有文件的远端空时长不会覆盖本地时长', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    await _insertFile(database, 'local-1', 'file-1', 'Old one', duration: 42);

    final api = _FakeCommunityApi(
      [_summary('remote-1', 'One')],
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
      [_summary('remote-1', 'One', authorNickname: 'Echo Studio')],
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
  });

  test('后台同步节流，force 可以绕过节流', () async {
    await _insertCollection(database, 'local-1', 'remote-1', 'One');
    final api = _FakeCommunityApi(
      [_summary('remote-1', 'One')],
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
    expect(api.collectionsCalls, 2);
  });
}

PublicCollectionSummary _summary(
  String id,
  String name, {
  String? authorNickname,
}) {
  return PublicCollectionSummary(
    id: id,
    name: name,
    description: null,
    coverUrl: null,
    authorNickname: authorNickname,
    fileCount: 1,
    publishedAt: DateTime(2026, 1, 1),
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
