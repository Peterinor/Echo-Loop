import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../models/audio_item.dart';
import '../../providers/audio_library_provider.dart';
import '../../providers/collection_provider.dart';
import '../../services/app_logger.dart';
import '../../utils/audio_duration.dart';
import 'audio_import_cancel.dart';

/// 已在应用沙盒内的音频注册服务。
///
/// 本地导入和链接下载只负责把音频文件放入沙盒；创建 [AudioItem]、写入音频库、
/// 关联合集和重复处理统一从这里进入，避免不同来源绕过数据库入库流程。
class AudioRegistrationService {
  AudioRegistrationService({
    Uuid? uuid,
    Future<int> Function(String relativePath)? readDurationSeconds,
  }) : _uuid = uuid ?? const Uuid(),
       _readDurationSeconds = readDurationSeconds ?? getAudioDurationSeconds;

  final Uuid _uuid;
  final Future<int> Function(String relativePath) _readDurationSeconds;

  Future<AudioRegistrationResult> registerSandboxedAudio({
    required SandboxedAudioRegistrationInput input,
    required AudioLibrary audioLibrary,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
    CancelToken? cancelToken,
  }) async {
    final traceId = cancelToken?.hashCode.toRadixString(16) ?? 'none';
    AppLogger.log('AudioImportRegister', 'begin trace=$traceId');
    cancelToken?.throwIfCanceled();
    final originalSha = input.originalAudioSha256;
    if (originalSha != null) {
      final existingResult = await registerExistingAudioByOriginalSha256(
        originalAudioSha256: originalSha,
        attemptedName: input.name,
        audioLibraryState: audioLibraryState,
        collectionList: collectionList,
        collectionState: collectionState,
        collectionId: collectionId,
      );
      if (existingResult != null) {
        AppLogger.log(
          'AudioImportRegister',
          'duplicate trace=$traceId kind=sha',
        );
        return existingResult;
      }
    } else {
      // 无原始内容指纹（老数据/社区音频）退回按名去重。
      final existingResult = await registerExistingAudioByName(
        name: input.name,
        audioLibraryState: audioLibraryState,
        collectionList: collectionList,
        collectionState: collectionState,
        collectionId: collectionId,
      );
      if (existingResult != null) {
        AppLogger.log(
          'AudioImportRegister',
          'duplicate trace=$traceId kind=name',
        );
        return existingResult;
      }
    }

    cancelToken?.throwIfCanceled();
    AppLogger.log('AudioImportRegister', 'duration_begin trace=$traceId');
    final duration = await _readDurationSeconds(input.relativePath);
    AppLogger.log('AudioImportRegister', 'duration_complete trace=$traceId');
    cancelToken?.throwIfCanceled();
    final audioItem = AudioItem(
      id: _uuid.v4(),
      name: input.name,
      audioPath: input.relativePath,
      addedDate: DateTime.now(),
      totalDuration: duration,
      audioSha256: input.audioSha256,
      originalAudioSha256: input.originalAudioSha256,
      importSourceType: input.importSourceType,
      importSourceUrl: input.importSourceUrl,
    );

    // 入库提交开始后让事务完成；取消方会保留已提交条目，避免文件与数据库失配。
    AppLogger.log(
      'AudioImportRegister',
      'database_commit_begin trace=$traceId',
    );
    await audioLibrary.addAudioItem(audioItem);
    AppLogger.log(
      'AudioImportRegister',
      'database_commit_complete trace=$traceId',
    );
    if (collectionId != null) {
      await collectionList?.addAudioToCollection(collectionId, audioItem.id);
    }
    AppLogger.log('AudioImportRegister', 'complete trace=$traceId');
    return AudioRegistrationAdded(audioItem);
  }

