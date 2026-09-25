/// ChatApi 单例 provider。
library;

import '../../../config/app_capabilities.dart';
import '../../custom_ai/custom_ai_client.dart';
import '../../custom_ai/custom_chat_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/api_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../providers/package_info_provider.dart';
import '../chatbot_flags.dart';
import '../services/chat_api_client.dart';
import '../services/fake_chat_api_client.dart';

part 'chat_api_client_provider.g.dart';

/// ChatApi 单例（keepAlive）。
///
/// kChatbotUseFakeApi=true（仅 debug 联调用）时返回假实现；否则构造真实网络客户端。
@Riverpod(keepAlive: true)
ChatApi chatApiClient(Ref ref) {
  if (isLocalEdition) return CustomChatApi(ref.watch(customAiClientProvider));
  if (kChatbotUseFakeApi) return const FakeChatApiClient();
  final client = ChatApiClient(
    baseUrl: apiBaseUrl,
    appVersion: readAppVersion(ref),
    tokenCoordinator: ref.read(supabaseTokenCoordinatorProvider),
  );
  ref.onDispose(client.dispose);
  return client;
}
