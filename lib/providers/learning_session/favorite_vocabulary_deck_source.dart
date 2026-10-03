/// 收藏词汇复习的内容适配器。
library;

import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_review_settings.dart';
import '../../models/flashcard_item.dart';
import '../../database/app_database.dart';
import 'favorite_review_deck_source.dart';

/// 把单词和意群转换为共享收藏复习队列的输入项。
final class FavoriteVocabularyDeckSource
    implements FlashcardDeckSource<FlashcardItem> {
  FavoriteVocabularyDeckSource({
    required List<SavedWord> words,
    required List<SavedSenseGroup> phrases,
    required MemoryScheduler scheduler,
    required FavoriteReviewSettings settings,
    DateTime Function()? now,
  }) : _words = words,
       _phrases = phrases,
       _scheduler = scheduler,
       _settings = settings,
       _now = now;

  final List<SavedWord> _words;
  final List<SavedSenseGroup> _phrases;
  final MemoryScheduler _scheduler;
  final FavoriteReviewSettings _settings;
  final DateTime Function()? _now;

  @override
  Future<List<ScheduledFlashcard<FlashcardItem>>> load() => _source().load();

  /// 切换复习顺序时只读取已有调度快照，避免恢复已取消的收藏。
  Future<List<ScheduledFlashcard<FlashcardItem>>> loadForReordering() =>
      _source().loadForReordering();

  FavoriteReviewDeckSource<FlashcardItem> _source() =>
      FavoriteReviewDeckSource<FlashcardItem>(
        items: [
          for (final item in _items)
            if (_isValid(item))
              FavoriteReviewDeckItem(
                content: item,
                subject: MemorySubjectRef(
                  namespace: item.namespace,
                  subjectId: _subjectId(item),
                ),
                createdAt: item.createdAt,
              ),
        ],
        scheduler: _scheduler,
        settings: _settings,
        now: _now,
      );

  List<FlashcardItem> get _items => [
    for (final word in _words) FlashcardWordItem(savedWord: word),
    for (final phrase in _phrases) FlashcardPhraseItem(savedPhrase: phrase),
  ];

  bool _isValid(FlashcardItem item) =>
      item.displayText.trim().isNotEmpty &&
      (item.memorySubjectId?.isNotEmpty ?? false);

  String _subjectId(FlashcardItem item) {
    final value = item.memorySubjectId;
    if (value == null || value.isEmpty) {
      throw StateError('收藏词汇缺少 memorySubjectId');
    }
    return value;
  }
}
