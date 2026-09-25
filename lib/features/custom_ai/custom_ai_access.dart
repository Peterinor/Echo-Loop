import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'custom_ai_settings.dart';
import 'custom_ai_settings_screen.dart';

/// 自带 AI 的使用条件只由模型配置决定，不创建官方登录会话。
Future<bool> ensureCustomAiConfigured(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(customAiSettingsProvider).isConfigured) return true;
  final configure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('配置 AI 模型'),
      content: const Text('使用自己的 API 即可开启 AI 功能，无需登录或会员。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('去设置'),
        ),
      ],
    ),
  );
  if (context.mounted && configure == true) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CustomAiSettingsScreen()),
    );
  }
  return false;
}
