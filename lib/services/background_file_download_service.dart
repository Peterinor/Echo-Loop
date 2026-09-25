import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'app_logger.dart';
import '../utils/app_data_dir.dart';

typedef BackgroundFileDownloadProgress =
    void Function(int receivedBytes, int? totalBytes);

/// 后台文件任务的最终状态。
enum BackgroundDownloadStatus { complete, notFound, failed, canceled }

/// 下载器返回的最终结果，保留平台错误供业务层映射。
class BackgroundDownloadResult {
  const BackgroundDownloadResult({
    required this.status,
    this.statusCode,
    this.receivedBytes,
    this.expectedBytes,
    this.contentType,
    this.errorDomain,
    this.errorCode,
    this.message,
    this.cause,
    this.isStorageFailure = false,
  });

  final BackgroundDownloadStatus status;
  final int? statusCode;
  final int? receivedBytes;
  final int? expectedBytes;
  final String? contentType;
  final String? errorDomain;
  final int? errorCode;
  final String? message;
  final Object? cause;
  final bool isStorageFailure;
}

/// 适配器可替换接口，供业务测试使用，不暴露插件状态类型。
abstract interface class BackgroundDownloadRunner {
  /// 将任务交给平台下载队列并等待终态。
  Future<BackgroundDownloadResult> enqueue({
    required Uri uri,
    required String savePath,
    required Map<String, String> headers,
    required BackgroundFileDownloadProgress? onProgress,
    required CancelToken? cancelToken,
  });
}

/// 文件后台下载服务。
///
/// 应用层只依据平台下载任务的终态和目标文件是否存在判断成功，不拿来源
/// 元数据中的文件大小作为失败条件。
class BackgroundFileDownloadService {
  BackgroundFileDownloadService({
    BackgroundDownloadRunner? runner,
    Future<Directory> Function()? resolveDataDir,
  }) : _runner = runner ?? _defaultRunner(resolveDataDir);

  static BackgroundDownloadRunner _defaultRunner(
    Future<Directory> Function()? resolveDataDir,
  ) {
    final directoryResolver = resolveDataDir ?? getAppDataDirectory;
    if (Platform.isMacOS) {
      return MacOSSystemDownloadRunner(resolveDataDir: directoryResolver);
    }
    return PluginBackgroundDownloadRunner(resolveDataDir: directoryResolver);
  }

  final BackgroundDownloadRunner _runner;

