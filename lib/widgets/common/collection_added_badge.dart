import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 合集已添加状态角标；语义标签由包裹它的状态区域提供。
class CollectionAddedBadge extends StatelessWidget {
  final String label;

  const CollectionAddedBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.successColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
