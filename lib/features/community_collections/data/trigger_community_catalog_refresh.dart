import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/discover_community_collections_provider.dart';

/// 触发社区合集公开 catalog 的唯一刷新入口。
///
/// 手动刷新只强制更新第一页；后续页面由用户滚动时按需加载。
Future<void> triggerCommunityCatalogRefresh(
  WidgetRef ref, {
  bool force = false,
}) {
  return ref
      .read(discoverCommunityCollectionsProvider.notifier)
      .refresh(force: force);
}
