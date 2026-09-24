import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart' as db;
import '../../../database/providers.dart';
import '../../../services/app_logger.dart';
import '../../../utils/app_data_dir.dart';
import '../models/community_collection_models.dart';
import 'community_collection_api.dart';

part 'community_collection_repository.g.dart';

const _logTag = 'CommunityCollectionRepo';

/// 已加入过的社区合集冲突；通常由并发 enroll 触发。
class CommunityCollectionAlreadyEnrolledError implements Exception {
  final String remoteId;
  final String localId;

  const CommunityCollectionAlreadyEnrolledError({
    required this.remoteId,
    required this.localId,
  });
}

/// v2 列表中不存在该社区合集，可能已下架。
class CommunityCollectionNotFoundError implements Exception {
  final String remoteId;

  const CommunityCollectionNotFoundError(this.remoteId);
}

/// 社区合集与本地 Drift 数据的协调层。
class CommunityCollectionRepository {
  final db.AppDatabase _db;
  final CommunityCollectionApi _api;
  final Future<Directory> Function() _docsDir;

  CommunityCollectionRepository({
    required db.AppDatabase database,
    required CommunityCollectionApi api,
    Future<Directory> Function()? docsDir,
  }) : _db = database,
       _api = api,
       _docsDir = docsDir ?? getAppDataDirectory;

  /// 拉取 v2 合集及其全部文件后，以事务方式创建本地占位数据。
  Future<String> enroll(String remoteId) async {
    final existing = await _db.collectionDao.getByRemoteId(remoteId);
    if (existing != null) {
      throw CommunityCollectionAlreadyEnrolledError(
        remoteId: remoteId,
        localId: existing.id,
      );
    }

    final summary = await _findCollection(remoteId);
    if (summary == null) throw CommunityCollectionNotFoundError(remoteId);
    final files = await _fetchAllFiles(remoteId);
    final localCollectionId = const Uuid().v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      await _db.collectionDao.upsert(
        db.CollectionsCompanion(
          id: Value(localCollectionId),
          name: Value(summary.name),
          createdDate: Value(now),
          updatedAt: Value(now),
          source: const Value('community'),
          remoteId: Value(summary.id),
          coverUrl: Value(summary.coverUrl),
          description: Value(summary.description),
          authorNickname: Value(summary.authorNickname),
          publishedAt: Value(summary.publishedAt),
        ),
      );
      for (final file in files) {
        final audioId = const Uuid().v4();
        await _db.audioItemDao.upsert(
          db.AudioItemsCompanion(
            id: Value(audioId),
            name: Value(file.title),
            addedDate: Value(now),
            totalDuration: Value(file.durationSec ?? 0),
            remoteAudioId: Value(file.id),
            originalDate: Value(file.publishedAt),
            updatedAt: Value(now),
          ),
        );
        await _db
            .into(_db.collectionAudioItems)
            .insertOnConflictUpdate(
              db.CollectionAudioItemsCompanion(
                collectionId: Value(localCollectionId),
                audioItemId: Value(audioId),
                sortOrder: Value(file.sortOrder),
                addedAt: Value(now),
              ),
            );
      }
    });
    AppLogger.log(_logTag, 'enrolled $remoteId as $localCollectionId');
    return localCollectionId;
  }

  /// 彻底移除社区合集及其未共享的本地媒体和学习数据。
  Future<void> remove(String localCollectionId) async {
    final audioIds = await _db.collectionDao.getAudioIds(localCollectionId);
    final audioRows = <db.AudioItem>[];
    for (final id in audioIds) {
      final row = await _db.audioItemDao.getById(id);
      if (row != null) audioRows.add(row);
    }

    await _db.transaction(() async {
      for (final audioId in audioIds) {
        for (final table in [
          'learning_progresses',
          'stage_completions',
          'playback_states',
          'bookmarks',
          'saved_words',
          'saved_sense_groups',
          'audio_item_tags',
        ]) {
          await _db.customStatement(
            'DELETE FROM $table WHERE audio_item_id = ?',
            [audioId],
          );
        }
      }
      await _db.customStatement(
        'DELETE FROM collection_audio_items WHERE collection_id = ?',
        [localCollectionId],
      );
      for (final id in audioIds) {
        await _db.audioItemDao.hardDelete(id);
      }
      await _db.collectionDao.hardDelete(localCollectionId);
    });
    await _deleteLocalFiles(audioRows);
  }

  Future<PublicCollectionSummary?> _findCollection(String remoteId) async {
    String? cursor;
    do {
      final page = await _api.getCollections(cursor: cursor);
      for (final item in page.items) {
        if (item.id == remoteId) return item;
      }
      cursor = page.nextCursor;
    } while (cursor?.isNotEmpty ?? false);
    return null;
  }

  Future<List<CommunityCollectionFile>> _fetchAllFiles(String remoteId) async {
    final files = <CommunityCollectionFile>[];
    String? cursor;
    do {
      final page = await _api.getCollectionFiles(remoteId, cursor: cursor);
      files.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor?.isNotEmpty ?? false);
    return files;
  }

  Future<void> _deleteLocalFiles(List<db.AudioItem> rows) async {
    final dir = await _docsDir();
    for (final row in rows) {
      for (final relativePath in [row.audioPath, row.transcriptPath]) {
        if (relativePath == null) continue;
        try {
          final file = File(p.join(dir.path, relativePath));
          if (await file.exists()) await file.delete();
        } catch (error) {
          AppLogger.log(_logTag, 'failed to delete $relativePath: $error');
        }
      }
    }
  }
}

@Riverpod(keepAlive: true)
CommunityCollectionRepository communityCollectionRepository(Ref ref) {
  return CommunityCollectionRepository(
    database: ref.watch(appDatabaseProvider),
    api: ref.watch(communityCollectionApiProvider),
  );
}
