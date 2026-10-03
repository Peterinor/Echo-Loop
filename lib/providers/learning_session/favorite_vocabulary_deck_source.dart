/// 收藏词汇复习的内容适配器。
library;

import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/data/memory_schedule_mapper.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_review_settings.dart';
import '../../models/flashcard_item.dart';
import '../../database/app_database.dart';
import '../../database/daos/favorite_review_dao.dart';
import 'favorite_review_deck_source.dart';

/// 把单词和意群转换为共享收藏复习队列的输入项。
final class FavoriteVocabularyDeckSource
    implements FlashcardDeckSource<FlashcardItem> {
  FavoriteVocabularyDeckSource({
    required FavoriteReviewDao favoriteReviewDao,
    required MemoryScheduler scheduler,
    required FavoriteReviewSettings settings,
    DateTime Function()? now,
  }) : _favoriteReviewDao = favoriteReviewDao,
       _scheduler = scheduler,
       _settings = settings,
       _now = now;

  final FavoriteReviewDao _favoriteReviewDao;
  final MemoryScheduler _scheduler;
  final FavoriteReviewSettings _settings;
  final DateTime Function()? _now;
  final MemoryScheduleMapper _scheduleMapper = MemoryScheduleMapper();

  @override
  Future<List<ScheduledFlashcard<FlashcardItem>>> load() async =>
      (await _source()).load();

  /// 切换顺序时重新查询到期队列，但不恢复或写入任何调度状态。
  Future<List<ScheduledFlashcard<FlashcardItem>>> loadForReordering() async =>
      (await _source()).loadForReordering();

  Future<FavoriteReviewDeckSource<FlashcardItem>> _source() async {
    final now = (_now ?? DateTime.now)().toUtc();
    final rows = await _favoriteReviewDao.getDueVocabulary(now);
    final items = <FavoriteReviewDeckItem<FlashcardItem>>[];
    for (final row in rows) {
      final schedule = _scheduleMapper.scheduleFromRow(row.schedule);
      final word = row.word;
      final senseGroup = row.senseGroup;
      final content = switch ((word, senseGroup)) {
        (final SavedWord word, null) => FlashcardWordItem(savedWord: word),
        (null, final SavedSenseGroup group) => FlashcardPhraseItem(
          savedPhrase: group,
        ),
        _ => null,
      };
      if (content == null) continue;
      items.add(
        FavoriteReviewDeckItem(
          content: content,
          subject: schedule.subject,
          createdAt: content.createdAt,
          schedule: schedule,
        ),
      );
    }
    return FavoriteReviewDeckSource<FlashcardItem>(
      items: items,
      scheduler: _scheduler,
      settings: _settings,
      now: () => now,
    );
  }
}
