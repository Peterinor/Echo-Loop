import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../onboarding_survey/providers/onboarding_survey_provider.dart';

/// 接受直接粘贴的 Authorization 值，存储时只保留密钥本体。
String normalizeApiKey(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
    .trim();

/// 不含密钥的模型配置，可进入普通设置备份。
class CustomAiSettings {
  const CustomAiSettings({this.baseUrl = '', this.model = ''});
  final String baseUrl;
  final String model;
  bool get isConfigured => baseUrl.isNotEmpty && model.isNotEmpty;

  /// 提示词版本、服务地址和模型共同隔离缓存，切换模型不复用旧结果。
  String get cacheNamespace =>
      'custom-v1:${sha256.convert(utf8.encode('$baseUrl|$model'))}';

  Uri get completionUri {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        model.trim().isEmpty) {
      throw const FormatException('请填写有效的 HTTPS API 地址和模型名称');
    }
    return uri.replace(
      path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
    );
  }
}

final customAiKeyStoreProvider = Provider(
  (ref) => const FlutterSecureStorage(),
);
const customAiKeyStorageKey = 'custom_ai_api_key';
final customAiSettingsProvider =
    NotifierProvider<CustomAiSettingsController, CustomAiSettings>(
      CustomAiSettingsController.new,
    );

/// 密钥只写安全存储；设置变化使依赖的客户端销毁并取消旧请求。
class CustomAiSettingsController extends Notifier<CustomAiSettings> {
  @override
  CustomAiSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return CustomAiSettings(
      baseUrl: prefs.getString('custom_ai_base_url') ?? '',
      model: prefs.getString('custom_ai_model') ?? '',
    );
  }

  Future<void> save(CustomAiSettings settings, {String? newKey}) async {
    settings.completionUri;
    final store = ref.read(customAiKeyStoreProvider);
    final key = newKey == null
        ? await store.read(key: customAiKeyStorageKey)
        : normalizeApiKey(newKey);
    if (key == null || key.isEmpty) throw const FormatException('请填写 API Key');
    await store.write(key: customAiKeyStorageKey, value: key);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('custom_ai_base_url', settings.baseUrl);
    await prefs.setString('custom_ai_model', settings.model);
    state = settings;
  }

  Future<void> clear() async {
    await ref.read(customAiKeyStoreProvider).delete(key: customAiKeyStorageKey);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove('custom_ai_base_url');
    await prefs.remove('custom_ai_model');
    state = const CustomAiSettings();
  }
}
