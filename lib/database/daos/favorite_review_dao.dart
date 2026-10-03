import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/audio_items.dart';
import '../tables/bookmarks.dart';
import '../tables/memory_schedules.dart';
import '../tables/saved_sense_groups.dart';
import '../tables/saved_words.dart';
import '../../features/memory_scheduler/domain/memory_namespaces.dart';

part 'favorite_review_dao.g.dart';

/// 已到期收藏句及其当前调度快照。
final class DueFavoriteSentenceRow {
  const DueFavoriteSentenceRow({
    required this.bookmark,
    required this.audioName,
    required this.schedule,
  });

  final Bookmark bookmark;
  final String audioName;
  final MemorySchedule schedule;
}

/// 已到期收藏词汇及其当前调度快照。
final class DueFavoriteVocabularyRow {
  const DueFavoriteVocabularyRow({
    required this.word,
    required this.senseGroup,
    required this.schedule,
  });

  final SavedWord? word;
  final SavedSenseGroup? senseGroup;
  final MemorySchedule schedule;
}

/// 从活动且到期的调度快照联表读取可复习收藏内容。
@DriftAccessor(
  tables: [
    MemorySchedules,
    Bookmarks,
    AudioItems,
    SavedWords,
    SavedSenseGroups,
  ],
)
class FavoriteReviewDao extends DatabaseAccessor<AppDatabase>
    with _$FavoriteReviewDaoMixin {
  /// 创建收藏复习查询 DAO。
  FavoriteReviewDao(super.db);

  /// 一条 SQL 查询已到期、有效且来源音频未删除的收藏句。
  Future<List<DueFavoriteSentenceRow>> getDueSentences(
    DateTime dueBeforeOrAt,
  ) async {
    final query =
        select(memorySchedules).join([
          innerJoin(
            bookmarks,
            memorySchedules.namespace.equals(kSavedSentenceNamespace) &
                memorySchedules.subjectId.equalsExp(bookmarks.memorySubjectId) &
                bookmarks.deletedAt.isNull(),
          ),
          innerJoin(
            audioItems,
            bookmarks.audioItemId.equalsExp(audioItems.id) &
                audioItems.deletedAt.isNull(),
          ),
        ])..where(
          memorySchedules.namespace.equals(kSavedSentenceNamespace) &
              memorySchedules.status.equals('active') &
              memorySchedules.dueAt.isSmallerOrEqualValue(dueBeforeOrAt),
        );

    final rows = await query.get();
    return [
      for (final row in rows)
        if (row.readTable(bookmarks).sentenceText.trim().isNotEmpty &&
            row.readTable(bookmarks).endTime >
                row.readTable(bookmarks).startTime)
          DueFavoriteSentenceRow(
            bookmark: row.readTable(bookmarks),
            audioName: row.readTable(audioItems).name,
            schedule: row.readTable(memorySchedules),
          ),
    ];
  }

  /// 一条 SQL 查询已到期且有效的收藏单词与意群。
  Future<List<DueFavoriteVocabularyRow>> getDueVocabulary(
    DateTime dueBeforeOrAt,
  ) async {
    final query =
        select(memorySchedules).join([
          leftOuterJoin(
            savedWords,
            memorySchedules.namespace.equals(kSavedWordOrPhraseNamespace) &
                memorySchedules.subjectId.equalsExp(
                  savedWords.memorySubjectId,
                ) &
                savedWords.deletedAt.isNull(),
          ),
          leftOuterJoin(
            savedSenseGroups,
            memorySchedules.namespace.equals(kSavedSenseGroupNamespace) &
                memorySchedules.subjectId.equalsExp(
                  savedSenseGroups.memorySubjectId,
                ) &
                savedSenseGroups.deletedAt.isNull(),
          ),
        ])..where(
          memorySchedules.status.equals('active') &
              memorySchedules.namespace.isIn([
                kSavedWordOrPhraseNamespace,
                kSavedSenseGroupNamespace,
              ]) &
              memorySchedules.dueAt.isSmallerOrEqualValue(dueBeforeOrAt),
        );

    final rows = await query.get();
    return [
      for (final row in rows)
        if (_isReviewableWord(row.readTableOrNull(savedWords)) ||
            _isReviewableSenseGroup(row.readTableOrNull(savedSenseGroups)))
          DueFavoriteVocabularyRow(
            word: row.readTableOrNull(savedWords),
            senseGroup: row.readTableOrNull(savedSenseGroups),
            schedule: row.readTable(memorySchedules),
          ),
    ];
  }

  bool _isReviewableWord(SavedWord? word) =>
      word != null && word.word.trim().isNotEmpty;

  bool _isReviewableSenseGroup(SavedSenseGroup? group) =>
      group != null && group.displayText.trim().isNotEmpty;
}
