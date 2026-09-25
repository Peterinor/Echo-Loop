// 后端 API 配置
//
// 集中管理后端服务器地址，方便切换开发/生产环境。
import 'app_capabilities.dart';

/// 后端服务器基础 URL
///
/// 通过 `--dart-define=API_BASE_URL=https://xxx` 注入。
/// 未指定时默认使用本地开发地址。
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

/// 本地版只读资源单独配置，避免未注入业务地址时请求 localhost。
/// 官方版继续沿用原有后端配置。
const resourceApiBaseUrl = isLocalEdition
    ? String.fromEnvironment(
        'RESOURCE_API_BASE_URL',
        defaultValue: 'https://www.echo-loop.top',
      )
    : apiBaseUrl;
