import '../../services/app_logger.dart';
import '../../database/daos/bookmark_dao.dart';
import '../../models/sentence.dart';

/// 书签读取与句子收藏状态转换工具。
class BookmarkManager {
  /// 规范化文本用于书签比较：转小写并移除首尾标点符号
  /// 用于检测相同文本的书签，忽略大小写和首尾标点差异
  static String _normalizeForBookmarkComparison(String text) {
    // 移除首尾空白
    String normalized = text.trim();
    // 转小写
    normalized = normalized.toLowerCase();
    // 移除首尾的常见标点符号（保留中间的标点）
    normalized = normalized.replaceAll(
      RegExp(r'^[.,!?;:\-—…、，。！？；：]+|[.,!?;:\-—…、，。！？；：]+$'),
      '',
    );
    return normalized.trim();
  }

  /// 加载书签（从 Drift 数据库）
  static Future<Set<int>> loadBookmarks(
    String audioId, {
    required BookmarkDao dao,
  }) async {
    try {
      return await dao.getBookmarkedIndices(audioId);
    } catch (e) {
      AppLogger.log('Bookmark', '✗ 加载书签失败: $e');
      return {};
    }
  }

  /// 更新句子的书签状态
  static void updateSentenceBookmarkStatus(
    List<Sentence> sentences,
    Set<int> bookmarkedIndices,
  ) {
    for (var sentence in sentences) {
      sentence.isBookmarked = bookmarkedIndices.contains(sentence.index);
    }
  }

  /// 基于收藏索引创建会话专用的句子快照。
  ///
  /// 字幕缓存是跨页面共享的只读投影，不能在进入某个学习会话时原地写入
  /// [Sentence.isBookmarked]。调用方应使用本方法得到独立副本，避免一个会话
  /// 的收藏状态污染其他页面或后续会话。
  static List<Sentence> createSentenceBookmarkSnapshot(
    Iterable<Sentence> sentences,
    Set<int> bookmarkedIndices,
  ) {
    return [
      for (final sentence in sentences)
        sentence.copyWith(
          isBookmarked: bookmarkedIndices.contains(sentence.index),
        ),
    ];
  }

  /// 基于收藏索引创建保留段落结构的会话句子快照。
  static List<List<Sentence>> createParagraphBookmarkSnapshot(
    Iterable<List<Sentence>> paragraphs,
    Set<int> bookmarkedIndices,
  ) {
    return [
      for (final paragraph in paragraphs)
        createSentenceBookmarkSnapshot(paragraph, bookmarkedIndices),
    ];
  }

  /// 切换书签状态
  /// 返回: (isRemoving, indicesToRemove, replacementIndex)
  ///
  /// 收藏模式删除当前句时，替代焦点优先取后一条；后面没有可用
  /// 收藏时回退到前一条。只有删除后确实无收藏可选时才返回 null。
  static (bool, Set<int>, int?) toggleBookmark(
    int index,
    List<Sentence> sentences,
    Set<int> bookmarkedIndices,
    bool inBookmarksMode,
  ) {
    final isRemoving = bookmarkedIndices.contains(index);
    Set<int> indicesToRemove = {};
    int? replacementIndex;

    if (isRemoving) {
      // 计算所有同文本（不区分大小写，忽略首尾标点）的书签
      final bookmarkedSentences = sentences
          .where((s) => bookmarkedIndices.contains(s.index))
          .toList();
      final targetTextNormalized = _normalizeForBookmarkComparison(
        sentences[index].text,
      );

      for (final s in bookmarkedSentences) {
        if (_normalizeForBookmarkComparison(s.text) == targetTextNormalized) {
          indicesToRemove.add(s.index);
        }
      }

      // 仅在书签模式时计算"下一个"焦点
      if (inBookmarksMode) {
        final pos = bookmarkedSentences.indexWhere((s) => s.index == index);
        if (pos != -1) {
          // 优先找后一个句子（跳过将被移除的条目）。
          for (int i = pos + 1; i < bookmarkedSentences.length; i++) {
            if (!indicesToRemove.contains(bookmarkedSentences[i].index)) {
              replacementIndex = bookmarkedSentences[i].index;
              break;
            }
          }

          // 当前句在收藏末尾时，回退到最近的前一条，避免收藏仍有
          // 内容却丢失当前焦点，导致精听页误退回列表。
          if (replacementIndex == null) {
            for (int i = pos - 1; i >= 0; i--) {
              if (!indicesToRemove.contains(bookmarkedSentences[i].index)) {
                replacementIndex = bookmarkedSentences[i].index;
                break;
              }
            }
          }
        }
      }
    }

    return (isRemoving, indicesToRemove, replacementIndex);
  }
}
