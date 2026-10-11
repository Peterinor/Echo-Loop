import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/audio_items.dart';
import '../tables/stage_completions.dart';

part 'stage_completion_dao.g.dart';

/// 最近完成记录（含音频 ID 和名称）
class RecentCompletion {
  /// 音频 ID（用于导航到学习计划页）
  final String audioId;

  /// 音频名称
  final String audioName;

  /// 完成的大阶段键
  final String stage;

  /// 完成的子步骤键
  final String subStage;

  /// 完成时间
  final DateTime completedAt;

  /// 该步骤耗时（毫秒）
  final int durationMs;

  const RecentCompletion({
    required this.audioId,
    required this.audioName,
    required this.stage,
    required this.subStage,
    required this.completedAt,
    required this.durationMs,
  });
}

/// 步骤完成历史 DAO
///
/// 提供步骤完成记录的插入、查询和删除操作。
@DriftAccessor(tables: [StageCompletions, AudioItems])
class StageCompletionDao extends DatabaseAccessor<AppDatabase>
    with _$StageCompletionDaoMixin {
  StageCompletionDao(super.db);

  /// 插入一条步骤完成记录
  Future<void> insertRecord(StageCompletionsCompanion entry) {
    return into(stageCompletions).insert(entry);
  }

  /// 查询指定音频的所有完成记录（按完成时间升序）
  Future<List<StageCompletion>> getByAudioId(String audioItemId) {
    return (select(stageCompletions)
          ..where((t) => t.audioItemId.equals(audioItemId))
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
  }

  /// 监听每条材料全历史中最新的子步骤完成时间。
  Stream<Map<String, DateTime>> watchLatestCompletionAtByAudio() {
    final latestCompletedAt = stageCompletions.completedAt.max();
    final query = selectOnly(stageCompletions)
      ..addColumns([stageCompletions.audioItemId, latestCompletedAt])
      ..groupBy([stageCompletions.audioItemId]);

    return query.watch().map((rows) {
      final result = <String, DateTime>{};
      for (final row in rows) {
        final audioId = row.read(stageCompletions.audioItemId);
        final completedAt = row.read(latestCompletedAt);
        if (audioId != null && completedAt != null) {
          result[audioId] = completedAt;
        }
      }
      return result;
    });
  }

  /// 查询指定时间之后的完成记录（含音频名称，按完成时间倒序）
  ///
  /// 用于"最近完成"区段，JOIN audio_items 获取音频名称。
  Future<List<RecentCompletion>> getRecentCompletions(DateTime since) async {
    final query =
        select(stageCompletions).join([
            innerJoin(
              audioItems,
              audioItems.id.equalsExp(stageCompletions.audioItemId),
            ),
          ])
          ..where(stageCompletions.completedAt.isBiggerOrEqualValue(since))
          ..orderBy([OrderingTerm.desc(stageCompletions.completedAt)]);

    final rows = await query.get();
    return rows.map((row) {
      final audio = row.readTable(audioItems);
      final completion = row.readTable(stageCompletions);
      return RecentCompletion(
        audioId: audio.id,
        audioName: audio.name,
        stage: completion.stage,
        subStage: completion.subStage,
        completedAt: completion.completedAt,
        durationMs: completion.durationMs,
      );
    }).toList();
  }

  /// 删除指定音频的所有完成记录
  Future<void> deleteByAudioId(String audioItemId) {
    return (delete(
      stageCompletions,
    )..where((t) => t.audioItemId.equals(audioItemId))).go();
  }

  /// 查询所有完成事件，按音频 ID 分组返回 `(stage, sub_stage)` 字符串集合。
  ///
  /// 返回的 Set 元素格式为 `'stage.key:subStage.key'`，用作真实"完成"事实
  /// 的内存索引：UI/进度计算用此判定子步骤是否真正做过，而非用
  /// `stage.index < currentStage.index` 推导。
  ///
  /// 启动时一次性加载所有音频的完成集合，比逐音频查询性能更好。
  Future<Map<String, Set<String>>> getCompletionKeysByAudio() async {
    final query = selectOnly(stageCompletions, distinct: true)
      ..addColumns([
        stageCompletions.audioItemId,
        stageCompletions.stage,
        stageCompletions.subStage,
      ]);
    final rows = await query.get();
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final audioId = row.read(stageCompletions.audioItemId)!;
      final stage = row.read(stageCompletions.stage)!;
      final subStage = row.read(stageCompletions.subStage)!;
      result.putIfAbsent(audioId, () => <String>{}).add('$stage:$subStage');
    }
    return result;
  }

  /// 查询指定音频各大阶段的最终完成时间。
  ///
  /// 同一大阶段可能有多个子步骤完成记录，这里取该 stage 下最后一个子步骤的
  /// `completedAt` 作为“大阶段完成时间”，供学习计划页显示“X 天前完成”。
  Future<Map<String, DateTime>> getStageCompletedAtByAudioId(
    String audioItemId,
  ) async {
    final rows = await _stageCompletedAtQuery(audioItemId).get();
    return _foldStageCompletedAt(rows);
  }

  /// 监听指定音频各大阶段的最终完成时间。
  ///
  /// 与 [getStageCompletedAtByAudioId] 语义相同，但返回流：`stage_completions`
  /// 表发生增删改时自动重新查询并发射新结果，供学习计划页实时刷新
  /// “完成于XX”文案，无需手动失效缓存。
  Stream<Map<String, DateTime>> watchStageCompletedAtByAudioId(
    String audioItemId,
  ) {
    return _stageCompletedAtQuery(
      audioItemId,
    ).watch().map(_foldStageCompletedAt);
  }

  /// 构造“按音频查询完成记录、按完成时间升序”的查询，供 Future / Stream 复用。
  SimpleSelectStatement<$StageCompletionsTable, StageCompletion>
  _stageCompletedAtQuery(String audioItemId) {
    return select(stageCompletions)
      ..where((t) => t.audioItemId.equals(audioItemId))
      ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]);
  }

  /// 将升序完成记录折叠为 `stage -> 最终完成时间`。
  ///
  /// 升序遍历、后写覆盖，故每个 stage 保留其最后一个子步骤的 `completedAt`。
  Map<String, DateTime> _foldStageCompletedAt(List<StageCompletion> rows) {
    final result = <String, DateTime>{};
    for (final row in rows) {
      result[row.stage] = row.completedAt;
    }
    return result;
  }
}
