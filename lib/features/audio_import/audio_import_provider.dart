import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/audio_item.dart';
import '../../providers/audio_library_provider.dart';
import '../../providers/collection_provider.dart';
import '../../providers/download_provider.dart';
import 'audio_import_models.dart';
import 'audio_import_service.dart';

part 'audio_import_provider.g.dart';

@riverpod
AudioImportService audioImportService(AudioImportServiceRef ref) {
  return AudioImportService(
    backgroundDownloader: ref.watch(backgroundFileDownloadServiceProvider),
  );
}

@riverpod
class AudioImportController extends _$AudioImportController {
  CancelToken? _cancelToken;
  int _sessionId = 0;

  @override
  AudioImportState build() {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    return const AudioImportIdle();
  }

  Future<AudioItem?> importFromUrl(String url, {String? collectionId}) async {
    if (state is AudioImportDownloading || state is AudioImportSaving) {
      return null;
    }

    _sessionId++;
    final sid = _sessionId;
    _cancelToken = CancelToken();
    state = const AudioImportResolving();

    try {
      final item = await ref
          .read(audioImportServiceProvider)
          .importFromUrl(
            url: url,
            audioLibrary: ref.read(audioLibraryProvider.notifier),
            audioLibraryState: ref.read(audioLibraryProvider),
            collectionList: collectionId == null
                ? null
                : ref.read(collectionListProvider.notifier),
            collectionState: collectionId == null
                ? null
                : ref.read(collectionListProvider),
            collectionId: collectionId,
            cancelToken: _cancelToken,
            onProgress: (received, total) {
              if (sid != _sessionId) return;
              final progress = total == null || total <= 0
                  ? -1.0
                  : received / total;
              state = AudioImportDownloading(
                displayName: url,
                progress: progress,
                receivedBytes: received,
                totalBytes: total,
              );
            },
          );
      if (sid != _sessionId) return null;
      state = AudioImportCompleted(item);
      // 后台检测内容有效性（不阻塞返回）。
      unawaited(
        ref.read(audioLibraryProvider.notifier).checkAudioContent(item.id),
      );
      return item;
    } on AudioImportException catch (e) {
      if (sid != _sessionId) return null;
      state = e.code == AudioImportFailureCode.canceled
          ? const AudioImportIdle()
          : AudioImportFailed(e);
      return null;
    } catch (e) {
      if (sid != _sessionId) return null;
      state = AudioImportFailed(
        AudioImportException(
          AudioImportFailureCode.unknown,
          'Audio import failed',
          e,
        ),
      );
      return null;
    } finally {
      if (sid == _sessionId) _cancelToken = null;
    }
  }

  Future<void> cancel() async {
    _cancelToken?.cancel('user-cancelled');
  }

  void reset() {
    if (state is AudioImportDownloading || state is AudioImportSaving) return;
    state = const AudioImportIdle();
  }
}

/// Podcast 单集懒下载控制器。
///
/// 与 [AudioImportController]（从链接导入）**完全独立**：两条流程各自持有状态，
/// 一方的下载失败不会污染另一方的 UI（避免播客下载失败后，打开「从链接导入」
/// 误显下载失败提示）。复用同一套 [AudioImportState] 模型类。
@riverpod
class PodcastDownloadController extends _$PodcastDownloadController {
  CancelToken? _cancelToken;
  int _sessionId = 0;

  @override
  AudioImportState build() {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    return const AudioImportIdle();
  }

  /// Podcast 单集懒下载：下载 enclosure 到沙盒并**就地更新现有占位条目**，
  /// 不新建 [AudioItem]（避免资源库出现重复孤儿条目）。
  ///
  /// 成功返回 true 并已写回 audioPath / 时长 / 指纹；失败返回 false 并置
  /// [AudioImportFailed]。state 的 displayName 取 enclosure URL，与列表项的
  /// 行内进度条匹配逻辑一致。
  Future<bool> downloadPodcastEpisode(AudioItem item) async {
    if (state is AudioImportDownloading || state is AudioImportSaving) {
      return false;
    }
    final enclosureUrl = item.podcastEnclosureUrl;
    if (enclosureUrl == null || enclosureUrl.isEmpty) return false;

    _sessionId++;
    final sid = _sessionId;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    // 立即进入下载态，保证行内进度条第一时间出现（不定进度）。
    state = AudioImportDownloading(displayName: enclosureUrl, progress: -1.0);

    try {
      final result = await ref
          .read(audioImportServiceProvider)
          .downloadEpisodeToSandbox(
            url: enclosureUrl,
            enclosureType: item.podcastEnclosureType,
            cancelToken: cancelToken,
            onProgress: (received, total) {
              if (sid != _sessionId) return;
              final progress = total == null || total <= 0
                  ? -1.0
                  : received / total;
              state = AudioImportDownloading(
                displayName: enclosureUrl,
                progress: progress,
                receivedBytes: received,
                totalBytes: total,
              );
            },
          );
      if (sid != _sessionId) {
        await ref
            .read(audioImportServiceProvider)
            .discardDownloadedAudio(result);
        return false;
      }

      // 解码失败（durationSeconds==0）不再回退 RSS 时长：宁可不显示，也不展示
      // 假时长。内容检测另用 FFmpeg 短解码和波形判断，不依赖此时长。
      await ref
          .read(audioLibraryProvider.notifier)
          .updateAudioItem(
            item.copyWith(
              audioPath: result.relativePath,
              totalDuration: result.durationSeconds,
              audioSha256: result.audioSha256,
              originalAudioSha256: result.originalAudioSha256,
            ),
          );
      state = const AudioImportIdle();
      // 后台检测内容有效性（复用已算出的解码时长，不阻塞返回）。
      unawaited(
        ref
            .read(audioLibraryProvider.notifier)
            .checkAudioContent(
              item.id,
              decodedDurationSeconds: result.durationSeconds,
            ),
      );
      return true;
    } on AudioImportException catch (e) {
      if (sid != _sessionId) return false;
      state = AudioImportFailed(e);
      return false;
    } catch (e) {
      if (sid != _sessionId) return false;
      state = AudioImportFailed(
        AudioImportException(
          AudioImportFailureCode.unknown,
          'Podcast episode download failed',
          e,
        ),
      );
      return false;
    } finally {
      if (sid == _sessionId) _cancelToken = null;
    }
  }

  /// 取消播客单集下载，并让迟到的下载结果失效。
  Future<void> cancel() async {
    if (state is! AudioImportDownloading && state is! AudioImportSaving) {
      return;
    }
    _sessionId++;
    _cancelToken?.cancel('user-cancelled');
    _cancelToken = null;
    state = const AudioImportIdle();
  }

  void reset() {
    if (state is AudioImportDownloading || state is AudioImportSaving) return;
    state = const AudioImportIdle();
  }
}
