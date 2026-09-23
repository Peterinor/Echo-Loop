import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../analytics/analytics_providers.dart';
import '../../../analytics/models/event_names.dart';
import '../../../providers/audio_library_provider.dart';
import '../../../providers/collection_provider.dart';
import '../../../services/app_logger.dart';
import '../data/community_collection_repository.dart';

part 'community_enrollment_provider.g.dart';

const _logTag = 'CommunityEnrollment';

/// enroll 的结果：本地合集 ID 和是否刚创建。
class CommunityEnrollResult {
  final String localCollectionId;
  final bool createdNew;

  const CommunityEnrollResult({
    required this.localCollectionId,
    required this.createdNew,
  });
}

/// 社区合集加入和移除的业务入口。
@Riverpod(keepAlive: true)
class CommunityEnrollment extends _$CommunityEnrollment {
  @override
  void build() {}

  /// 拉取 v2 元数据并加入本地合集。
  Future<CommunityEnrollResult> enroll(String remoteId) async {
    final repository = ref.read(communityCollectionRepositoryProvider);
    try {
      final localId = await repository.enroll(remoteId);
      await ref.read(audioLibraryProvider.notifier).loadLibrary();
      await ref.read(collectionListProvider.notifier).loadCollections();
      ref.read(analyticsServiceProvider).track(
        Events.communityCollectionEnroll,
        {EventParams.remoteId: remoteId},
      );
      return CommunityEnrollResult(
        localCollectionId: localId,
        createdNew: true,
      );
    } on CommunityCollectionAlreadyEnrolledError catch (error) {
      return CommunityEnrollResult(
        localCollectionId: error.localId,
        createdNew: false,
      );
    } catch (error, stackTrace) {
      AppLogger.log(_logTag, 'enroll failed: $error');
      AppLogger.log(_logTag, stackTrace.toString());
      rethrow;
    }
  }

  /// 移除社区合集及其本地媒体和学习记录。
  Future<void> remove(String localCollectionId) async {
    await ref
        .read(communityCollectionRepositoryProvider)
        .remove(localCollectionId);
    await ref.read(audioLibraryProvider.notifier).loadLibrary();
    await ref.read(collectionListProvider.notifier).loadCollections();
  }
}
