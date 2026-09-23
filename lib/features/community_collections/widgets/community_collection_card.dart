import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/app_network_image_cache.dart';
import '../models/community_collection_models.dart';

/// Discover 页的合集卡片。
///
/// 点击卡片主体 [onOpenDetail] 进入详情页；右侧 trailing 按回调切换：
/// - 未加入：`+` 图标 → [onEnroll]
/// - 已加入：`去学习` 文字按钮 → [onGoLearn]
///
/// 数据源是 v2 的 [PublicCollectionSummary]，卡片只展示摘要信息。
class CommunityCollectionCard extends StatelessWidget {
  final PublicCollectionSummary item;

  /// 是否已加入（由父层根据 `collectionListProvider` 判断）
  final bool enrolled;

  /// 是否正在 enroll（按钮 disabled + spinner）
  final bool enrolling;

  final VoidCallback onOpenDetail;
  final VoidCallback onEnroll;
  final VoidCallback onGoLearn;

  const CommunityCollectionCard({
    super.key,
    required this.item,
    required this.enrolled,
    required this.enrolling,
    required this.onOpenDetail,
    required this.onEnroll,
    required this.onGoLearn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 主体：整块点击 = 打开详情
            Expanded(
              child: InkWell(
                onTap: onOpenDetail,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildCover(theme),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.audioCount(item.fileCount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (item.description case final description?
                                when description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 右侧：trailing 区全高可点击（enroll / goLearn / spinner）
            _buildTrailing(context, l10n, theme),
          ],
        ),
      ),
    );
  }

  /// 封面：有 URL 用 [CachedNetworkImage]（内存 + 磁盘双层缓存，冷启动也不重下）；
  /// 无 URL 或加载失败 → 渐变 + 首字母占位
  Widget _buildCover(ThemeData theme) {
    const size = 56.0;
    final coverUrl = item.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) {
      return _coverPlaceholder(theme, size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: coverUrl,
        cacheManager: AppNetworkImageCache.instance,
        width: size,
        height: size,
        // contain：完整展示图片，不裁剪；非方形图片两侧/上下留白
        fit: BoxFit.contain,
        // 加载中也用占位图，避免闪烁
        placeholder: (_, __) => _coverPlaceholder(theme, size),
        errorWidget: (_, __, ___) => _coverPlaceholder(theme, size),
      ),
    );
  }

  Widget _coverPlaceholder(ThemeData theme, double size) {
    final letter = item.name.isEmpty ? '?' : item.name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 右侧 trailing 区。三种态共用一个固定宽度的 InkWell 卡槽，
  /// 整个卡片高度都是点击区（与 collection_screen 里的 `...` 菜单同 pattern）。
  Widget _buildTrailing(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    const trailingWidth = 56.0;
    if (enrolling) {
      return const SizedBox(
        width: trailingWidth,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (enrolled) {
      return SizedBox(
        width: trailingWidth + 16, // "去学习" 文字宽度富余
        child: InkWell(
          onTap: onGoLearn,
          child: Center(
            child: Text(
              l10n.goLearn,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: trailingWidth,
      child: InkWell(
        onTap: onEnroll,
        child: Tooltip(
          message: l10n.addToMyCollections,
          child: Center(
            child: Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
