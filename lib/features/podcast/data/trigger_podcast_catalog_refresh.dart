import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'podcast_catalog_service.dart';

/// 触发 Podcast catalog 刷新，不参与社区合集 v2 同步。
Future<PodcastCatalogRefreshOutcome?> triggerPodcastCatalogRefresh(
  WidgetRef ref, {
  bool force = false,
}) async {
  try {
    final outcome = await ref
        .read(podcastCatalogServiceProvider)
        .refresh(force: force);
    if (outcome is PodcastCatalogUpdated) {
      ref.invalidate(cachedPodcastCatalogProvider);
    }
    return outcome;
  } catch (_) {
    return null;
  }
}