  /// 下载文件到应用数据目录中的 [savePath]。
  Future<void> download({
    required Uri uri,
    required String savePath,
    Map<String, String> headers = const <String, String>{},
    CancelToken? cancelToken,
    BackgroundFileDownloadProgress? onProgress,
  }) async {
    AppLogger.log(
      'BackgroundFileDownload',
      'download started host=${uri.host} url=${_safeDownloadUrl(uri)} '
          'file=${p.basename(savePath)}',
    );
    try {
      onProgress?.call(0, null);
      final BackgroundDownloadResult result;
      try {
        result = await _runner.enqueue(
          uri: uri,
          savePath: savePath,
          headers: headers,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      } on FileSystemException catch (error) {
        throw BackgroundFileDownloadException(
          'Failed to save downloaded file.',
          isStorageFailure: true,
          cause: error,
        );
      }

      switch (result.status) {
        case BackgroundDownloadStatus.complete:
          final file = File(savePath);
          if (!await file.exists()) {
            throw BackgroundFileDownloadException(
              'Download completed without creating the target file.',
              cause: result.cause,
            );
          }
          final actualBytes = await file.length();
          AppLogger.log(
            'BackgroundFileDownload',
            'download complete host=${uri.host} url=${_safeDownloadUrl(uri)} '
                'file=${p.basename(savePath)} '
                'statusCode=${result.statusCode ?? "(null)"} '
                'bytes=$actualBytes '
                'expectedBytes=${result.expectedBytes ?? "(unknown)"}'
                '${result.contentType == null ? '' : ' contentType=${result.contentType}'}',
          );
        case BackgroundDownloadStatus.notFound:
          throw BackgroundFileDownloadException(
            result.message ?? 'Download URL was not found.',
            statusCode: result.statusCode ?? 404,
            cause: result.cause,
            receivedBytes: result.receivedBytes,
            expectedBytes: result.expectedBytes,
            errorDomain: result.errorDomain,
            errorCode: result.errorCode,
          );
        case BackgroundDownloadStatus.failed:
          throw BackgroundFileDownloadException(
            result.message ?? 'Background download failed.',
            statusCode: result.statusCode,
            isStorageFailure: result.isStorageFailure,
            cause: result.cause,
            receivedBytes: result.receivedBytes,
            expectedBytes: result.expectedBytes,
            errorDomain: result.errorDomain,
            errorCode: result.errorCode,
          );
        case BackgroundDownloadStatus.canceled:
          throw BackgroundFileDownloadException(
            result.message ?? 'Download canceled.',
            isCanceled: true,
            cause: result.cause,
            receivedBytes: result.receivedBytes,
            expectedBytes: result.expectedBytes,
            errorDomain: result.errorDomain,
            errorCode: result.errorCode,
          );
      }
    } on Object catch (error) {
      final details = switch (error) {
        BackgroundFileDownloadException(
          :final statusCode,
          :final isStorageFailure,
          :final isCanceled,
          :final receivedBytes,
          :final expectedBytes,
          :final errorDomain,
          :final errorCode,
          :final message,
          :final cause,
        ) =>
          ' statusCode=${statusCode ?? "(null)"} storage=$isStorageFailure '
              'canceled=$isCanceled bytes=${receivedBytes ?? "(unknown)"} '
              'expectedBytes=${expectedBytes ?? "(unknown)"}'
              '${errorDomain == null ? '' : ' errorDomain=$errorDomain'}'
              '${errorCode == null ? '' : ' errorCode=$errorCode'} '
              'message=${_safeDiagnosticText(message)}'
              '${cause == null ? '' : ' causeType=${cause.runtimeType} cause=${_safeDiagnosticText(cause.toString())}'}',
        _ => ' detail=${_safeDiagnosticText(error.toString())}',
      };
      AppLogger.log(
        'BackgroundFileDownload',
        'download failed host=${uri.host} url=${_safeDownloadUrl(uri)} '
            'file=${p.basename(savePath)} '
            'errorType=${error.runtimeType}$details',
      );
      rethrow;
    }
  }
}

/// 应用层下载错误，带 HTTP 状态及取消语义供现有功能映射。
class BackgroundFileDownloadException implements Exception {
  const BackgroundFileDownloadException(
    this.message, {
    this.statusCode,
    this.isCanceled = false,
    this.isStorageFailure = false,
    this.receivedBytes,
    this.expectedBytes,
    this.errorDomain,
    this.errorCode,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final bool isCanceled;
  final bool isStorageFailure;
  final int? receivedBytes;
  final int? expectedBytes;
  final String? errorDomain;
  final int? errorCode;
  final Object? cause;

  @override
  String toString() => 'BackgroundFileDownloadException($message)';
}

/// `background_downloader` 的平台队列适配器。
class PluginBackgroundDownloadRunner implements BackgroundDownloadRunner {
  PluginBackgroundDownloadRunner({
    required Future<Directory> Function() resolveDataDir,
    FileDownloader? downloader,
    Uuid? uuid,
  }) : _resolveDataDir = resolveDataDir,
       _downloader = downloader ?? FileDownloader(),
       _uuid = uuid ?? const Uuid();

  static const _group = 'echo-loop-user-files';

  final Future<Directory> Function() _resolveDataDir;
  final FileDownloader _downloader;
  final Uuid _uuid;
  final Map<String, _PendingDownload> _pending = {};
  Future<void>? _initialization;

  @override
  Future<BackgroundDownloadResult> enqueue({
    required Uri uri,
    required String savePath,
    required Map<String, String> headers,
    required BackgroundFileDownloadProgress? onProgress,
    required CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return const BackgroundDownloadResult(
        status: BackgroundDownloadStatus.canceled,
        message: 'Download canceled before enqueue.',
      );
    }

    await _ensureInitialized();
    final dataDir = await _resolveDataDir();
    final rootPath = p.normalize(dataDir.path);
    final targetPath = p.normalize(savePath);
    if (!p.isWithin(rootPath, targetPath)) {
      throw ArgumentError.value(
        savePath,
        'savePath',
        'Download destination must be inside the application data directory.',
      );
    }
    final relativePath = p.relative(targetPath, from: rootPath);
    final directory = p.dirname(relativePath);
    await File(targetPath).parent.create(recursive: true);

    final taskId = _uuid.v4();
    final completer = Completer<BackgroundDownloadResult>();
    _pending[taskId] = _PendingDownload(
      completer: completer,
      onProgress: onProgress,
      host: uri.host,
      safeUrl: _safeDownloadUrl(uri),
      fileName: p.basename(relativePath),
    );
    final task = DownloadTask(
      taskId: taskId,
      url: uri.toString(),
      filename: p.basename(relativePath),
      directory: directory == '.' ? '' : directory,
      baseDirectory: BaseDirectory.applicationSupport,
      group: _group,
      headers: headers,
      updates: Updates.statusAndProgress,
      allowPause: false,
      displayName: p.basename(relativePath),
    );

    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel
            .then((_) async {
              await _downloader.cancelTaskWithId(taskId);
            })
            .catchError((Object error) {
              AppLogger.log(
                'BackgroundFileDownload',
                'failed to cancel task: $error',
              );
            }),
      );
    }

    try {
      final accepted = await _downloader.enqueue(task);
      AppLogger.log(
        'BackgroundFileDownload',
        'task submitted host=${uri.host} url=${_safeDownloadUrl(uri)} '
            'taskId=$taskId accepted=$accepted',
      );
      if (!accepted && !completer.isCompleted) {
        completer.complete(
          const BackgroundDownloadResult(
            status: BackgroundDownloadStatus.failed,
            message: 'Could not enqueue background download.',
          ),
        );
      }
      return await completer.future;
    } finally {
      _pending.remove(taskId);
    }
  }

