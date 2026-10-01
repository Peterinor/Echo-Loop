import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../services/app_logger.dart';
import '../services/media_kit_duration_probe.dart';
import 'app_data_dir.dart';

const _durationDebugLogTag = 'MediaDuration';
final _defaultMediaKitDurationProbe = MediaKitDurationProbe();

typedef MediaFileDurationProbe =
    Future<Duration?> Function(String filePath, {String? traceId});
typedef MediaDurationSecondsReader =
    Future<int> Function(String relativePath, {String? traceId});

/// 通过同一个 media_kit 探测器读取音频和视频素材的时长。
class MediaDurationReader {
  MediaDurationReader({
    Future<Directory> Function()? resolveDataDirectory,
    MediaFileDurationProbe? mediaProbe,
  }) : _resolveDataDirectory = resolveDataDirectory ?? getAppDataDirectory,
       _mediaProbe = mediaProbe ?? _defaultMediaKitDurationProbe.read;

  final Future<Directory> Function() _resolveDataDirectory;
  final MediaFileDurationProbe _mediaProbe;

  /// 读取相对应用数据目录的素材时长；失败时返回 0，不阻断导入。
  Future<int> read(String relativePath, {String? traceId}) async {
    final stopwatch = Stopwatch()..start();
    final extension = path.extension(relativePath);
    if (traceId != null) {
      AppLogger.log(
        _durationDebugLogTag,
        'event=probe_begin trace=$traceId extension=$extension '
        'backend=media_kit platform=${defaultTargetPlatform.name}',
      );
    }

    var phase = 'resolve_data_directory';
    try {
      final dataDir = await _resolveDataDirectory();
      final fullPath = path.join(dataDir.path, relativePath);
      phase = 'media_kit_probe';
      final duration = await _mediaProbe(fullPath, traceId: traceId);
      final seconds = duration?.inSeconds ?? 0;
      if (traceId != null) {
        AppLogger.log(
          _durationDebugLogTag,
          'event=probe_complete trace=$traceId outcome=${duration == null
              ? 'empty'
              : seconds > 0
              ? 'positive'
              : 'zero'} '
          'durationMs=${duration?.inMilliseconds ?? 0} seconds=$seconds '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
      }
      return seconds;
    } on Object catch (error) {
      AppLogger.log(
        _durationDebugLogTag,
        'event=probe_failed trace=${traceId ?? 'none'} phase=$phase '
        'backend=media_kit errorType=${error.runtimeType} '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return 0;
    }
  }
}

final _defaultMediaDurationReader = MediaDurationReader();

/// 读取音频或视频素材时长（秒）。
///
/// [relativePath] 相对于应用数据目录的素材路径。
/// 失败时返回 0，不阻断导入流程。[traceId] 非空时记录不包含完整路径的诊断日志。
Future<int> getMediaDurationSeconds(String relativePath, {String? traceId}) =>
    _defaultMediaDurationReader.read(relativePath, traceId: traceId);
