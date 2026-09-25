import 'package:dio/dio.dart';

/// 本地版在发送前拒绝官方业务请求，仅显式资源客户端可匿名读取同源白名单。
class LocalBackendPolicy extends Interceptor {
  LocalBackendPolicy({
    required this.baseUrl,
    required this.allowAnonymousResources,
  });

  final String baseUrl;
  final bool allowAnonymousResources;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (allowAnonymousResources &&
        options.method == 'GET' &&
        options.uri.origin == Uri.parse(baseUrl).origin &&
        _isAnonymousResourcePath(options.uri.path)) {
      // 不自动跟随重定向，避免白名单请求跳转到未获准的接口。
      options.followRedirects = false;
      handler.next(options);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: '本地版已禁用官方业务服务',
      ),
    );
  }

  /// 精确匹配匿名目录、合集详情与文件详情，保持与上游资源协议一致。
  bool _isAnonymousResourcePath(String path) =>
      path == '/api/v1/catalog' ||
      path == '/api/v2/collections' ||
      RegExp(r'^/api/v2/collections/[^/]+(?:/files/[^/]+)?$').hasMatch(path);
}