  Future<void> _ensureInitialized() {
    final initialization = _initialization;
    if (initialization != null) return initialization;
    final future = _initialize();
    _initialization = future;
    return future.catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    AppLogger.log(
      'BackgroundFileDownload',
      'initializing plugin group=$_group',
    );
    try {
      _downloader.configureNotificationForGroup(
        _group,
        running: const TaskNotification('Downloading', '{displayName}'),
        complete: const TaskNotification('Download complete', '{displayName}'),
        error: const TaskNotification('Download failed', '{displayName}'),
        progressBar: true,
      );
      _downloader.registerCallbacks(
        group: _group,
        taskStatusCallback: _handleStatus,
        taskProgressCallback: _handleProgress,
      );
      await _downloader.trackTasksInGroup(_group);
      await _downloader.start(
        doTrackTasks: false,
        doRescheduleKilledTasks: false,
      );
      AppLogger.log('BackgroundFileDownload', 'plugin ready group=$_group');
    } on Object catch (error) {
      AppLogger.log(
        'BackgroundFileDownload',
        'plugin initialization failed errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  void _handleStatus(TaskStatusUpdate update) {
    final pending = _pending[update.task.taskId];
    if (pending == null || pending.completer.isCompleted) return;
    final exception = update.exception;
    AppLogger.log(
      'BackgroundFileDownload',
      'task status=${update.status.name} host=${pending.host} '
          'url=${pending.safeUrl} '
          'file=${pending.fileName} taskId=${update.task.taskId} '
          'statusCode=${update.responseStatusCode ?? "(null)"} '
          'bytes=${pending.receivedBytes ?? "(unknown)"} '
          'expectedBytes=${pending.expectedBytes ?? "(unknown)"} '
          'durationMs=${pending.stopwatch.elapsedMilliseconds}'
          '${exception == null ? '' : ' error=${_safeTaskException(exception)}'}',
    );

    final result = switch (update.status) {
      TaskStatus.complete => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.complete,
        statusCode: update.responseStatusCode,
        receivedBytes: pending.receivedBytes,
        expectedBytes: pending.expectedBytes,
      ),
      TaskStatus.notFound => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.notFound,
        statusCode: update.responseStatusCode ?? 404,
        message: 'Download URL was not found.',
        cause: update.exception,
        receivedBytes: pending.receivedBytes,
        expectedBytes: pending.expectedBytes,
      ),
      TaskStatus.failed => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.failed,
        statusCode:
            update.responseStatusCode ??
            switch (update.exception) {
              TaskHttpException(:final httpResponseCode) => httpResponseCode,
              _ => null,
            },
        message: 'Background download failed.',
        cause: update.exception,
        isStorageFailure: _isInsufficientStorage(update.exception),
        receivedBytes: pending.receivedBytes,
        expectedBytes: pending.expectedBytes,
      ),
      TaskStatus.canceled => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.canceled,
        message: 'Download canceled.',
        cause: update.exception,
      ),
      _ => null,
    };
    if (result != null) pending.completer.complete(result);
  }

  /// 插件在部分平台会用文件系统异常包装网络错误，因此只识别明确的空间不足描述。
  bool _isInsufficientStorage(TaskException? exception) {
    final description = exception?.description.toLowerCase();
    if (description == null) return false;
    return const <String>[
      'no space left',
      'enospc',
      'errno = 28',
      'errno 28',
      'insufficient space',
      'not enough space',
      'disk full',
      'storage full',
    ].any(description.contains);
  }

  String _safeTaskException(TaskException exception) {
    final description = exception.description.replaceAll(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      '<url>',
    );
    return '${exception.exceptionType}: $description';
  }

  void _handleProgress(TaskProgressUpdate update) {
    final pending = _pending[update.task.taskId];
    if (pending == null) return;
    final expectedBytes = update.expectedFileSize > 0
        ? update.expectedFileSize
        : null;
    pending.expectedBytes = expectedBytes;
    pending.receivedBytes = expectedBytes == null
        ? null
        : (update.progress * expectedBytes)
              .round()
              .clamp(0, expectedBytes)
              .toInt();
    final callback = pending.onProgress;
    if (callback == null || update.progress < 0) return;
    final receivedBytes = expectedBytes == null
        ? 0
        : (update.progress * expectedBytes)
              .round()
              .clamp(0, expectedBytes)
              .toInt();
    callback(receivedBytes, expectedBytes);
  }
}

