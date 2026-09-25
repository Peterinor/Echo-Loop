import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'custom_ai_client.dart';
import 'custom_ai_settings.dart';

/// 用户模型的唯一配置入口；密钥保持遮挡，不回显已保存值。
class CustomAiSettingsScreen extends ConsumerStatefulWidget {
  const CustomAiSettingsScreen({super.key});
  @override
  ConsumerState<CustomAiSettingsScreen> createState() =>
      _CustomAiSettingsScreenState();
}

class _CustomAiSettingsScreenState
    extends ConsumerState<CustomAiSettingsScreen> {
  final _url = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  final _cancel = CancelToken();
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    final settings = ref.read(customAiSettingsProvider);
    _url.text = settings.baseUrl;
    _model.text = settings.model;
  }

  @override
  void dispose() {
    _cancel.cancel('settings closed');
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    CustomAiClient? probe;
    try {
      final config = CustomAiSettings(
        baseUrl: _url.text.trim().replaceFirst(RegExp(r'/+$'), ''),
        model: _model.text.trim(),
      );
      config.completionUri;
      final key = _key.text.trim().isEmpty
          ? await ref
                    .read(customAiKeyStoreProvider)
                    .read(key: customAiKeyStorageKey) ??
                ''
          : normalizeApiKey(_key.text);
      if (key.isEmpty) throw const FormatException('请填写 API Key');
      if (test) {
        probe = CustomAiClient(config, readKey: () async => key);
        await probe.object('Return JSON: {"ok":true}', {
          'task': 'connection test',
        }, cancelToken: _cancel);
      } else {
        await ref
            .read(customAiSettingsProvider.notifier)
            .save(config, newKey: key);
        if (mounted) _key.clear();
      }
      if (mounted) setState(() => _message = test ? '连接成功' : '配置已保存');
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error) {
            CustomAiException(:final message) => message,
            FormatException(:final message) => message,
            _ => '操作失败，请检查配置或设备安全存储后重试',
          },
        );
      }
    } finally {
      probe?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await ref.read(customAiSettingsProvider.notifier).clear();
      if (!mounted) return;
      _url.clear();
      _model.clear();
      _key.clear();
      setState(() => _message = '配置和密钥已移除');
    } catch (_) {
      if (mounted) setState(() => _message = '移除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 模型设置')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('填写支持 OpenAI 兼容协议的云端模型。学习数据保存在本机；使用 AI 时，相关文本会发送到你配置的服务。'),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            hintText: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          ),
        ),
        TextField(
          controller: _model,
          enabled: !_busy,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '模型名称',
            hintText: 'qwen3-max',
          ),
        ),
        TextField(
          controller: _key,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API Key',
            helperText: '已保存时留空可保留原密钥；支持粘贴 Bearer 前缀',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存配置'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _save(test: true),
          child: const Text('测试连接（会调用模型）'),
        ),
        TextButton(
          onPressed: _busy ? null : _clear,
          child: const Text('移除配置和密钥'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(message),
          ),
      ],
    ),
  );
}
