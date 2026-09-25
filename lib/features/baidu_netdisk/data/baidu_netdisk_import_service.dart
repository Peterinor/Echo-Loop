/// 百度网盘音频导入服务。
library;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import '../../../models/audio_item.dart';
import '../../../providers/audio_library_provider.dart';
import '../../../providers/collection_provider.dart';
import '../../../services/app_logger.dart';
import '../../../utils/app_data_dir.dart';
import '../../../utils/transcript_picker.dart';
import '../../audio_import/audio_import_cancel.dart';
import '../../audio_import/audio_finalization_service.dart';
import '../../audio_import/audio_import_models.dart';
import '../../audio_import/audio_registration_service.dart';
import '../../audio_import/subtitle_pairing.dart';
import '../models/cloud_drive_models.dart';
import 'baidu_credential_repository.dart';
import 'baidu_netdisk_api.dart';

/// 百度网盘导入进度回调。
typedef BaiduNetdiskImportProgressCallback =
    void Function(CloudDriveEntry entry, int receivedBytes, int? totalBytes);

/// 百度网盘批量导入中单条音频的最终结果回调。
typedef BaiduNetdiskImportItemResultCallback =
    void Function(CloudDriveImportItemResult result);

/// 百度网盘导入后给音频挂载字幕的回调。
typedef BaiduNetdiskSubtitleImporter =
    Future<void> Function(
      AudioItem item, {
      required String text,
      required String ext,
    });

/// 百度网盘音频导入服务抽象。
abstract interface class BaiduNetdiskImportService {
  /// 导入单个百度网盘音频文件。
  Future<AudioItem> importAudio({
    required CloudDriveEntry entry,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
  });

  /// 批量导入百度网盘音频文件。
  Future<CloudDriveImportOutcome> importAudios({
    required List<CloudDriveEntry> entries,
    List<CloudDriveEntry> subtitleEntries = const <CloudDriveEntry>[],
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
    BaiduNetdiskImportItemResultCallback? onItemResult,
  });
}

/// 默认百度网盘导入服务。
class DefaultBaiduNetdiskImportService implements BaiduNetdiskImportService {
  /// 构造默认实现。
  DefaultBaiduNetdiskImportService({
    required BaiduCredentialRepository credentialRepository,
    required BaiduNetdiskApi api,
    Future<Directory> Function()? resolveDataDir,
    AudioFinalizationService? finalizationService,
    AudioRegistrationService? registrationService,
    BaiduNetdiskSubtitleImporter? subtitleImporter,
  }) : _credentialRepository = credentialRepository,
       _api = api,
       _resolveDataDir = resolveDataDir ?? getAppDataDirectory,
       _finalizationService = finalizationService ?? AudioFinalizationService(),
       _registrationService = registrationService ?? AudioRegistrationService(),
       _subtitleImporter = subtitleImporter;

  final BaiduCredentialRepository _credentialRepository;
  final BaiduNetdiskApi _api;
  final Future<Directory> Function() _resolveDataDir;
  final AudioFinalizationService _finalizationService;
  final AudioRegistrationService _registrationService;
  final BaiduNetdiskSubtitleImporter? _subtitleImporter;