class _PendingDownload {
  _PendingDownload({
    required this.completer,
    required this.onProgress,
    required this.host,
    required this.safeUrl,
    required this.fileName,
  }) : stopwatch = Stopwatch()..start();

  final Completer<BackgroundDownloadResult> completer;
  final BackgroundFileDownloadProgress? onProgress;
  final String host;
  final String safeUrl;
  final String fileName;
  final Stopwatch stopwatch;
  int? receivedBytes;
  int? expectedBytes;
}

/// macOS 原生下载桥接，可在 Dart 单元测试中替换。
abstract interface class MacOSSystemDownloadClient {
  /// 使用系统网络栈下载文件，并通过 [onProgress] 回报进度。
  Future<BackgroundDownloadResult> download({
    required Uri uri,
    required String savePath,
    required Map<String, String> headers,
    required BackgroundFileDownloadProgress? onProgress,
    required CancelToken? cancelToken,
  });
}

/// macOS 下载适配器。
///
/// macOS 使用 URLSession 默认配置，由系统决定代理和网络路由；其他平台继续
/// 使用 `background_downloader` 自己的原生后台任务实现。
class MacOSSystemDownloadRunner implements BackgroundDownloadRunner {
  MacOSSystemDownloadRunner({
    required Future<Directory> Function() resolveDataDir,
    MacOSSystemDownloadClient? client,
  }) : _resolveDataDir = resolveDataDir,
       _client = client ?? const _MethodChannelMacOSSystemDownloadClient();

  final Future<Directory> Function() _resolveDataDir;
  final MacOSSystemDownloadClient _client;

