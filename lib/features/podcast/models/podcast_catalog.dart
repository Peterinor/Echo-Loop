/// Podcast catalog 中用于发现页展示的单条精选 Podcast。
class PodcastCatalogItem {
  final String id;
  final String applePodcastUrl;
  final String rssUrl;
  final String? imageUrl;
  final String title;
  final String? description;

  const PodcastCatalogItem({
    required this.id,
    required this.applePodcastUrl,
    required this.rssUrl,
    required this.imageUrl,
    required this.title,
    required this.description,
  });

  factory PodcastCatalogItem.fromJson(Map<String, dynamic> json) {
    return PodcastCatalogItem(
      id: json['id'] as String,
      applePodcastUrl: json['applePodcastUrl'] as String? ?? '',
      rssUrl: json['rssUrl'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
    );
  }

  /// 订阅时优先使用 Apple Podcasts URL，缺失时回退到 RSS URL。
  String get subscriptionInputUrl {
    final appleUrl = applePodcastUrl.trim();
    return appleUrl.isNotEmpty ? appleUrl : rssUrl.trim();
  }
}

/// Podcast catalog 的本地内存快照。
class PodcastCatalogSnapshot {
  final List<PodcastCatalogItem> podcasts;
  final String contentHash;
  final DateTime fetchedAt;

  const PodcastCatalogSnapshot({
    required this.podcasts,
    required this.contentHash,
    required this.fetchedAt,
  });
}
