import 'package:flutter/material.dart';

import 'custom_ai_settings_screen.dart';

/// 本地版模型设置入口，展示和导航随自定义 AI 模块维护。
class CustomAiSettingsTile extends StatelessWidget {
  const CustomAiSettingsTile({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.auto_awesome),
      title: const Text('AI 模型设置'),
      subtitle: const Text('使用自己的 API，无需登录或会员'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CustomAiSettingsScreen()),
      ),
    ),
  );
}