  /// 如果库中已有同名音频，按统一规则处理重复或合集关联。
  ///
  /// 返回 `null` 表示没有同名音频，调用方可以继续复制或下载新文件。
  Future<AudioRegistrationResult?> registerExistingAudioByName({
    required String name,
    required AudioLibraryState audioLibraryState,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
  }) async {
    final existingItem = _findExistingByName(
      audioLibraryState.audioItems,
      name,
    );
    if (existingItem == null) return null;

    if (collectionId == null) {
      return AudioRegistrationDuplicate(existingName: existingItem.name);
    }

    final audioIds = collectionState?.getAudioIds(collectionId) ?? const [];
    if (audioIds.contains(existingItem.id)) {
      return AudioRegistrationDuplicate(existingName: existingItem.name);
    }

    await collectionList?.addAudioToCollection(collectionId, existingItem.id);
    return AudioRegistrationAdded(existingItem);
  }

  /// 如果库中已有相同原始内容指纹的音频，按"按内容全局去重"规则处理。
  ///
  /// 用 [AudioItem.originalAudioSha256]（转码前原始指纹）比对，而非 `audioSha256`：
  /// 后者在 AI 转录后会被改写为转码后指纹，导致"导入→转录→再导入同一文件"无法识别
  /// 重复；前者始终是原始内容指纹、跨转码稳定。
  ///
  /// 去重语义：库中**永不**存在两个同内容条目；同一条目可被多个合集引用。返回
  /// `null` 表示库中没有同内容音频，调用方可以继续创建新条目。规则：
  /// - 无合集上下文（collectionId 为空）：已存在同内容即视为重复，返回
  ///   [AudioRegistrationDuplicate]，不新建。
  /// - 已在目标合集：视为重复，返回 [AudioRegistrationDuplicate]。
  /// - 不在目标合集：把已有条目关联到该合集，返回 [AudioRegistrationAdded]，不新建。
  Future<AudioRegistrationResult?> registerExistingAudioByOriginalSha256({
    required String originalAudioSha256,
    required AudioLibraryState audioLibraryState,
    String? attemptedName,
    CollectionList? collectionList,
    CollectionState? collectionState,
    String? collectionId,
  }) async {
    final existingItem = _findExistingByOriginalSha256(
      audioLibraryState.audioItems,
      originalAudioSha256,
    );
    if (existingItem == null) return null;
    if (collectionId == null) {
      return AudioRegistrationDuplicate(
        existingName: existingItem.name,
        attemptedName: attemptedName,
      );
    }

    final audioIds = collectionState?.getAudioIds(collectionId) ?? const [];
    if (audioIds.contains(existingItem.id)) {
      return AudioRegistrationDuplicate(
        existingName: existingItem.name,
        attemptedName: attemptedName,
      );
    }

    await collectionList?.addAudioToCollection(collectionId, existingItem.id);
    return AudioRegistrationAdded(existingItem);
  }

  AudioItem? _findExistingByName(List<AudioItem> items, String name) {
    for (final item in items) {
      if (item.name == name) return item;
    }
    return null;
  }

  AudioItem? _findExistingByOriginalSha256(
    List<AudioItem> items,
    String originalAudioSha256,
  ) {
    for (final item in items) {
      if (item.originalAudioSha256 == originalAudioSha256) return item;
    }
    return null;
  }
}

class SandboxedAudioRegistrationInput {
  const SandboxedAudioRegistrationInput({
    required this.name,
    required this.relativePath,
    required this.importSourceType,
    this.audioSha256,
    this.importSourceUrl,
    this.originalAudioSha256,
  });

  final String name;
  final String relativePath;
  final AudioImportSourceType importSourceType;
  final String? audioSha256;
  final String? importSourceUrl;
  final String? originalAudioSha256;
}

sealed class AudioRegistrationResult {
  const AudioRegistrationResult();
}

class AudioRegistrationAdded extends AudioRegistrationResult {
  const AudioRegistrationAdded(this.item);

  final AudioItem item;
}

class AudioRegistrationDuplicate extends AudioRegistrationResult {
  const AudioRegistrationDuplicate({
    required this.existingName,
    String? attemptedName,
  }) : attemptedName = attemptedName ?? existingName;

  /// 库中已存在的同内容（或同名）条目名称。
  final String existingName;

  /// 本次尝试导入的名称（可能与 [existingName] 不同，如内容相同但文件名不同）。
  final String attemptedName;

  /// 兼容旧用法：默认取已存在条目名称。
  String get name => existingName;
}
