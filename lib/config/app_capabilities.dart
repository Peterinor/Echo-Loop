/// 本地版禁用账号、付费和官方 AI；匿名学习资源、词典与语音模型下载可用。
const isLocalEdition =
    String.fromEnvironment('APP_EDITION', defaultValue: 'official') == 'local';

/// 禁用入口同时拦截深链，避免隐藏按钮后仍进入远程页面。
bool isLocalEditionBlockedRoute(String path) => const [
  '/login',
  '/account',
  '/paywall',
].any((prefix) => path == prefix || path.startsWith('$prefix/'));
