/// 订阅可用性查询：当前平台是否启用订阅。
///
/// UI 层所有「要不要展示订阅入口 / 能不能进 Paywall」的判断统一 watch 本
/// provider，不直接读 config——集中一个入口，测试可 override 模拟各平台。
///
/// 真相源是 channel-aware 的 [subscriptionAvailableFor]：先由 `platform +
/// DISTRIBUTION_CHANNEL` 决定 [clientPaymentChannel]（见 `client_distribution.dart`），
/// 再看该渠道对应实现是否配置就绪（原生 RC key / Paddle 后端 API）。
library;

import '../../../config/app_capabilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/client_distribution.dart';
import '../../../config/paddle_config.dart';
import '../../../config/revenuecat_config.dart';
import '../../remote_config/remote_config.dart';
import '../../remote_config/remote_config_providers.dart';

part 'subscription_availability.g.dart';

/// 当前平台是否支持订阅（订阅 UI 展示总闸）。
@riverpod
bool subscriptionAvailability(Ref ref) =>
    !isLocalEdition &&
    subscriptionAvailableFor(
      channel: clientPaymentChannel,
      // 本地 StoreKit 测试模式仅对 Apple 渠道生效（与 purchaseServiceTypeFor 一致），
      // 避免 Android 下 USE_LOCAL_STOREKIT=true 但无 Google key 时门控误判可用、
      // 购买却落回 Stub。
      nativeStoreConfigured:
          isRevenueCatConfigured ||
          (useLocalStoreKit &&
              clientPaymentChannel == ClientPaymentChannel.appleStore),
      webConfigured: isPaddleCheckoutConfigured,
    );

/// 根据本地渠道与对应实现的配置状态决定是否展示订阅能力。
bool subscriptionAvailableFor({
  required ClientPaymentChannel channel,
  required bool nativeStoreConfigured,
  required bool webConfigured,
}) {
  return switch (channel) {
    ClientPaymentChannel.appleStore ||
    ClientPaymentChannel.googlePlay => nativeStoreConfigured,
    ClientPaymentChannel.web => webConfigured,
    ClientPaymentChannel.unavailable => false,
  };
}

/// 当前是否走 Paddle 网页支付渠道（侧载 APK / 桌面）。
///
/// Paywall 据此切换购买动作：套餐仍由统一 UI 展示，点击后改为
/// 「服务端创建 Paddle checkout + 浏览器结账 + 回流对账」。
@riverpod
bool webCheckoutMode(Ref ref) => webCheckoutModeFor(
  channel: clientPaymentChannel,
  webConfigured: isPaddleCheckoutConfigured,
);

/// 仅 direct 且网页结账配置完整时进入 Web checkout 模式。
bool webCheckoutModeFor({
  required ClientPaymentChannel channel,
  required bool webConfigured,
}) => channel == ClientPaymentChannel.web && webConfigured;

/// 商店包是否展示「切换到 Web 支付」兜底入口。
///
/// 这是 UI 展示门控，不改变默认购买渠道；只有商店包、Paddle 后端可用、远程开关
/// 同时满足时才展示，便于按国家/审核策略灰度。
final showStoreWebCheckoutFallbackProvider = Provider<bool>((ref) {
  return showStoreWebCheckoutFallbackFor(
    channel: clientPaymentChannel,
    webConfigured: isPaddleBackendConfigured,
    remoteEnabled: ref.watch(
      remoteFeatureEnabledProvider(RemoteFeature.showStoreWebCheckoutFallback),
    ),
  );
});

/// 纯函数形式供测试覆盖渠道与开关矩阵。
bool showStoreWebCheckoutFallbackFor({
  required ClientPaymentChannel channel,
  required bool webConfigured,
  required bool remoteEnabled,
}) {
  final storeChannel =
      channel == ClientPaymentChannel.appleStore ||
      channel == ClientPaymentChannel.googlePlay;
  return storeChannel && webConfigured && remoteEnabled;
}
