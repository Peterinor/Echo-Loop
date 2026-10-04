import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/features/audio_import/audio_import_models.dart';
import 'package:echo_loop/features/audio_import/audio_import_provider.dart';
import 'package:echo_loop/features/audio_import/audio_import_service.dart';
import 'package:echo_loop/models/audio_item.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';

import '../../helpers/mock_providers.dart';

/// 伪 AudioImportService：只覆写单集下载，便于不触网验证 controller 行为。
class _FakeEpisodeDownloadService extends AudioImportService {
  _FakeEpisodeDownloadService({this.shouldThrow = false});

  final bool shouldThrow;
  String? lastDisplayName;

  @override
  Future<DownloadedAudio> downloadEpisodeToSandbox({
    required String url,
    required String displayName,
    String? enclosureType,
    CancelToken? cancelToken,
    AudioImportProgressCallback? onProgress,
  }) async {
    lastDisplayName = displayName;
    if (shouldThrow) {
      throw const AudioImportException(
        AudioImportFailureCode.network,
        'download failed',
      );
    }
    onProgress?.call(50, 100); // 触发一次进度回调
    return const DownloadedAudio(
      relativePath: 'audios/imported/episode.m4a',
      durationSeconds: 321,
      created: true,
      audioSha256: 'sha-xyz',
      originalAudioSha256: 'source-sha-xyz',
    );
  }
}

class _BlockingEpisodeDownloadService extends AudioImportService {
  final started = Completer<CancelToken>();

  @override
  Future<DownloadedAudio> downloadEpisodeToSandbox({
    required String url,
    required String displayName,
    String? enclosureType,
    CancelToken? cancelToken,
    AudioImportProgressCallback? onProgress,
  }) async {
    final token = cancelToken;
    if (token == null) throw StateError('cancel token is required');
    started.complete(token);
    await token.whenCancel;
    throw const AudioImportException(
      AudioImportFailureCode.canceled,
      'download canceled',
    );
  }
}

void main() {
  group('PodcastDownloadController.downloadPodcastEpisode', () {
    AudioItem podcastItem() =>
        createTestAudioItem(id: 'ep-1', name: 'Episode 1').copyWith(
          audioPath: null,
          totalDuration: 0,
          podcastEpisodeGuid: 'guid-1',
          podcastEnclosureUrl: 'https://example.com/episode.mp3',
          podcastEnclosureType: 'audio/mpeg',
        );

    ProviderContainer makeContainer(
      AudioImportService service,
      AudioItem item,
    ) {
      return ProviderContainer(
        overrides: [
          audioImportServiceProvider.overrideWithValue(service),
          audioLibraryProvider.overrideWith(
            () => TestAudioLibrary(AudioLibraryState(audioItems: [item])),
          ),
        ],
      );
    }

    test('成功下载就地更新现有条目，不新建条目', () async {
      final item = podcastItem();
      final service = _FakeEpisodeDownloadService();
      final container = makeContainer(service, item);
      addTearDown(container.dispose);

      final ok = await container
          .read(podcastDownloadControllerProvider.notifier)
          .downloadPodcastEpisode(item);

      expect(ok, isTrue);
      expect(service.lastDisplayName, item.name);
      final items = container.read(audioLibraryProvider).audioItems;
      // 仍只有一个条目（未产生孤儿）
      expect(items.length, 1);
      final updated = items.single;
      expect(updated.id, 'ep-1');
      expect(updated.audioPath, 'audios/imported/episode.m4a');
      expect(updated.totalDuration, 321);
      expect(updated.audioSha256, 'sha-xyz');
      expect(updated.originalAudioSha256, 'source-sha-xyz');
      // podcast 元字段保留
      expect(updated.podcastEpisodeGuid, 'guid-1');
      // 收尾回到 idle
      expect(
        container.read(podcastDownloadControllerProvider),
        isA<AudioImportIdle>(),
      );
    });

    test('下载失败置 AudioImportFailed 且不修改条目', () async {
      final item = podcastItem();
      final container = makeContainer(
        _FakeEpisodeDownloadService(shouldThrow: true),
        item,
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(podcastDownloadControllerProvider.notifier)
          .downloadPodcastEpisode(item);

      expect(ok, isFalse);
      final items = container.read(audioLibraryProvider).audioItems;
      expect(items.single.audioPath, isNull);
      expect(
        container.read(podcastDownloadControllerProvider),
        isA<AudioImportFailed>(),
      );
    });

    test('缺少 enclosure URL 时直接返回 false', () async {
      final item = createTestAudioItem(
        id: 'ep-2',
        name: 'No URL',
      ).copyWith(audioPath: null, podcastEpisodeGuid: 'guid-2');
      final container = makeContainer(_FakeEpisodeDownloadService(), item);
      addTearDown(container.dispose);

      final ok = await container
          .read(podcastDownloadControllerProvider.notifier)
          .downloadPodcastEpisode(item);

      expect(ok, isFalse);
    });

    test('取消下载会清空状态、取消 token，并忽略迟到结果', () async {
      final item = podcastItem();
      final service = _BlockingEpisodeDownloadService();
      final container = makeContainer(service, item);
      addTearDown(container.dispose);

      final notifier = container.read(
        podcastDownloadControllerProvider.notifier,
      );
      final download = notifier.downloadPodcastEpisode(item);
      final token = await service.started.future;

      await notifier.cancel();

      expect(token.isCancelled, isTrue);
      expect(
        container.read(podcastDownloadControllerProvider),
        isA<AudioImportIdle>(),
      );
      expect(await download, isFalse);
      expect(
        container.read(audioLibraryProvider).audioItems.single.audioPath,
        isNull,
      );
    });

    test('播客下载失败不污染链接导入 controller 状态（两条流程独立）', () async {
      final item = podcastItem();
      final container = makeContainer(
        _FakeEpisodeDownloadService(shouldThrow: true),
        item,
      );
      addTearDown(container.dispose);

      await container
          .read(podcastDownloadControllerProvider.notifier)
          .downloadPodcastEpisode(item);

      // 播客下载置 Failed，但链接导入 controller 仍为初始 idle。
      expect(
        container.read(podcastDownloadControllerProvider),
        isA<AudioImportFailed>(),
      );
      expect(
        container.read(audioImportControllerProvider),
        isA<AudioImportIdle>(),
      );
    });
  });
}
