import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

/// 社区合集角标：贴在合集封面角上的文字小标签（"社区" / "已下架"）。
///
/// 设计目标：用最小占位直接传达语义，无需用户解读图标。
/// - 正常状态：金色圆角胶囊 + 白色"社区"文字
/// - 已下架状态：灰色圆角胶囊 + 白色"已下架"文字
///
/// 同时保留 Semantics + Tooltip 以兼容无障碍读屏。
class CommunityCornerBadge extends StatelessWidget {
  /// 是否处于已下架状态。
  final bool isDeprecated;

  const CommunityCornerBadge({super.key, this.isDeprecated = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final label = isDeprecated
        ? l10n.communityDeprecatedBadge
        : l10n.communityBadge;
    final bgColor = isDeprecated
        ? theme.colorScheme.outline
        : AppTheme.communityBadgeColor;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            // 不加描边：深色背景 + 白字本身已有强对比；白边在小尺寸上反而显朦胧
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.2,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
