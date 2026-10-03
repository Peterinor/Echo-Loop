/// 收藏复习共用的调度队列来源。
library;

import '../../features/memory_scheduler/application/memory_scheduler.dart';
import '../../features/memory_scheduler/config/memory_profiles.dart';
import '../../features/memory_scheduler/domain/memory_schedule.dart';
import '../../features/memory_scheduler/domain/memory_scheduler_commands.dart';
import '../../features/memory_scheduler/domain/memory_subject_ref.dart';
import '../../features/scheduled_flashcard/domain/scheduled_flashcard.dart';
import '../../models/favorite_review_settings.dart';

/// 已纳入收藏复习调度的内容适配项。
final class FavoriteReviewDeckItem<T> {
  const FavoriteReviewDeckItem({
    required this.content,
    required this.subject,
    required this.createdAt,
  });

  final T content;
  final MemorySubjectRef subject;
  final DateTime createdAt;
}

/// 对任意收藏内容执行同一套 FSRS 入队、过滤、排序和预算逻辑。
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
  Future<List<ScheduledFlashcard<T>>> load() => _load(prepareSchedules: true);

  /// 仅读取既有 active 快照，用于设置变更时更新当前队列顺序。
  Future<List<ScheduledFlashcard<T>>> loadForReordering() =>
      _load(prepareSchedules: false);

  Future<List<ScheduledFlashcard<T>>> _load({
    required bool prepareSchedules,
  }) async {
    final now = _now().toUtc();
    final schedules = <MemorySubjectRef, MemorySchedule>{};
    for (final item in _items) {
      final existing = await _scheduler.getSchedule(item.subject);
      if (!prepareSchedules) {
        if (existing != null &&
            existing.status == MemoryScheduleStatus.active) {
          schedules[item.subject] = existing;
        }
        continue;
      }
      // 兼容旧调用方或测试直接写入收藏表的情况；正常新增路径会提前建立快照。
      final schedule = existing == null
          ? await _scheduler.ensureSchedule(
              EnsureMemoryScheduleCommand(
                subject: item.subject,
                profile: kFsrsDefaultProfileRef,
                occurredAt: now,
              ),
            )
          : existing.status == MemoryScheduleStatus.archived
          ? await _scheduler.restore(
              RestoreMemoryScheduleCommand(
                subject: item.subject,
                restoredAt: now,
                expectedRevision: existing.revision,
              ),
            )
          : existing;
      schedules[item.subject] = schedule;
    }
    final due = _items.where((item) {
      final schedule = schedules[item.subject];
      if (schedule == null) return false;
      final dueAt = schedule.dueAt;
      return !dueAt.isAfter(now);
    }).toList();
    _sortDue(due, schedules, now);
    return due
        .map(
          (item) => ScheduledFlashcard<T>(
            subject: item.subject,
            content: item.content,
            scheduleRevision: schedules[item.subject]!.revision,
            dueAt: schedules[item.subject]!.dueAt,
          ),
        )
        .toList(growable: false);
  }

  void _sortDue(
    List<FavoriteReviewDeckItem<T>> items,
    Map<MemorySubjectRef, MemorySchedule> schedules,
    DateTime now,
  ) {
    if (_settings.order == FavoriteReviewOrder.random) {
      items.shuffle();
      return;
    }
    items.sort((a, b) {
      final left = schedules[a.subject]!;
      final right = schedules[b.subject]!;
      if (_settings.order == FavoriteReviewOrder.dueAt) {
        final due = left.dueAt.compareTo(right.dueAt);
        return due != 0 ? due : _key(a.subject).compareTo(_key(b.subject));
      }
      final leftNew = left.reviewCount == 0;
      final rightNew = right.reviewCount == 0;
      if (leftNew != rightNew) return leftNew ? 1 : -1;
      if (leftNew) return a.createdAt.compareTo(b.createdAt);
      final score = _scheduler
          .retrievability(left, now)
          .compareTo(_scheduler.retrievability(right, now));
      return score != 0 ? score : left.dueAt.compareTo(right.dueAt);
    });
  }

  String _key(MemorySubjectRef subject) =>
      '${subject.namespace}:${subject.subjectId}';
}
