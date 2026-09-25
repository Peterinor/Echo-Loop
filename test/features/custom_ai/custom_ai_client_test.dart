import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_client.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  const config = CustomAiSettings(
    baseUrl: 'https://example.com/v1',
    model: 'test',
  );
  test('accepts a pasted Bearer key without duplicating prefix', () {
    expect(normalizeApiKey(' Bearer secret '), 'secret');
    expect(normalizeApiKey('secret'), 'secret');
  });
  test('isolates model caches without depending on the secret', () {
    expect(
      config.cacheNamespace,
      isNot(
        const CustomAiSettings(
          baseUrl: 'https://example.com/v1',
          model: 'other',
        ).cacheNamespace,
      ),
    );
  });
  test(
    'structured request uses user endpoint and no official authentication',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) {
          expect(
            request.uri.toString(),
            'https://example.com/v1/chat/completions',
          );
          expect(request.headers['Authorization'], 'Bearer secret');
          expect(request.headers.containsKey('x-app-platform'), isFalse);
          expect(request.followRedirects, isFalse);
          return ResponseBody.fromString(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': '{"translation":"你好"}'},
                },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });
      final client = CustomAiClient(
        config,
        readKey: () async => 'Bearer secret',
        dio: dio,
      );
      expect(await client.object('Return JSON', {'text': 'Hello'}), {
        'translation': '你好',
      });
      client.dispose();
    },
  );
  test('does not accept truncated model output as a complete result', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromString(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '{}'},
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
    final client = CustomAiClient(
      config,
      readKey: () async => 'secret',
      dio: dio,
    );
    await expectLater(
      client.object('JSON', {}),
      throwsA(isA<CustomAiException>()),
    );
    client.dispose();
  });
  test(
    'provider authentication errors are sanitized and never become membership errors',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          (_) => ResponseBody.fromString(
            '{"error":"secret echoed by provider"}',
            401,
          ),
        );
      final client = CustomAiClient(
        config,
        readKey: () async => 'secret',
        dio: dio,
      );
      await expectLater(
        client.object('JSON', {}),
        throwsA(
          predicate(
            (e) => e is CustomAiException && !e.toString().contains('secret'),
          ),
        ),
      );
      client.dispose();
    },
  );
  test('SSE accepts split UTF8 and refuses an unfinished stream', () async {
    final bytes = utf8.encode(
      'data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}\n\n'
      'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
      'data: [DONE]\n\n',
    );
    final frames = await decodeCompletionStream(
      Stream<Uint8List>.fromIterable(bytes.map((b) => Uint8List.fromList([b]))),
    ).toList();
    expect(frames.last.text, '你好');
    expect(frames.last.isFinal, isTrue);
    await expectLater(
      decodeCompletionStream(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          ),
        ),
      ).toList(),
      throwsA(isA<CustomAiException>()),
    );
  });

  test('cancelling while reading the key prevents a model request', () async {
    final key = Completer<String>();
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final client = CustomAiClient(config, readKey: () => key.future, dio: dio);
    final token = CancelToken();
    final result = client.object('JSON', {}, cancelToken: token);
    final assertion = expectLater(
      result,
      throwsA(
        predicate(
          (error) => error is DioException && CancelToken.isCancel(error),
        ),
      ),
    );
    token.cancel();
    key.complete('secret');
    await assertion;
    expect(requests, 0);
    client.dispose();
  });
}
