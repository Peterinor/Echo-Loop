import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chatbot/services/ndjson_text_stream.dart';
import 'custom_ai_settings.dart';

/// 取消仍沿用 Dio 的取消异常，业务层不会将用户停止误报为失败。
void checkAiCancelled(CancelToken? token) {
  final error = token?.cancelError;
  if (error != null) throw error;
}

/// 安全的用户可读错误：不包含响应体、请求头或密钥。
class CustomAiException implements Exception {
  const CustomAiException(this.message);
  final String message;
  @override
  String toString() => message;
}

final customAiClientProvider = Provider<CustomAiClient>((ref) {
  final config = ref.watch(customAiSettingsProvider);
  final store = ref.read(customAiKeyStoreProvider);
  final client = CustomAiClient(
    config,
    readKey: () async => await store.read(key: customAiKeyStorageKey) ?? '',
  );
  ref.onDispose(client.dispose);
  return client;
});

/// 独立的用户模型客户端，不经过官方鉴权、日志和会员拦截器。
class CustomAiClient {
  CustomAiClient(this.config, {required this.readKey, Dio? dio})
    : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
  }
  final CustomAiSettings config;
  final Future<String> Function() readKey;
  final Dio _dio;

  Future<Response<T>> _request<T>(
    List<Map<String, Object?>> messages, {
    required bool stream,
    bool json = false,
    CancelToken? cancelToken,
  }) async {
    if (!config.isConfigured) throw const CustomAiException('请先在设置中配置 AI 模型');
    final uri = config.completionUri;
    final key = normalizeApiKey(await readKey());
    if (key.isEmpty) throw const CustomAiException('请在 AI 模型设置中填写 API Key');
    checkAiCancelled(cancelToken);
    try {
      return await _dio.post<T>(
        uri.toString(),
        data: {
          'model': config.model,
          'messages': messages,
          'stream': stream,
          if (json) 'response_format': {'type': 'json_object'},
        },
        options: Options(
          headers: {'Authorization': 'Bearer $key'},
          contentType: Headers.jsonContentType,
          responseType: stream ? ResponseType.stream : ResponseType.json,
          followRedirects: false,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw CustomAiException(switch (error.response?.statusCode) {
        401 || 403 => '模型服务鉴权失败，请检查 API Key 和模型权限',
        429 => '模型服务限流或额度不足，请稍后重试或检查供应商账户',
        400 || 404 => '模型服务不接受请求，请检查 API 地址、模型名称和协议支持',
        _ => '模型请求失败，请检查网络或稍后重试',
      });
    }
  }

  /// 结构化任务只有完整且合法的 JSON 才返回；截断结果不得进入业务缓存。
  Future<Map<String, Object?>> object(
    String instruction,
    Map<String, Object?> input, {
    CancelToken? cancelToken,
  }) async {
    final response = await _request<Object?>(
      [
        {'role': 'system', 'content': instruction},
        {'role': 'user', 'content': jsonEncode(input)},
      ],
      stream: false,
      json: true,
      cancelToken: cancelToken,
    );
    checkAiCancelled(cancelToken);
    final root = response.data;
    final choices = root is Map ? root['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map && choice['finish_reason'] == 'stop') {
        final message = choice['message'];
        final content = message is Map ? message['content'] : null;
        if (content is String) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is Map<String, Object?>) return decoded;
          } on FormatException {
            throw const CustomAiException('模型返回格式不正确，请重试');
          }
        }
      }
    }
    throw const CustomAiException('模型未返回完整结果，请重试');
  }

  /// 对话使用标准 SSE，保留停止、增量显示和完整结束校验。
  Stream<ChatTextFrame> chat(
    List<Map<String, Object?>> messages, {
    CancelToken? cancelToken,
  }) async* {
    final response = await _request<ResponseBody>(
      messages,
      stream: true,
      cancelToken: cancelToken,
    );
    final body = response.data;
    if (body == null) throw const CustomAiException('模型响应为空');
    try {
      yield* decodeCompletionStream(
        body.stream.timeout(const Duration(seconds: 120)),
      );
    } catch (error) {
      checkAiCancelled(cancelToken);
      if (error is CustomAiException) rethrow;
      throw const CustomAiException('模型响应中断，请重试');
    }
  }

  void dispose() => _dio.close(force: true);
}

/// SSE 按事件边界解析，兼容网络分包、UTF-8 分片和多行 data。
Stream<ChatTextFrame> decodeCompletionStream(Stream<List<int>> bytes) async* {
  final data = <String>[];
  var text = '';
  var stopped = false;
  await for (final line
      in bytes
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
      continue;
    }
    if (line.isNotEmpty || data.isEmpty) continue;
    final payload = data.join('\n');
    data.clear();
    if (payload == '[DONE]') {
      if (!stopped || text.trim().isEmpty) {
        throw const CustomAiException('模型未完整结束响应');
      }
      yield ChatTextFrame(text: text, isFinal: true);
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const CustomAiException('模型流式格式不正确');
    }
    if (decoded is! Map || decoded.containsKey('error')) {
      throw const CustomAiException('模型流式响应失败');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final choice = choices.first;
    if (choice is! Map) throw const CustomAiException('模型流式格式不正确');
    final delta = choice['delta'];
    final part = delta is Map ? delta['content'] : null;
    if (part is String && part.isNotEmpty) {
      text += part;
      yield ChatTextFrame(text: text, isFinal: false);
    }
    final reason = choice['finish_reason'];
    if (reason != null) {
      if (reason != 'stop') throw const CustomAiException('模型输出被截断或拒绝，请重试');
      stopped = true;
    }
  }
  throw const CustomAiException('模型响应中断，请重试');
}
