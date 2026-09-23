import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/sign_in_required_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/audio_item.dart';
import '../../../providers/audio_library_provider.dart';
import '../../../providers/collection_provider.dart';
import '../../../router/app_router.dart';
import '../../../widgets/audio_list_view.dart';
import '../models/community_collection_models.dart';
import '../models/community_collection_paging.dart';
import '../providers/community_collection_detail_provider.dart';
import '../providers/community_enrollment_provider.dart';
import '../providers/discover_community_collections_provider.dart';

/// 社区合集详情页；文件预览和加入均使用 v2 数据。
class CommunityCollectionDetailScreen extends ConsumerStatefulWidget {
  final String remoteId;

  const CommunityCollectionDetailScreen({super.key, required this.remoteId});

  @override
  ConsumerState<CommunityCollectionDetailScreen> createState() =>
      _CommunityCollectionDetailScreenState();
}

class _CommunityCollectionDetailScreenState
    extends ConsumerState<CommunityCollectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final summary = ref
        .watch(discoverCommunityCollectionsProvider)
        .whenOrNull(
          data: (page) => page.items
              .where((item) => item.id == widget.remoteId)
              .firstOrNull,
        );
    final collectionState = ref.watch(collectionListProvider);
    final localId = _localId(collectionState);

    // 已加入合集时，列表真相在本地数据库；不要为了渲染本地列表再等待远端
    // catalog 请求，避免重新进入详情页被网络加载阻塞。
    if (localId != null && summary != null) {
      return Scaffold(
        appBar: AppBar(title: Text(summary.name)),
        body: _Content(
          summary: summary,
          remotePage: null,
          fileCount: collectionState.getAudioCount(localId),
          localId: localId,
          onLoadMore: () {},
          onEnroll: () => _enroll(context, ref),
          onPreviewFileTap: (_) => _showEnrollDialog(context, ref),
          onLearn: () {
            context.go(AppRoutes.collectionDetail(localId));
          },
        ),
      );
    }

    final files = ref.watch(communityCollectionFilesProvider(widget.remoteId));
    return Scaffold(
      appBar: AppBar(title: Text(summary?.name ?? '')),
      body: files.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (page) => _Content(
          summary: summary,
          remotePage: page,
          fileCount: summary?.fileCount ?? page.items.length,
          localId: localId,
          onLoadMore: () => unawaited(
            ref
                .read(
                  communityCollectionFilesProvider(widget.remoteId).notifier,
                )
                .loadMore(),
          ),
          onEnroll: () => _enroll(context, ref),
          onPreviewFileTap: (_) => _showEnrollDialog(context, ref),
          onLearn: () {
            if (localId != null) {
              context.go(AppRoutes.collectionDetail(localId));
            }
          },
        ),
      ),
    );
  }

  String? _localId(CollectionState state) {
    for (final collection in state.collections) {
      if (collection.isCommunity && collection.remoteId == widget.remoteId) {
        return collection.id;
      }
    }
    return null;
  }

  /// 未加入合集时，点击预览素材先提示用户添加合集。
  Future<void> _showEnrollDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final shouldEnroll = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.enrollNeededTitle),
        content: Text(l10n.enrollNeededMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.addToMyCollections),
          ),
        ],
      ),
    );
    if (shouldEnroll == true && context.mounted) {
      await _enroll(context, ref);
    }
  }

  Future<void> _enroll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final allowed = await ensureSignedInForAction(
      context: context,
      ref: ref,
      title: l10n.communityCollectionSignInRequiredTitle,
      message: l10n.communityCollectionSignInRequiredMessage,
    );
    if (!allowed || !context.mounted) return;
    try {
      await ref
          .read(communityEnrollmentProvider.notifier)
          .enroll(widget.remoteId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.enrollSucceeded)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.enrollFailed)));
      }
    }
  }
}

class _Content extends StatelessWidget {
  final PublicCollectionSummary? summary;
  final CommunityCollectionPagedState<CommunityCollectionFile>? remotePage;
  final int fileCount;
  final String? localId;
  final VoidCallback onLoadMore;
  final VoidCallback onEnroll;
  final ValueChanged<CommunityCollectionFile> onPreviewFileTap;
  final VoidCallback onLearn;

  const _Content({
    required this.summary,
    required this.remotePage,
    required this.fileCount,
    required this.localId,
    required this.onLoadMore,
    required this.onEnroll,
    required this.onPreviewFileTap,
    required this.onLearn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final collection = summary;
    if (collection == null) {
      return Center(child: Text(l10n.communityCollectionDeprecated));
    }
    final description = collection.description;
    final audioList = switch (localId) {
      final String id => _LocalAudioList(localId: id),
      _ => _PreviewList(
        files: remotePage?.items ?? const [],
        hasMore: remotePage?.hasMore ?? false,
        isLoadingMore: remotePage?.isLoadingMore ?? false,
        loadMoreError: remotePage?.loadMoreError,
        onLoadMore: onLoadMore,
        onTap: onPreviewFileTap,
      ),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null && description.isNotEmpty)
                Text(description),
              const SizedBox(height: 6),
              Text(
                l10n.audioCount(fileCount),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (localId == null) const _PreviewListHeader(),
        Expanded(child: audioList),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: localId == null ? onEnroll : onLearn,
                child: Text(
                  localId == null ? l10n.addToMyCollections : l10n.goLearn,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalAudioList extends ConsumerWidget {
  final String localId;

  const _LocalAudioList({required this.localId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(collectionListProvider);
    final items = collection
        .getAudioIds(localId)
        .map((id) => ref.read(audioLibraryProvider.notifier).getItemById(id))
        .whereType<AudioItem>()
        .toList(growable: false);
    return AudioListView(items: items, collectionId: localId);
  }
}

class _PreviewList extends StatelessWidget {
  final List<CommunityCollectionFile> files;
  final bool hasMore;
  final bool isLoadingMore;
  final Object? loadMoreError;
  final VoidCallback onLoadMore;
  final ValueChanged<CommunityCollectionFile> onTap;

  const _PreviewList({
    required this.files,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && !hasMore) return const Center(child: Text('暂无文件'));
    final footerCount = isLoadingMore || loadMoreError != null ? 1 : 0;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification &&
            notification.metrics.extentAfter < 200) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        itemCount: files.length + footerCount,
        separatorBuilder: (_, index) {
          if (index >= files.length - 1) return const SizedBox.shrink();
          return const Divider(height: 1);
        },
        itemBuilder: (context, index) {
          if (index >= files.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            return Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: Text(AppLocalizations.of(context)!.retry),
              ),
            );
          }
          final file = files[index];
          final durationSec = file.durationSec;
          return ListTile(
            leading: Icon(
              file.mediaType == CommunityMediaType.video
                  ? Icons.videocam_outlined
                  : Icons.graphic_eq,
            ),
            title: Text(
              file.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            trailing: durationSec == null || durationSec <= 0
                ? null
                : Text(
                    _formatPreviewDuration(durationSec),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
            onTap: () => onTap(file),
          );
        },
      ),
    );
  }
}

/// 未加入态预览列表的列标题，与旧版合集详情页保持一致。
class _PreviewListHeader extends StatelessWidget {
  const _PreviewListHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
      child: Row(
        children: [
          Expanded(child: Text(l10n.audioListColumnName, style: style)),
          Text(l10n.audioListColumnDuration, style: style),
        ],
      ),
    );
  }
}

String _formatPreviewDuration(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}min';
  }
  if (minutes == 0) return '${seconds}s';
  return seconds == 0
      ? '${minutes}min'
      : '$minutes:${seconds.toString().padLeft(2, '0')}';
}