  @override
  Future<AudioItem> importAudio({
    required CloudDriveEntry entry,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
    BaiduNetdiskImportItemResultCallback? onItemResult,
  }) async {
    if (entry.isDirectory) {
      throw AudioImportException(
        AudioImportFailureCode.unsupportedFormat,
        'Cannot import a directory: ${entry.name}',
      );
    }
    if (!isImportablePrimaryMediaExtension(entry.extension)) {
      throw AudioImportException(
        AudioImportFailureCode.unsupportedFormat,
        'Unsupported media format: .${entry.extension}',
      );
    }

    final accessToken = await _credentialRepository.getValidAccessToken();
    if (accessToken == null) {
      throw const BaiduReauthorizationRequiredException();
    }

    final dataDir = await _resolveDataDir();
    final tempRelativePath = await _downloadToTemp(
      accessToken: accessToken,
      entry: entry,
      dataDir: dataDir,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    final targetSubdir = isVideoImportExtension(entry.extension)
        ? 'videos'
        : p.join('audios', 'imported');
    FinalizedAudio? finalizedAudio;
    try {
      finalizedAudio = await _finalizationService.finalize(
        dataDir: dataDir,
        tempRelativePath: tempRelativePath,
        targetSubdir: targetSubdir,
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCanceled();

      final result = await _registrationService.registerSandboxedAudio(
        input: SandboxedAudioRegistrationInput(
          name: _displayNameForEntry(entry),
          relativePath: finalizedAudio.relativePath,
          importSourceType: AudioImportSourceType.cloudDrive,
          importSourceUrl: _sourceUrlForEntry(entry),
          audioSha256: finalizedAudio.sha256,
          originalAudioSha256: finalizedAudio.originalSha256,
        ),
        audioLibrary: audioLibrary,
        audioLibraryState: audioLibraryState,
        collectionList: collectionList,
        collectionState: collectionState,
        collectionId: collectionId,
        cancelToken: cancelToken,
      );

      switch (result) {
        case AudioRegistrationAdded(:final item):
          return item;
        case AudioRegistrationDuplicate(:final name):
          throw AudioImportException(
            AudioImportFailureCode.duplicate,
            'Audio already exists: $name',
          );
      }
    } catch (error) {
      final savedAudio = finalizedAudio;
      if (savedAudio != null && savedAudio.created) {
        await _deleteIfExists(
          File(p.join(dataDir.path, savedAudio.relativePath)),
        );
      }
      if (error is DioException && CancelToken.isCancel(error)) {
        throw const AudioImportException(
          AudioImportFailureCode.canceled,
          'Audio import canceled',
        );
      }
      rethrow;
    }
  }

  @override
  Future<CloudDriveImportOutcome> importAudios({
    required List<CloudDriveEntry> entries,
    List<CloudDriveEntry> subtitleEntries = const <CloudDriveEntry>[],
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
    BaiduNetdiskImportProgressCallback? onProgress,
    BaiduNetdiskImportItemResultCallback? onItemResult,
  }) async {
    final added = <CloudDriveEntry>[];
    final addedItems = <AudioItem>[];
    final duplicateDetails = <AudioImportDuplicate>[];
    final duplicateEntries = <CloudDriveEntry>[];
    final failures = <CloudDriveImportFailure>[];
    var currentLibraryState = audioLibraryState;
    var wasCanceled = false;
    final subtitleByAudio = _matchSubtitleEntries(entries, subtitleEntries);

    for (final entry in entries) {
      try {
        var item = await importAudio(
          entry: entry,
          audioLibrary: audioLibrary,
          audioLibraryState: currentLibraryState,
          collectionList: collectionList,
          collectionState: collectionState,
          collectionId: collectionId,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        final subtitle = subtitleByAudio[entry.fsId];
        if (subtitle != null) {
          final attached = await _attachSubtitleIfPossible(
            item: item,
            subtitleEntry: subtitle,
            cancelToken: cancelToken,
          );
          if (attached) {
            item = item.copyWith(transcriptSource: TranscriptSource.local);
          }
        }
        added.add(entry);
        addedItems.add(item);
        onItemResult?.call(
          CloudDriveImportItemResult.added(entry: entry, item: item),
        );
        currentLibraryState = currentLibraryState.copyWith(
          audioItems: [...currentLibraryState.audioItems, item],
        );
      } on AudioImportException catch (error) {
        if (error.code == AudioImportFailureCode.canceled) {
          wasCanceled = true;
          break;
        }
        if (error.code == AudioImportFailureCode.duplicate) {
          final existingName = _existingNameFromDuplicateMessage(error.message);
          duplicateEntries.add(entry);
          duplicateDetails.add((
            attempted: _displayNameForEntry(entry),
            existing: existingName,
          ));
          onItemResult?.call(
            CloudDriveImportItemResult.duplicate(
              entry: entry,
              existingName: existingName,
            ),
          );
          continue;
        }
        final failure = CloudDriveImportFailure(
          entry: entry,
          message: error.message,
          errorKind: error.code.name,
        );
        failures.add(failure);
        onItemResult?.call(
          CloudDriveImportItemResult.failed(entry: entry, failure: failure),
        );
      } on BaiduNetdiskFileException catch (error) {
        if (error.kind == BaiduNetdiskFileErrorKind.canceled) {
          wasCanceled = true;
          break;
        }
        final failure = CloudDriveImportFailure(
          entry: entry,
          message: error.message,
          errorKind: error.kind.name,
        );
        failures.add(failure);
        onItemResult?.call(
          CloudDriveImportItemResult.failed(entry: entry, failure: failure),
        );
      } on BaiduReauthorizationRequiredException {
        rethrow;
      } on Object catch (error, stackTrace) {
        if (error is DioException && CancelToken.isCancel(error)) {
          wasCanceled = true;
          break;
        }
        AppLogger.log(
          'BaiduNetdiskImport',
          'import "${entry.name}" failed unexpectedly: $error\n$stackTrace',
        );
        final failure = CloudDriveImportFailure(
          entry: entry,
          message: _messageForUnexpectedError(error),
          errorKind: 'unknown',
        );
        failures.add(failure);
        onItemResult?.call(
          CloudDriveImportItemResult.failed(entry: entry, failure: failure),
        );
      }
    }

    return CloudDriveImportOutcome(
      added: added,
      addedItems: addedItems,
      duplicateDetails: duplicateDetails,
      duplicateEntries: duplicateEntries,
      failures: failures,
      wasCanceled: wasCanceled,
    );
  }

  Map<int, CloudDriveEntry> _matchSubtitleEntries(
    List<CloudDriveEntry> audioEntries,
    List<CloudDriveEntry> subtitleEntries,
  ) {
    if (audioEntries.isEmpty || subtitleEntries.isEmpty) {
      return const <int, CloudDriveEntry>{};
    }
    final entriesByName = <String, CloudDriveEntry>{
      for (final entry in [...audioEntries, ...subtitleEntries])
        entry.name: entry,
    };
    final pairing = matchSubtitlesForAudios(entriesByName.keys);
    final result = <int, CloudDriveEntry>{};
    for (final audio in audioEntries) {
      final subtitleName = pairing[audio.name];
      final subtitle = subtitleName == null
          ? null
          : entriesByName[subtitleName];
      if (subtitle != null) result[audio.fsId] = subtitle;
    }
    return result;
  }

  Future<bool> _attachSubtitleIfPossible({
    required AudioItem item,
    required CloudDriveEntry subtitleEntry,
    required CancelToken? cancelToken,
  }) async {
    final importer = _subtitleImporter;
    if (importer == null || item.hasTranscript) return false;
    try {
      final text = await _downloadSubtitleText(
        entry: subtitleEntry,
        cancelToken: cancelToken,
      );
      await importer(item, text: text, ext: subtitleEntry.extension);
      AppLogger.log(
        'BaiduNetdiskImport',
        'attached subtitle "${subtitleEntry.name}" to "${item.name}"',
      );
      return true;
    } on BaiduNetdiskFileException catch (error) {
      if (error.kind == BaiduNetdiskFileErrorKind.canceled) rethrow;
      AppLogger.log(
        'BaiduNetdiskImport',
        'attach subtitle "${subtitleEntry.name}" to "${item.name}" failed: $error',
      );
    } on AudioImportException catch (error) {
      if (error.code == AudioImportFailureCode.canceled) rethrow;
      AppLogger.log(
        'BaiduNetdiskImport',
        'attach subtitle "${subtitleEntry.name}" to "${item.name}" failed: $error',
      );
    } catch (error) {
      AppLogger.log(
        'BaiduNetdiskImport',
        'attach subtitle "${subtitleEntry.name}" to "${item.name}" failed: $error',
      );
    }
    return false;
  }

  Future<String> _downloadSubtitleText({
    required CloudDriveEntry entry,
    required CancelToken? cancelToken,
  }) async {
    final accessToken = await _credentialRepository.getValidAccessToken();
    if (accessToken == null) {
      throw const BaiduReauthorizationRequiredException();
    }

    final dataDir = await _resolveDataDir();
    final tempRelativePath = await _downloadToTemp(
      accessToken: accessToken,
      entry: entry,
      dataDir: dataDir,
      cancelToken: cancelToken,
      onProgress: null,
    );
    final tempFile = File(p.join(dataDir.path, tempRelativePath));
    try {
      final decoded = await decodeTranscriptBytes(await tempFile.readAsBytes());
      return decoded.text;
    } finally {
      await _deleteIfExists(tempFile);
    }
  }

  Future<String> _downloadToTemp({
    required String accessToken,
    required CloudDriveEntry entry,
    required Directory dataDir,
    required CancelToken? cancelToken,
    required BaiduNetdiskImportProgressCallback? onProgress,
  }) async {
    final tmpDir = Directory(p.join(dataDir.path, 'tmp', 'baidu_netdisk'));
    await tmpDir.create(recursive: true);
    final tempFile = File(
      p.join(tmpDir.path, '${entry.fsId}.${entry.extension}'),
    );
    try {
      await _downloadWithFreshLink(
        accessToken: accessToken,
        entry: entry,
        savePath: tempFile.path,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      return p.join('tmp', 'baidu_netdisk', p.basename(tempFile.path));
    } on Object {
      await _deleteIfExists(tempFile);
      rethrow;
    }
  }

  Future<void> _downloadWithFreshLink({
    required String accessToken,
    required CloudDriveEntry entry,
    required String savePath,
    required CancelToken? cancelToken,
    required BaiduNetdiskImportProgressCallback? onProgress,
  }) async {
    final link = await _api.fetchDownloadLink(
      accessToken: accessToken,
      fsId: entry.fsId,
    );
    try {
      await _api.downloadToFile(
        accessToken: accessToken,
        dlink: link.dlink,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (received, total) =>
            onProgress?.call(entry, received, total),
      );
    } on BaiduNetdiskFileException catch (error) {
      if (!_shouldRefreshDlink(error)) rethrow;
      AppLogger.log(
        'BaiduNetdiskImport',
        'download "${entry.name}" failed with ${error.kind.name}; refreshing dlink once',
      );
      final refreshed = await _api.fetchDownloadLink(
        accessToken: accessToken,
        fsId: entry.fsId,
      );
      await _api.downloadToFile(
        accessToken: accessToken,
        dlink: refreshed.dlink,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (received, total) =>
            onProgress?.call(entry, received, total),
      );
    }
  }

  bool _shouldRefreshDlink(BaiduNetdiskFileException error) {
    return switch (error.kind) {
      BaiduNetdiskFileErrorKind.unauthorized ||
      BaiduNetdiskFileErrorKind.notFound ||
      BaiduNetdiskFileErrorKind.network => true,
      BaiduNetdiskFileErrorKind.badRequest ||
      BaiduNetdiskFileErrorKind.rateLimited ||
      BaiduNetdiskFileErrorKind.canceled ||
      BaiduNetdiskFileErrorKind.unknown => false,
    };
  }

  String _displayNameForEntry(CloudDriveEntry entry) {
    final name = p.basenameWithoutExtension(entry.name).trim();
    return name.isEmpty ? entry.name : name;
  }

  String _existingNameFromDuplicateMessage(String message) {
    const prefix = 'Audio already exists: ';
    if (!message.startsWith(prefix)) return message;
    return message.substring(prefix.length);
  }

  String _sourceUrlForEntry(CloudDriveEntry entry) {
    return 'baidunetdisk://fs/${entry.fsId}?path=${Uri.encodeComponent(entry.path)}';
  }

  String _messageForUnexpectedError(Object error) {
    final message = error.toString().trim();
    return message.isEmpty ? 'Baidu Netdisk import failed.' : message;
  }

  Future<void> _deleteIfExists(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }
}
