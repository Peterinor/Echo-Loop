/// 收藏复习共用的调度队列来源。
library;

import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_review_settings.dart';

/// 已纳入收藏复习调度的内容适配项。
final class FavoriteReviewDeckItem<T> {
  const FavoriteReviewDeckItem({
    required this.content,
    required this.subject,
    required this.createdAt,
    required this.schedule,
  });

  final T content;
  final MemorySubjectRef subject;
  final DateTime createdAt;
  final MemorySchedule schedule;
}

/// 对一次联表查询返回的收藏内容复用同一套到期过滤和排序逻辑。
final class FavoriteReviewDeckSource<T> implements FlashcardDeckSource<T> {
  FavoriteReviewDeckSource({
    required List<FavoriteReviewDeckItem<T>> items,
    required MemoryScheduler scheduler,
    required FavoriteReviewSettings settings,
    DateTime Function()? now,
  }) : _items = items,
       _scheduler = scheduler,
       _settings = settings,
       _now = now ?? DateTime.now;

  final List<FavoriteReviewDeckItem<T>> _items;
  final MemoryScheduler _scheduler;
  final FavoriteReviewSettings _settings;
  final DateTime Function() _now;

  @override
  Future<List<ScheduledFlashcard<T>>> load() => _load();

  /// 按当前设置重新排列活动且到期的调度快照，不改持久化状态。
  Future<List<ScheduledFlashcard<T>>> loadForReordering() => _load();

  Future<List<ScheduledFlashcard<T>>> _load() async {
    final now = _now().toUtc();
    final due = _items.where((item) {
      return item.schedule.status == MemoryScheduleStatus.active &&
          !item.schedule.dueAt.isAfter(now);
    }).toList();
    _sortDue(due, now);
    return due
        .map(
          (item) => ScheduledFlashcard<T>(
            subject: item.subject,
            content: item.content,
            scheduleRevision: item.schedule.revision,
            dueAt: item.schedule.dueAt,
          ),
        )
        .toList(growable: false);
  }

  void _sortDue(List<FavoriteReviewDeckItem<T>> items, DateTime now) {
    if (_settings.order == FavoriteReviewOrder.random) {
      items.shuffle();
      return;
    }
    items.sort((a, b) {
      final left = a.schedule;
      final right = b.schedule;
      if (_settings.order == FavoriteReviewOrder.dueAt) {
        final due = left.dueAt.compareTo(right.dueAt);
        return due != 0 ? due : _key(a.subject).compareTo(_key(b.subject));
      }
      final leftNew = left.reviewCount == 0;
      final rightNew = right.reviewCount == 0;
      if (leftNew != rightNew) return leftNew ? 1 : -1;
      if (leftNew) {
        final createdAt = a.createdAt.compareTo(b.createdAt);
        return createdAt != 0
            ? createdAt
            : _key(a.subject).compareTo(_key(b.subject));
      }
      final score = _scheduler
          .retrievability(left, now)
          .compareTo(_scheduler.retrievability(right, now));
      if (score != 0) return score;
      final dueAt = left.dueAt.compareTo(right.dueAt);
      return dueAt != 0 ? dueAt : _key(a.subject).compareTo(_key(b.subject));
    });
  }

  String _key(MemorySubjectRef subject) =>
      '${subject.namespace}:${subject.subjectId}';
}
