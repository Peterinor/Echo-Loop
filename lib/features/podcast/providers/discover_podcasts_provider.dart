import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/podcast_catalog_service.dart';
import '../models/podcast_catalog.dart';

part 'discover_podcasts_provider.g.dart';

/// Discover 页的精选 Podcast 列表。
@Riverpod(keepAlive: true)
List<PodcastCatalogItem>? discoverPodcasts(Ref ref) {
  final catalog = ref.watch(cachedPodcastCatalogProvider);
  if (catalog == null) {
    final service = ref.read(podcastCatalogServiceProvider);
    return service.hasInitialized ? const <PodcastCatalogItem>[] : null;
  }
  return catalog.podcasts;
}
