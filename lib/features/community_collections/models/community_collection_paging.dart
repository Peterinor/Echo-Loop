/// 社区合集 catalog 的单页数据。
class CommunityCollectionCatalogPage<T> {
  final String? cursor;
  final List<T> items;
  final String? nextCursor;

  const CommunityCollectionCatalogPage({
    required this.cursor,
    required this.items,
    required this.nextCursor,
  });
}

/// 社区合集分页列表的界面状态。
///
/// 保留已加载的页面，而不是只保存扁平列表，便于页面刷新后替换对应
/// cursor，并丢弃已经不属于当前 cursor 链的旧页面。
class CommunityCollectionPagedState<T> {
  final List<CommunityCollectionCatalogPage<T>> pages;
  final bool isLoadingMore;
  final Object? loadMoreError;

  const CommunityCollectionPagedState({
    required this.pages,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  factory CommunityCollectionPagedState.fromFirstPage(
    CommunityCollectionCatalogPage<T> page,
  ) {
    return CommunityCollectionPagedState(pages: [page]);
  }

  List<T> get items =>
      pages.expand((page) => page.items).toList(growable: false);

  String? get nextCursor => pages.isEmpty ? null : pages.last.nextCursor;

  bool get hasMore {
    final cursor = nextCursor;
    return cursor != null && cursor.isNotEmpty;
  }

  CommunityCollectionPagedState<T> copyWith({
    List<CommunityCollectionCatalogPage<T>>? pages,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return CommunityCollectionPagedState(
      pages: pages ?? this.pages,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : loadMoreError ?? this.loadMoreError,
    );
  }

  CommunityCollectionPagedState<T> replaceFirstPage(
    CommunityCollectionCatalogPage<T> page,
  ) {
    return CommunityCollectionPagedState(
      pages: [page],
      isLoadingMore: isLoadingMore,
      loadMoreError: loadMoreError,
    );
  }

  CommunityCollectionPagedState<T> replacePage(
    CommunityCollectionCatalogPage<T> page,
  ) {
    final nextPages = pages.toList(growable: true);
    final index = nextPages.indexWhere(
      (current) => current.cursor == page.cursor,
    );
    if (index < 0) {
      nextPages.add(page);
    } else {
      nextPages
        ..removeRange(index + 1, nextPages.length)
        ..[index] = page;
    }
    return CommunityCollectionPagedState(
      pages: nextPages,
      isLoadingMore: isLoadingMore,
      loadMoreError: loadMoreError,
    );
  }

  CommunityCollectionPagedState<T> appendPage(
    CommunityCollectionCatalogPage<T> page,
  ) {
    return CommunityCollectionPagedState(
      pages: [...pages, page],
      isLoadingMore: isLoadingMore,
      loadMoreError: loadMoreError,
    );
  }
}
