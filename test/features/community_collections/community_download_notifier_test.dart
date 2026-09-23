import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo_loop/database/app_database.dart' as db;
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/features/community_collections/data/community_collection_api.dart';
import 'package:echo_loop/features/community_collections/data/community_file_lifecycle.dart';
import 'package:echo_loop/features/community_collections/download/community_download_notifier.dart';
import 'package:echo_loop/features/community_collections/download/download_progress.dart';
import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mock_providers.dart';

class _MissingFileApi extends CommunityCollectionApi {
  _MissingFileApi() : super.withDio(Dio());

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
  test('远端文件消失时下载不会永久停留在进行中', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    final dataDirectory = await Directory.systemTemp.createTemp(
      'community-download-',
    );
    await database.collectionDao.upsert(
      db.CollectionsCompanion(
        id: const Value('collection-1'),
        name: const Value('Community'),
        createdDate: Value(DateTime(2026, 1, 1)),
        updatedAt: Value(DateTime(2026, 1, 1)),
        source: const Value('community'),
        remoteId: const Value('remote-1'),
      ),
    );
    await database.audioItemDao.upsert(
      db.AudioItemsCompanion(
        id: const Value('audio-1'),
        name: const Value('Missing file'),
        addedDate: Value(DateTime(2026, 1, 1)),
        updatedAt: Value(DateTime(2026, 1, 1)),
        remoteAudioId: const Value('file-1'),
      ),
    );
    await database
        .into(database.collectionAudioItems)
        .insert(
          db.CollectionAudioItemsCompanion(
            collectionId: const Value('collection-1'),
            audioItemId: const Value('audio-1'),
            addedAt: Value(DateTime(2026, 1, 1)),
          ),
        );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        communityCollectionApiProvider.overrideWithValue(_MissingFileApi()),
        communityFileLifecycleServiceProvider.overrideWithValue(
          CommunityFileLifecycleService(
            database: database,
            dataDir: () async => dataDirectory,
          ),
        ),
        audioLibraryProvider.overrideWith(() => TestAudioLibrary()),
        collectionListProvider.overrideWith(() => TestCollectionList()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
      if (await dataDirectory.exists()) {
        await dataDirectory.delete(recursive: true);
      }
    });

    final notifier = container.read(communityDownloadProvider.notifier);
    expect(
      await notifier.start(audioItemId: 'audio-1', displayName: 'Missing file'),
      StartResult.started,
    );
    expect(await notifier.awaitCompletion(), isFalse);
    expect(container.read(communityDownloadProvider), isA<DownloadFailed>());
    expect(
      container.read(communityDownloadProvider),
      isNot(isA<DownloadInProgress>()),
    );
  });
}
