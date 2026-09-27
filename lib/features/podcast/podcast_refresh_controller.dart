/// 已订阅播客的统一静默刷新入口。
///
/// 约束：
/// - App 生命周期只负责触发本控制器，不直接遍历合集或拼刷新策略。
/// - 真实刷新统一走 [PodcastRepository.refresh]，复用其 60 分钟节流与 inflight 合并。
/// - 单个 feed 刷新失败不影响其他已订阅播客；失败只记日志，不打断全局静默刷新。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/collection_provider.dart';
import '../../services/app_logger.dart';
import 'podcast_repository.dart';

/// 统一的播客静默刷新控制器。
final podcastRefreshControllerProvider = Provider<PodcastRefreshController>(
  PodcastRefreshController.new,
);

/// 负责在启动/回前台等标准生命周期入口静默刷新已订阅播客。
class PodcastRefreshController {
  final Ref _ref;

  Future<void>? _inflight;

  PodcastRefreshController(this._ref);

  /// 按当前本地合集列表，静默刷新所有已订阅播客。
  ///
  /// 多次并发触发时复用同一条链路，避免生命周期抖动时重复遍历合集。
  Future<void> refreshIfStale() {
    final existing = _inflight;
    if (existing != null) {
      AppLogger.log('PodcastRefresh', 'refreshIfStale reusing inflight');
      return existing;
    }
    final future = _runRefreshIfStale();
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<void> _runRefreshIfStale() async {
    final collections = _ref
        .read(collectionListProvider)
        .rawCollections
        .where((collection) => collection.isPodcast)
        .toList(growable: false);
    if (collections.isEmpty) {
      AppLogger.log('PodcastRefresh', 'refreshIfStale skipped: no podcasts');
      return;
    }

    AppLogger.log(
      'PodcastRefresh',
      'refreshIfStale start count=${collections.length}',
    );
    final repository = _ref.read(podcastRepositoryProvider);
    var failures = 0;

    for (final collection in collections) {
      try {
        await repository.refresh(collection.id, force: false);
      } catch (error, stackTrace) {
        failures += 1;
        AppLogger.log(
          'PodcastRefresh',
          'refresh failed collectionId=${collection.id} '
              'name=${collection.name} error=$error',
        );
        AppLogger.log('PodcastRefresh', stackTrace.toString());
      }
    }

    AppLogger.log(
      'PodcastRefresh',
      'refreshIfStale done count=${collections.length} failures=$failures',
    );
  }
}
