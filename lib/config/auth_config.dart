// 认证配置
//
// 通过 `--dart-define` 注入 Supabase 与 Google OAuth 凭据。
// 三套环境（dev / staging / prod）各自维护一份 auth.env，本地 build 时用
// `--dart-define-from-file=auth.env` 加载。
//
// 任一字段缺失（空字符串）时，main.dart 跳过 Supabase 初始化，
// 登录相关功能不可用但 app 仍可匿名运行。
library;

import 'app_capabilities.dart';

/// Supabase 项目 URL（如 https://xxx.supabase.co）。
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Supabase publishable key（公开可暴露的客户端密钥）。
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

/// Google OAuth Web Client ID，仅 Android 平台用作 `serverClientId`。
/// iOS / macOS 不接 Google 登录，无需配。
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// 认证配置是否完整。
///
/// 当 URL 或 publishable key 缺失时返回 false，main.dart 据此跳过 Supabase 初始化。
bool get isAuthConfigured =>
    !isLocalEdition &&
    supabaseUrl.isNotEmpty &&
    supabasePublishableKey.isNotEmpty;
