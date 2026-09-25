/// 真机/模拟器验证：匿名发现目录、Apple 搜索和 RSS 订阅，不读取模型密钥。
library;

import 'dart:io';
import 'package:echo_loop/main.dart' as app;
import 'package:echo_loop/config/app_capabilities.dart';
import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/community_collections/providers/discover_community_collections_provider.dart';
import 'package:echo_loop/features/community_collections/widgets/discover_entry_banner.dart';
import 'package:echo_loop/features/podcast/podcast_search_service.dart';
import 'package:echo_loop/features/podcast/podcast_preview_provider.dart';
import 'package:echo_loop/features/podcast/podcast_repository.dart';
import 'package:echo_loop/features/podcast/providers/discover_podcasts_provider.dart';
import 'package:echo_loop/features/podcast/screens/podcast_discovery_screen.dart';
import 'package:echo_loop/providers/collection_provider.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';
import 'package:echo_loop/providers/startup_bootstrap_provider.dart';
import 'package:echo_loop/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只对本次设备验收使用显式代理，不改系统设置或生产网络行为。
class _TestProxy extends HttpOverrides {
  _TestProxy(this.proxy);
  final String proxy;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY $proxy';
}

/// 等待真实状态完成；超时报出具体步骤，避免依赖固定网络延时。
Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String step,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Timeout: $step');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const proxy = String.fromEnvironment('RESOURCE_TEST_PROXY');
  if (proxy.isNotEmpty) HttpOverrides.global = _TestProxy(proxy);
  testWidgets('local anonymous resource discovery and podcast subscription', (
    tester,
  ) async {
    expect(isLocalEdition, isTrue);
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('onboarding_completed_at_ms')) {
      await prefs.setInt(
        'onboarding_completed_at_ms',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    app.main();
    await _until(
      tester,
      () => find.byType(app.EchoLoopApp).evaluate().isNotEmpty,
      'first frame',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(app.EchoLoopApp)),
    );
    await _until(
      tester,
      () => container.read(localStartupProvider).hasValue,
      'startup',
    );
    expect(container.read(isAuthenticatedProvider), isFalse);
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.collections);
    await _until(
      tester,
      () => find.byType(DiscoverEntryBanner).evaluate().isNotEmpty,
      'resource entry',
    );
    await tester.tap(find.byType(DiscoverEntryBanner));
    await _until(
      tester,
      () => !container.read(discoverCommunityCollectionsProvider).isLoading,
      'anonymous collections',
    );
    final collections = await container.read(
      discoverCommunityCollectionsProvider.future,
    );
    expect(collections.items, isNotEmpty);
    debugPrint('[LocalResources] anonymous community catalog loaded');

    router.push(AppRoutes.podcastSubscribe);
    await _until(
      tester,
      () =>
          find.byType(PodcastDiscoveryScreen).evaluate().isNotEmpty &&
          (container.read(discoverPodcastsProvider)?.isNotEmpty ?? false),
      'featured podcasts',
    );
    expect(container.read(discoverPodcastsProvider), isNotEmpty);
    final results = await PodcastSearchService().search(
      'BBC 6 Minute English',
      limit: 3,
    );
    expect(results, isNotEmpty);
    final podcast = results.first;
    await tester.enterText(find.byType(TextField).first, podcast.feedUrl);
    await _until(
      tester,
      () => container.read(podcastPreviewProvider(podcast.feedUrl)).hasValue,
      'RSS preview',
    );
    if (!container
        .read(collectionListProvider)
        .rawCollections
        .any((c) => c.podcastFeedUrl == podcast.feedUrl)) {
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    }
    await _until(
      tester,
      () => container
          .read(collectionListProvider)
          .rawCollections
          .any((c) => c.podcastFeedUrl == podcast.feedUrl),
      'anonymous subscription',
    );
    final subscribed = container
        .read(collectionListProvider)
        .rawCollections
        .firstWhere((c) => c.podcastFeedUrl == podcast.feedUrl);
    await container
        .read(podcastRepositoryProvider)
        .refresh(subscribed.id, force: true);
    await container.read(audioLibraryProvider.notifier).loadLibrary();
    expect(
      container
          .read(audioLibraryProvider)
          .audioItems
          .any((item) => item.podcastEpisodeGuid != null),
      isTrue,
    );
    // 与页面“去学习”一致使用 go，避免重复压入同一个 ShellRoute。
    router.go(AppRoutes.collectionDetail(subscribed.id));
    await _until(
      tester,
      () => find.byType(RefreshIndicator).evaluate().isNotEmpty,
      'podcast episodes',
    );
    expect(container.read(isAuthenticatedProvider), isFalse);
    expect(tester.takeException(), isNull);
    debugPrint(
      '[LocalResources] featured podcasts, Apple search, RSS subscription and episode list verified without login',
    );
  });
}
