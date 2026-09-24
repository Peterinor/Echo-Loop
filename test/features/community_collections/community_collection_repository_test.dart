import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/features/community_collections/data/community_collection_api.dart';
import 'package:echo_loop/features/community_collections/data/community_collection_repository.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCommunityApi extends CommunityCollectionApi {
  _FakeCommunityApi() : super.withDio(Dio());

  @override
  Future<PublicCollectionPage> getCollections({
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    return PublicCollectionPage(
      items: [
        PublicCollectionSummary(
          id: 'remote-1',
          name: 'Community English',
          description: 'A community collection.',
          coverUrl: null,
          authorNickname: 'Echo Studio',
          fileCount: 0,
          publishedAt: DateTime(2026, 9, 22),
        ),
      ],
      nextCursor: null,
    );
  }

  @override
  Future<CommunityCollectionFilesPage> getCollectionFiles(
    String collectionId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    return const CommunityCollectionFilesPage(items: [], nextCursor: null);
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

  test(
    'enrolling a community collection stores the author nickname locally',
    () async {
      final repository = CommunityCollectionRepository(
        database: database,
        api: _FakeCommunityApi(),
      );

      final localId = await repository.enroll('remote-1');
      final collection = await database.collectionDao.getById(localId);

      expect(collection?.authorNickname, 'Echo Studio');
      expect(collection?.description, 'A community collection.');
      expect(collection?.publishedAt, DateTime(2026, 9, 22));
    },
  );
}
