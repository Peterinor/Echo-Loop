import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/audio_library_provider.dart';
import '../../../providers/collection_provider.dart';
import '../download/community_download_notifier.dart';
import 'community_sync_service.dart';

/// 触发社区合集唯一同步入口，并刷新本地派生状态。
Future<CommunitySyncOutcome> triggerCommunitySync(
  WidgetRef ref, {
  bool force = false,
}) async {
  final outcome = await ref
      .read(communitySyncServiceProvider)
      .syncAll(force: force);
  if (outcome is CommunitySyncCompleted) {
    await ref.read(audioLibraryProvider.notifier).loadLibrary();
    await ref.read(collectionListProvider.notifier).loadCollections();

    final removed = outcome.filesRemoved + outcome.filesMarkedUnavailable;
    if (removed > 0) {
      final context = communityDownloadScaffoldMessengerKey.currentContext;
      final messenger = communityDownloadScaffoldMessengerKey.currentState;
      // 全局 ScaffoldMessenger 在 App 生命周期内与 MaterialApp 同寿命；同步
      // 完成后重新读取当前 locale，避免在 service 层缓存文案。
      // ignore: use_build_context_synchronously
      final l10n = context == null ? null : AppLocalizations.of(context);
      if (messenger != null && l10n != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.communityFilesRemoved(removed))),
        );
      }
    }
  }
  return outcome;
}
