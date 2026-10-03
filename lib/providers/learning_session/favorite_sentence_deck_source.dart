/// 收藏句复习的内容适配器。
library;

import '../../database/daos/bookmark_dao.dart';
import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/domain/memory_namespaces.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/bookmark_sentence.dart';
import '../../models/favorite_review_settings.dart';
import '../../models/sentence.dart';
import 'favorite_review_deck_source.dart';

/// 把收藏句转换为共享收藏复习队列的输入项。
final class FavoriteSentenceDeckSource
    implements FlashcardDeckSource<BookmarkSentence> {
  FavoriteSentenceDeckSource({
    required List<BookmarkWithAudio> bookmarks,
    required MemoryScheduler scheduler,
    required FavoriteReviewSettings settings,
    DateTime Function()? now,
  }) : _bookmarks = bookmarks,
       _scheduler = scheduler,
       _settings = settings,
       _now = now;

  final List<BookmarkWithAudio> _bookmarks;
  final MemoryScheduler _scheduler;
  final FavoriteReviewSettings _settings;
  final DateTime Function()? _now;

  @override
  Future<List<ScheduledFlashcard<BookmarkSentence>>> load() => _source().load();

  /// 切换复习顺序时只读取已有调度快照，避免恢复已取消的收藏。
  Future<List<ScheduledFlashcard<BookmarkSentence>>> loadForReordering() =>
      _source().loadForReordering();

  FavoriteReviewDeckSource<BookmarkSentence> _source() =>
      FavoriteReviewDeckSource<BookmarkSentence>(
        items: [
          for (final item in _bookmarks)
            if (_isValid(item))
              FavoriteReviewDeckItem(
                content: _toCard(item, _subjectId(item)),
                subject: MemorySubjectRef(
                  namespace: kSavedSentenceNamespace,
                  subjectId: _subjectId(item),
                ),
                createdAt: item.bookmark.createdAt,
              ),
        ],
        scheduler: _scheduler,
        settings: _settings,
        now: _now,
      );

  bool _isValid(BookmarkWithAudio item) =>
      item.bookmark.endTime > item.bookmark.startTime &&
      item.bookmark.sentenceText.trim().isNotEmpty &&
      (item.bookmark.memorySubjectId?.isNotEmpty ?? false);

  String _subjectId(BookmarkWithAudio item) {
    final value = item.bookmark.memorySubjectId;
    if (value == null || value.isEmpty) {
      throw StateError('收藏句缺少 memorySubjectId');
    }
    return value;
  }

  BookmarkSentence _toCard(BookmarkWithAudio item, String subjectId) =>
      BookmarkSentence(
        sentence: Sentence(
          index: item.bookmark.sentenceIndex,
          text: item.bookmark.sentenceText,
          startTime: Duration(
            milliseconds: (item.bookmark.startTime * 1000).round(),
          ),
          endTime: Duration(
            milliseconds: (item.bookmark.endTime * 1000).round(),
          ),
          isBookmarked: true,
        ),
        audioItemId: item.bookmark.audioItemId,
        audioName: item.audioName,
        originalSentenceIndex: item.bookmark.sentenceIndex,
        memorySubjectId: subjectId,
      );
}