  @override
  Future<BackgroundDownloadResult> enqueue({
    required Uri uri,
    required String savePath,
    required Map<String, String> headers,
    required BackgroundFileDownloadProgress? onProgress,
    required CancelToken? cancelToken,
  }) async {
    final rootPath = p.normalize((await _resolveDataDir()).path);
    final targetPath = p.normalize(savePath);
    if (!p.isWithin(rootPath, targetPath)) {
      throw ArgumentError.value(
        savePath,
        'savePath',
        'Download destination must be inside the application data directory.',
      );
    }
    return _client.download(
      uri: uri,
      savePath: targetPath,
      headers: headers,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

class _MethodChannelMacOSSystemDownloadClient
    implements MacOSSystemDownloadClient {
  const _MethodChannelMacOSSystemDownloadClient();

  static const _methodChannel = MethodChannel('top.echo-loop/system_download');
  static const _eventChannel = EventChannel(
    'top.echo-loop/system_download/events',
  );

  static final _uuid = const Uuid();
  static final Map<String, _MacOSPendingDownload> _pending = {};
  static StreamSubscription<Object?>? _updates;

  @override
  Future<BackgroundDownloadResult> download({
    required Uri uri,
    required String savePath,
    required Map<String, String> headers,
    required BackgroundFileDownloadProgress? onProgress,
    required CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      return const BackgroundDownloadResult(
        status: BackgroundDownloadStatus.canceled,
        message: 'Download canceled before enqueue.',
      );
    }
    await _ensureListening();

    final taskId = _uuid.v4();
    final completer = Completer<BackgroundDownloadResult>();
    _pending[taskId] = _MacOSPendingDownload(
      completer: completer,
      onProgress: onProgress,
      host: uri.host,
      safeUrl: _safeDownloadUrl(uri),
      fileName: p.basename(savePath),
    );
    AppLogger.log(
      'BackgroundFileDownload',
      'system download started host=${uri.host} '
          'url=${_safeDownloadUrl(uri)} '
          'file=${p.basename(savePath)} taskId=$taskId',
    );

    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancel.then((_) => _requestCancel(taskId)).catchError((
          Object error,
        ) {
          AppLogger.log(
            'BackgroundFileDownload',
            'failed to cancel system download errorType=${error.runtimeType}',
          );
        }),
      );
    }

    try {
      final accepted = await _methodChannel.invokeMethod<bool>(
        'startDownload',
        <String, Object?>{
          'taskId': taskId,
          'url': uri.toString(),
          'savePath': savePath,
          'headers': headers,
        },
      );
      if (accepted != true && !completer.isCompleted) {
        completer.complete(
          const BackgroundDownloadResult(
            status: BackgroundDownloadStatus.failed,
            message: 'Could not enqueue system download.',
          ),
        );
      } else if (accepted == true) {
        final pending = _pending[taskId];
        if (pending != null) {
          pending.started = true;
          if (pending.cancelRequested || (cancelToken?.isCancelled ?? false)) {
            await _requestCancel(taskId);
          }
        }
      }
      return await completer.future;
    } on Object catch (error) {
      if (!completer.isCompleted) {
        completer.complete(
          BackgroundDownloadResult(
            status: BackgroundDownloadStatus.failed,
            message: 'Could not start system download.',
            cause: error,
          ),
        );
      }
      return await completer.future;
    } finally {
      _pending.remove(taskId);
    }
  }

  Future<void> _ensureListening() async {
    if (_updates != null) return;
    _updates = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        for (final pending in _pending.values) {
          if (!pending.completer.isCompleted) {
            pending.completer.complete(
              BackgroundDownloadResult(
                status: BackgroundDownloadStatus.failed,
                message: 'System download event stream failed.',
                cause: error,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _requestCancel(String taskId) async {
    final pending = _pending[taskId];
    if (pending == null || pending.completer.isCompleted) return;
    pending.cancelRequested = true;
    if (!pending.started) return;
    await _methodChannel.invokeMethod<bool>('cancelDownload', <String, Object?>{
      'taskId': taskId,
    });
  }

  void _handleEvent(Object? event) {
    if (event is! Map<Object?, Object?>) return;
    final update = event;
    final taskId = update['taskId'];
    final status = update['status'];
    if (taskId is! String || status is! String) return;
    final pending = _pending[taskId];
    if (pending == null || pending.completer.isCompleted) return;

    if (status == 'progress') {
      final receivedBytes = _integer(update['receivedBytes']);
      final totalBytes = _integer(update['totalBytes']);
      pending.receivedBytes = receivedBytes ?? pending.receivedBytes;
      pending.expectedBytes = totalBytes ?? pending.expectedBytes;
      if (receivedBytes != null) {
        pending.onProgress?.call(receivedBytes, totalBytes);
      }
      return;
    }

    final statusCode = _integer(update['statusCode']);
    final receivedBytes = _integer(update['receivedBytes']);
    final expectedBytes = _integer(update['expectedBytes']);
    final contentType = update['contentType'] is String
        ? update['contentType'] as String
        : null;
    final errorDomain = update['errorDomain'] is String
        ? update['errorDomain'] as String
        : null;
    final errorCode = _integer(update['errorCode']);
    pending.receivedBytes = receivedBytes ?? pending.receivedBytes;
    pending.expectedBytes = expectedBytes ?? pending.expectedBytes;
    final rawMessage = update['message'];
    final message = rawMessage is String ? rawMessage : null;
    final result = switch (status) {
      'complete' => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.complete,
        statusCode: statusCode,
        receivedBytes: receivedBytes,
        expectedBytes: expectedBytes,
        contentType: contentType,
      ),
      'notFound' => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.notFound,
        statusCode: statusCode ?? 404,
        message: message,
        receivedBytes: receivedBytes,
        expectedBytes: expectedBytes,
        contentType: contentType,
      ),
      'canceled' => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.canceled,
        message: message,
        receivedBytes: receivedBytes,
        expectedBytes: expectedBytes,
        errorDomain: errorDomain,
        errorCode: errorCode,
      ),
      'failed' => BackgroundDownloadResult(
        status: BackgroundDownloadStatus.failed,
        statusCode: statusCode,
        message: message,
        isStorageFailure: update['isStorageFailure'] == true,
        receivedBytes: receivedBytes,
        expectedBytes: expectedBytes,
        contentType: contentType,
        errorDomain: errorDomain,
        errorCode: errorCode,
      ),
      _ => null,
    };
    if (result == null) return;
    AppLogger.log(
      'BackgroundFileDownload',
      'system task status=$status host=${pending.host} '
          'url=${pending.safeUrl} '
          'file=${pending.fileName} '
          'taskId=$taskId statusCode=${statusCode ?? "(null)"} '
          'bytes=${receivedBytes ?? pending.receivedBytes ?? "(unknown)"} '
          'expectedBytes=${expectedBytes ?? pending.expectedBytes ?? "(unknown)"} '
          'durationMs=${pending.stopwatch.elapsedMilliseconds}'
          '${contentType == null ? '' : ' contentType=$contentType'}'
          '${errorDomain == null ? '' : ' errorDomain=$errorDomain'}'
          '${errorCode == null ? '' : ' errorCode=$errorCode'}'
          '${message == null ? '' : ' message=${_safeDiagnosticText(message)}'}',
    );
    pending.completer.complete(result);
  }

  int? _integer(Object? value) => value is num ? value.toInt() : null;
}

String _safeDiagnosticText(String value) => value.replaceAll(
  RegExp(r'https?://[^\s"<>]+', caseSensitive: false),
  '<url>',
);

String _safeDownloadUrl(Uri uri) {
  final queryParameters = <String>[];
  uri.queryParametersAll.forEach((key, values) {
    final normalizedKey = key.toLowerCase().replaceAll(RegExp(r'[-_.]'), '');
    final isSensitive =
        normalizedKey.contains('token') ||
        normalizedKey.contains('signature') ||
        normalizedKey == 'sig' ||
        normalizedKey.contains('secret') ||
        normalizedKey.contains('password') ||
        normalizedKey.contains('passwd') ||
        normalizedKey.startsWith('auth') ||
        normalizedKey.contains('credential') ||
        normalizedKey.contains('apikey') ||
        normalizedKey.endsWith('key') ||
        normalizedKey == 'keypairid' ||
        normalizedKey.contains('policy') ||
        normalizedKey.contains('session');
    for (final value in values) {
      queryParameters.add(
        '${Uri.encodeQueryComponent(key)}='
        '${Uri.encodeQueryComponent(isSensitive ? 'REDACTED' : value)}',
      );
    }
  });
  return uri
      .replace(
        userInfo: '',
        query: uri.hasQuery ? queryParameters.join('&') : null,
      )
      .removeFragment()
      .toString();
}

class _MacOSPendingDownload {
  _MacOSPendingDownload({
    required this.completer,
    required this.onProgress,
    required this.host,
    required this.safeUrl,
    required this.fileName,
  }) : stopwatch = Stopwatch()..start();

  final Completer<BackgroundDownloadResult> completer;
  final BackgroundFileDownloadProgress? onProgress;
  final String host;
  final String safeUrl;
  final String fileName;
  final Stopwatch stopwatch;
  int? receivedBytes;
  int? expectedBytes;
  bool started = false;
  bool cancelRequested = false;
}
