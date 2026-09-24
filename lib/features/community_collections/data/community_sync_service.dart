import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart' as db;
import '../../../database/providers.dart';
import '../../../providers/learning_settings_provider.dart'
    show sharedPreferencesProvider;
import '../../../services/app_logger.dart';
import '../../../services/refresh_coordinator.dart';
import '../models/community_collection_models.dart';
import 'community_collection_api.dart';
import 'community_file_lifecycle.dart';

part 'community_sync_service.g.dart';

/// 社区合集同步结果，供日志、启动流程和测试使用。
sealed class CommunitySyncOutcome {
  const CommunitySyncOutcome();
}

/// 成功完成一次远端同步；部分合集失败时仍返回此结果，保证其它合集继续更新。
class CommunitySyncCompleted extends CommunitySyncOutcome {
  final int collectionsScanned;
  final int collectionsDeprecated;
  final int collectionsUndeprecated;
  final int filesAdded;
  final int filesRemoved;
  final int filesMarkedUnavailable;
  final int failedCollections;
  final int failedFiles;

  const CommunitySyncCompleted({
    required this.collectionsScanned,
    required this.collectionsDeprecated,
    required this.collectionsUndeprecated,
    required this.filesAdded,
    required this.filesRemoved,
    this.filesMarkedUnavailable = 0,
    this.failedCollections = 0,
    this.failedFiles = 0,
  });
}

/// 后台刷新命中节流窗口时跳过网络请求。
class CommunitySyncThrottled extends CommunitySyncOutcome {
  const CommunitySyncThrottled();
}

/// 没有订阅社区合集时跳过网络同步。
class CommunitySyncSkipped extends CommunitySyncOutcome {
  const CommunitySyncSkipped();
}

/// 网络或数据解析失败；本地缓存继续可用。
class CommunitySyncFailed extends CommunitySyncOutcome {
  final Object error;

  const CommunitySyncFailed(this.error);
}

/// 社区合集本地缓存与 v2 远端数据的协调层。
class CommunitySyncService {
  final db.AppDatabase _db;
  final CommunityCollectionApi _api;
  final CommunityFileLifecycleService _fileLifecycle;
  final SharedPreferences? _preferences;
  final DateTime Function() _now;
  late final RefreshCoordinator<String, CommunitySyncOutcome> _refresh;

  static const throttleWindow = Duration(hours: 2);
  static const _lastSyncAtKey = 'community_collection_last_sync_at_v2';

  CommunitySyncService({
    required db.AppDatabase database,
    required CommunityCollectionApi api,
    CommunityFileLifecycleService? fileLifecycle,
    SharedPreferences? preferences,
    DateTime Function()? now,
  }) : _db = database,
       _api = api,
       _fileLifecycle =
           fileLifecycle ?? CommunityFileLifecycleService(database: database),
       _preferences = preferences,
       _now = now ?? DateTime.now {
    _refresh = RefreshCoordinator<String, CommunitySyncOutcome>(now: _now);
  }

  /// 同一时刻只允许一个同步请求；后台调用受 2 小时节流，手动刷新可强制执行。
  Future<CommunitySyncOutcome> syncAll({bool force = false}) {
    return _refresh
        .run(
          key: 'community-subscriptions',
          force: force,
          lastRefreshedAt: _lastSyncAt,
          throttleWindow: throttleWindow,
          refresh: _runSyncAll,
        )
        .then((result) async {
          return switch (result) {
            RefreshThrottled<CommunitySyncOutcome>() =>
              const CommunitySyncThrottled(),
            RefreshCompleted<CommunitySyncOutcome>(:final result) =>
              _recordCompleted(result),
          };
        });
  }

