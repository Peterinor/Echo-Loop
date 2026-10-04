import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'app_logger.dart';
import 'media_kit_debug_initializer.dart';

const _durationDebugLogTag = 'MediaDuration';

/// 时长探测所需的最小播放器接口，便于用事件流测试异步元数据行为。
abstract interface class DurationProbePlayer {
  Duration get duration;

  Stream<Duration> get durationStream;

  Stream<String> get errorStream;

  Future<void> openPaused(String filePath);

  Future<void> dispose();
}

typedef DurationProbePlayerFactory = DurationProbePlayer Function();

enum _ProbeOutcomeType { duration, mediaError, timeout }

class _ProbeOutcome {
  const _ProbeOutcome.duration(this.value) : type = _ProbeOutcomeType.duration;

  const _ProbeOutcome.mediaError()
    : type = _ProbeOutcomeType.mediaError,
      value = Duration.zero;

  const _ProbeOutcome.timeout()
    : type = _ProbeOutcomeType.timeout,
      value = Duration.zero;

  final _ProbeOutcomeType type;
  final Duration value;
}

/// 用 media_kit 读取媒体文件时长，不开始播放；异常和超时以 null 返回。
class MediaKitDurationProbe {
  MediaKitDurationProbe({
    Duration timeout = const Duration(seconds: 10),
    DurationProbePlayerFactory? playerFactory,
    void Function()? ensureInitialized,
  }) : _timeout = timeout,
       _playerFactory = playerFactory ?? _createPlayer,
       _ensureInitialized = ensureInitialized ?? ensureMediaKitInitialized;

  final Duration _timeout;
  final DurationProbePlayerFactory _playerFactory;
  final void Function() _ensureInitialized;

  /// 打开本地文件后等待正时长事件，探测最多等待配置的时长（默认 10 秒）。
  Future<Duration?> read(String filePath, {String? traceId}) async {
    final stopwatch = Stopwatch()..start();
    var phase = 'initialize';
    DurationProbePlayer? player;
    StreamSubscription<Duration>? durationSubscription;
    StreamSubscription<String>? errorSubscription;
    final outcome = Completer<_ProbeOutcome>();

    try {
      _ensureInitialized();
      player = _playerFactory();
      durationSubscription = player.durationStream.listen(
        (duration) {
          if (duration > Duration.zero && !outcome.isCompleted) {
            outcome.complete(_ProbeOutcome.duration(duration));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!outcome.isCompleted) {
            outcome.complete(const _ProbeOutcome.mediaError());
          }
        },
      );
      errorSubscription = player.errorStream.listen(
        (_) {
          if (!outcome.isCompleted) {
            outcome.complete(const _ProbeOutcome.mediaError());
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!outcome.isCompleted) {
            outcome.complete(const _ProbeOutcome.mediaError());
          }
        },
      );

      phase = 'open';
      await player.openPaused(filePath).timeout(_timeout);

      final currentDuration = player.duration;
      if (currentDuration > Duration.zero) {
        _log(
          traceId,
          'event=media_duration_probe_complete trace=${traceId ?? 'none'} '
          'outcome=positive '
          'durationMs=${currentDuration.inMilliseconds} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        return currentDuration;
      }

      phase = 'wait_for_duration';
      final remaining = _timeout - stopwatch.elapsed;
      final result = remaining <= Duration.zero
          ? const _ProbeOutcome.timeout()
          : await outcome.future.timeout(
              remaining,
              onTimeout: () => const _ProbeOutcome.timeout(),
            );
      switch (result.type) {
        case _ProbeOutcomeType.duration:
          _log(
            traceId,
            'event=media_duration_probe_complete trace=${traceId ?? 'none'} '
            'outcome=positive '
            'durationMs=${result.value.inMilliseconds} '
            'elapsedMs=${stopwatch.elapsedMilliseconds}',
          );
          return result.value;
        case _ProbeOutcomeType.mediaError:
          _log(
            traceId,
            'event=media_duration_probe_failed '
            'trace=${traceId ?? 'none'} phase=media_error '
            'errorType=MediaKitStreamError '
            'elapsedMs=${stopwatch.elapsedMilliseconds}',
            always: true,
          );
          return null;
        case _ProbeOutcomeType.timeout:
          _log(
            traceId,
            'event=media_duration_probe_failed '
            'trace=${traceId ?? 'none'} phase=$phase '
            'errorType=TimeoutException '
            'elapsedMs=${stopwatch.elapsedMilliseconds}',
            always: true,
          );
          return null;
      }
    } on Object catch (error) {
      _log(
        traceId,
        'event=media_duration_probe_failed '
        'trace=${traceId ?? 'none'} phase=$phase '
        'errorType=${error.runtimeType} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        always: true,
      );
      return null;
    } finally {
      await _cancelSubscription(durationSubscription, 'duration', traceId);
      await _cancelSubscription(errorSubscription, 'error', traceId);
      final activePlayer = player;
      if (activePlayer != null) {
        try {
          await activePlayer.dispose();
        } on Object catch (error) {
          _log(
            traceId,
            'event=media_duration_probe_dispose_failed '
            'trace=${traceId ?? 'none'} '
            'errorType=${error.runtimeType}',
            always: true,
          );
        }
      }
    }
  }

  static DurationProbePlayer _createPlayer() =>
      _MediaKitDurationPlayer(Player());

  Future<void> _cancelSubscription<T>(
    StreamSubscription<T>? subscription,
    String streamName,
    String? traceId,
  ) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } on Object catch (error) {
      _log(
        traceId,
        'event=media_duration_probe_subscription_cancel_failed '
        'trace=${traceId ?? 'none'} '
        'stream=$streamName errorType=${error.runtimeType}',
        always: true,
      );
    }
  }

  void _log(String? traceId, String message, {bool always = false}) {
    if (traceId == null && !always) return;
    AppLogger.log(_durationDebugLogTag, message);
  }
}

class _MediaKitDurationPlayer implements DurationProbePlayer {
  _MediaKitDurationPlayer(this._player);

  final Player _player;

  @override
  Duration get duration => _player.state.duration;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Future<void> openPaused(String filePath) =>
      _player.open(Media(filePath), play: false);

  @override
  Future<void> dispose() => _player.dispose();
}
