/// 网页词典主框架导航的加载阶段。
enum WebDictionaryLoadPhase { loading, ready, error }

/// 维护当前主框架导航状态，并拒绝 URL 已过期的回调。
class WebDictionaryLoadState {
  /// 创建加载状态快照。
  const WebDictionaryLoadState({
    required this.phase,
    required this.generation,
    required this.activeUrl,
  });

  /// 创建首屏等待状态。
  factory WebDictionaryLoadState.initial(String url) => WebDictionaryLoadState(
    phase: WebDictionaryLoadPhase.loading,
    generation: 0,
    activeUrl: url,
  );

  /// 当前主框架导航的阶段。
  final WebDictionaryLoadPhase phase;

  /// 当前导航代际，用于隔离旧导航留下的计时器。
  final int generation;

  /// 当前主框架 URL，用于忽略较早导航的回调。
  final String? activeUrl;

  /// 页面是否仍在等待可见提交或加载结束。
  bool get isLoading => phase == WebDictionaryLoadPhase.loading;

  /// 页面开始新导航，并使先前的超时计时器失效。
  WebDictionaryLoadState navigationStarted(String? url) =>
      WebDictionaryLoadState(
        phase: WebDictionaryLoadPhase.loading,
        generation: generation + 1,
        activeUrl: url ?? activeUrl,
      );

  /// 用户请求重试当前 URL。
  WebDictionaryLoadState retryStarted() => WebDictionaryLoadState(
    phase: WebDictionaryLoadPhase.loading,
    generation: generation + 1,
    activeUrl: activeUrl,
  );

  /// 页面已进入可显示阶段；不等待全部资源完成。
  WebDictionaryLoadState pageCommitted(String? url) =>
      _accepts(url) ? _withPhase(WebDictionaryLoadPhase.ready) : this;

  /// 平台加载完成回调兜底，包括没有发送可见提交事件的平台。
  WebDictionaryLoadState loadStopped(String? url) =>
      _accepts(url) ? _withPhase(WebDictionaryLoadPhase.ready) : this;

  /// 当前主框架导航失败；旧 URL 的迟到错误不影响新导航。
  WebDictionaryLoadState loadFailed(String? url) =>
      _accepts(url) ? _withPhase(WebDictionaryLoadPhase.error) : this;

  /// 等待超时后结束加载态；旧代际的计时器回调不影响当前状态。
  WebDictionaryLoadState timedOut(int expectedGeneration) =>
      expectedGeneration == generation && isLoading
      ? _withPhase(WebDictionaryLoadPhase.error)
      : this;

  bool _accepts(String? url) =>
      url == null || activeUrl == null || url == activeUrl;

  WebDictionaryLoadState _withPhase(WebDictionaryLoadPhase value) =>
      phase == value
      ? this
      : WebDictionaryLoadState(
          phase: value,
          generation: generation,
          activeUrl: activeUrl,
        );
}