  DateTime? get _lastSyncAt {
    final millis = _preferences?.getInt(_lastSyncAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<CommunitySyncOutcome> _recordCompleted(
    CommunitySyncOutcome result,
  ) async {
    if (result is CommunitySyncCompleted) {
      await _preferences?.setInt(_lastSyncAtKey, _now().millisecondsSinceEpoch);
    }
    return result;
  }

  Future<CommunitySyncOutcome> _runSyncAll() async {
    final locals = await (_db.select(
      _db.collections,
    )..where((t) => t.source.equals('community') & t.deletedAt.isNull())).get();
    if (locals.isEmpty) return const CommunitySyncSkipped();

    try {
      final summaries = await _fetchAllCollections();
      final byRemoteId = {for (final item in summaries) item.id: item};
      var deprecated = 0;
      var undeprecated = 0;
      var added = 0;
      var removed = 0;
      var unavailable = 0;
      var failedCollections = 0;
      var failedFiles = 0;

      for (final local in locals) {
        try {
          final remoteId = local.remoteId;
          final summary = remoteId == null ? null : byRemoteId[remoteId];
          if (summary == null) {
            if (local.deprecatedAt == null) {
              await _markDeprecated(local.id);
              deprecated++;
            }
            continue;
          }
          if (local.deprecatedAt != null) {
            await _restore(local.id);
            undeprecated++;
          }
          final files = await _fetchAllFiles(summary.id);
          final result = await _applyCollection(local, summary, files);
          added += result.added;
          removed += result.removed;
          unavailable += result.unavailable;
          failedFiles += result.failedFiles;
        } catch (error, stackTrace) {
          failedCollections++;
          AppLogger.log(
            'CommunitySync',
            'collection sync failed localId=${local.id} remoteId=${local.remoteId}: $error',
          );
          AppLogger.log('CommunitySync', stackTrace.toString());
        }
      }

      return CommunitySyncCompleted(
        collectionsScanned: locals.length,
        collectionsDeprecated: deprecated,
        collectionsUndeprecated: undeprecated,
        filesAdded: added,
        filesRemoved: removed,
        filesMarkedUnavailable: unavailable,
        failedCollections: failedCollections,
        failedFiles: failedFiles,
      );
    } catch (error, stackTrace) {
      AppLogger.log('CommunitySync', 'sync failed: $error');
      AppLogger.log('CommunitySync', stackTrace.toString());
      return CommunitySyncFailed(error);
    }
  }

  Future<List<PublicCollectionSummary>> _fetchAllCollections() async {
    final result = <PublicCollectionSummary>[];
    String? cursor;
    do {
      final page = await _api.getCollections(cursor: cursor);
      result.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor?.isNotEmpty ?? false);
    return result;
  }

  Future<List<CommunityCollectionFile>> _fetchAllFiles(
    String collectionId,
  ) async {
    final result = <CommunityCollectionFile>[];
    String? cursor;
    do {
      final page = await _api.getCollectionFiles(collectionId, cursor: cursor);
      result.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor?.isNotEmpty ?? false);
    return result;
  }

  Future<void> _markDeprecated(String localId) async {
    final now = _now();
    await (_db.update(
      _db.collections,
    )..where((t) => t.id.equals(localId))).write(
      db.CollectionsCompanion(deprecatedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> _restore(String localId) async {
    await (_db.update(
      _db.collections,
    )..where((t) => t.id.equals(localId))).write(
      db.CollectionsCompanion(
        deprecatedAt: const Value(null),
        source: const Value('community'),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<_CollectionDiff> _applyCollection(
    db.Collection local,
    PublicCollectionSummary summary,
    List<CommunityCollectionFile> files,
  ) async {
    final junctions = await (_db.select(
      _db.collectionAudioItems,
    )..where((t) => t.collectionId.equals(local.id))).get();
    final audioRows = <String, db.AudioItem>{};
    for (final junction in junctions) {
      final row = await _db.audioItemDao.getById(junction.audioItemId);
      if (row != null) audioRows[row.id] = row;
    }
    final localByRemoteId = <String, db.AudioItem>{};
    for (final row in audioRows.values) {
      final remoteId = row.remoteAudioId;
      if (remoteId != null) localByRemoteId[remoteId] = row;
    }
    final remoteIds = files.map((file) => file.id).toSet();
    var added = 0;
    var removed = 0;
    var unavailable = 0;
    var failedFiles = 0;

    await _db.transaction(() async {
      for (final file in files) {
        final existing = localByRemoteId[file.id];
        if (existing == null) {
          final id = const Uuid().v4();
          final now = _now();
          await _db.audioItemDao.upsert(
            db.AudioItemsCompanion(
              id: Value(id),
              name: Value(file.title),
              addedDate: Value(now),
              totalDuration: Value(file.durationSec ?? 0),
              remoteAudioId: Value(file.id),
              originalDate: Value(file.publishedAt),
              communityUnavailableAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
          await _db
              .into(_db.collectionAudioItems)
              .insertOnConflictUpdate(
                db.CollectionAudioItemsCompanion(
                  collectionId: Value(local.id),
                  audioItemId: Value(id),
                  sortOrder: Value(file.sortOrder),
                  addedAt: Value(now),
                ),
              );
          added++;
          continue;
        }

        final junction = junctions.firstWhere(
          (item) => item.audioItemId == existing.id,
        );
        if (junction.sortOrder != file.sortOrder) {
          await (_db.update(_db.collectionAudioItems)..where(
                (t) =>
                    t.collectionId.equals(local.id) &
                    t.audioItemId.equals(existing.id),
              ))
              .write(
                db.CollectionAudioItemsCompanion(
                  sortOrder: Value(file.sortOrder),
                ),
              );
        }
        await (_db.update(
          _db.audioItems,
        )..where((t) => t.id.equals(existing.id))).write(
          db.AudioItemsCompanion(
            name: Value(file.title),
            totalDuration: file.durationSec == null
                ? const Value.absent()
                : Value(file.durationSec!),
            originalDate: Value(file.publishedAt),
            communityUnavailableAt: const Value(null),
            updatedAt: Value(_now()),
          ),
        );
      }

      await (_db.update(
        _db.collections,
      )..where((t) => t.id.equals(local.id))).write(
        db.CollectionsCompanion(
          source: const Value('community'),
          name: Value(summary.name),
          description: Value(summary.description),
          coverUrl: Value(summary.coverUrl),
          authorNickname: Value(summary.authorNickname),
          publishedAt: Value(summary.publishedAt),
          updatedAt: Value(_now()),
        ),
      );
    });

    for (final row in localByRemoteId.values) {
      if (remoteIds.contains(row.remoteAudioId)) continue;
      try {
        final result = await _fileLifecycle.markUnavailable(
          audioItemId: row.id,
          localCollectionId: local.id,
        );
        switch (result) {
          case CommunityFileRemovalResult.removed:
            removed++;
          case CommunityFileRemovalResult.markedUnavailable:
            unavailable++;
          case CommunityFileRemovalResult.unchanged:
            break;
        }
      } catch (error, stackTrace) {
        failedFiles++;
        AppLogger.log(
          'CommunitySync',
          'file removal failed audioItemId=${row.id}: $error',
        );
        AppLogger.log('CommunitySync', stackTrace.toString());
      }
    }
    return _CollectionDiff(
      added: added,
      removed: removed,
      unavailable: unavailable,
      failedFiles: failedFiles,
    );
  }
}

class _CollectionDiff {
  final int added;
  final int removed;
  final int unavailable;
  final int failedFiles;

  const _CollectionDiff({
    required this.added,
    required this.removed,
    required this.unavailable,
    required this.failedFiles,
  });
}

@Riverpod(keepAlive: true)
CommunitySyncService communitySyncService(Ref ref) {
  return CommunitySyncService(
    database: ref.watch(appDatabaseProvider),
    api: ref.watch(communityCollectionApiProvider),
    fileLifecycle: ref.watch(communityFileLifecycleServiceProvider),
    preferences: ref.read(sharedPreferencesProvider),
  );
}
