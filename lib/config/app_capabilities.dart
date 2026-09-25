/// 本地版只禁用官方业务服务；词典、发音与语音模型资源下载继续可用。
const isLocalEdition =
    String.fromEnvironment('APP_EDITION', defaultValue: 'official') == 'local';

/// 禁用入口同时拦截深链，避免隐藏按钮后仍进入远程页面。
bool isLocalEditionBlockedRoute(String path) => const [
  '/login',
  '/account',
  '/paywall',
  '/discover',
  '/podcast-subscribe',
].any((prefix) => path == prefix || path.startsWith('$prefix/'));
