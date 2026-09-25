import 'dart:async';

import 'package:dio/dio.dart';
import 'package:universal_io/io.dart';

import '../../services/app_logger.dart';
import 'audio_import_cancel.dart';

/// 可取消地把音频字节流写入目标文件，并在完成或失败时关闭流和文件。
Future<void> copyAudioImportStreamToFile({
  required Stream<List<int>> source,
  required File destination,
  CancelToken? cancelToken,
}) async {
  final traceId = cancelToken?.hashCode.toRadixString(16) ?? 'none';
  final stopwatch = Stopwatch()..start();
  var copiedBytes = 0;
  cancelToken?.throwIfCanceled();
  final output = destination.openWrite();
  final completed = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = source.listen(
    (chunk) {
      if (!(cancelToken?.isCancelled ?? false)) {
        output.add(chunk);
        copiedBytes += chunk.length;
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      AppLogger.log(
        'AudioImportCopy',
        'stream_error trace=$traceId error=${error.runtimeType}',
      );
      if (!completed.isCompleted) {
        completed.completeError(error, stackTrace);
      }
    },
    onDone: () {
      AppLogger.log(
        'AudioImportCopy',
        'stream_source_done trace=$traceId bytes=$copiedBytes',
      );
      output.flush().then((_) {
        if (!completed.isCompleted) completed.complete();
      }, onError: completed.completeError);
    },
  );
  final cancelFuture = cancelToken?.whenCancel;
  if (cancelFuture != null) {
    unawaited(
      cancelFuture.then((error) async {
        AppLogger.log('AudioImportCopy', 'stream_cancel trace=$traceId');
        await subscription.cancel();
        if (!completed.isCompleted) {
          completed.completeError(error, StackTrace.current);
        }
      }),
    );
  }

  try {
    await completed.future;
    cancelToken?.throwIfCanceled();
    AppLogger.log(
      'AudioImportCopy',
      'stream_complete trace=$traceId bytes=$copiedBytes '
          'elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
  } finally {
    await subscription.cancel();
    await output.close();
    AppLogger.log(
      'AudioImportCopy',
      'stream_closed trace=$traceId elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
  }
}
