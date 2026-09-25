import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echo_loop/config/app_capabilities.dart';
import 'package:echo_loop/database/daos/sentence_ai_cache_dao.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_client.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings_screen.dart';
import 'package:echo_loop/features/custom_ai/custom_sentence_ai_client.dart';
import 'package:echo_loop/features/onboarding_survey/providers/onboarding_survey_provider.dart';
import 'package:echo_loop/features/subscription/models/premium_feature.dart';
import 'package:echo_loop/features/subscription/providers/feature_access_provider.dart';
import 'package:echo_loop/features/subscription/providers/subscription_availability.dart';
import 'package:echo_loop/providers/sentence_ai_provider.dart';
import 'package:echo_loop/services/backend_dio.dart';
import 'package:echo_loop/services/dictionary/ai_dictionary_source.dart';
import 'package:echo_loop/services/dictionary/dictionary_source.dart';

class _Dao extends Mock implements SentenceAiCacheDao {}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.value);
  Map<String, Object?> value;
  int requests = 0;
  final requestOptions = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests++;
    requestOptions.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': jsonEncode(value)},
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'local edition blocks official transport before network dispatch',
    () async {
      final adapter = _Adapter({});
      final dio = createBackendDio(baseUrl: 'https://official.invalid')
        ..httpClientAdapter = adapter;
      await expectLater(
        dio.get<Object?>('/api/entitlements'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, 0);
      dio.close();
    },
    skip: !isLocalEdition,
  );

  test(
    'local access has no login or subscription side effects',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(featureAccessProvider(PremiumFeature.aiTranslation)),
        isTrue,
      );
      expect(
        container.read(featureAccessProvider(PremiumFeature.aiTranscription)),
        isFalse,
      );
      expect(container.read(subscriptionAvailabilityProvider), isFalse);
      expect(isLocalEditionBlockedRoute('/login/email'), isTrue);
      expect(isLocalEditionBlockedRoute('/discover/material'), isFalse);
      expect(isLocalEditionBlockedRoute('/podcast-subscribe'), isFalse);
      expect(isLocalEditionBlockedRoute('/collections/local'), isFalse);
    },
    skip: !isLocalEdition,
  );

  test(
    'local resource transport only allows anonymous read endpoints',
    () async {
      final adapter = _Adapter({});
      final dio = createBackendDio(
        baseUrl: 'https://official.invalid',
        allowAnonymousResources: true,
      )..httpClientAdapter = adapter;
      addTearDown(dio.close);
      for (final path in [
        '/api/v1/catalog',
        '/api/v2/collections',
        '/api/v2/collections/example',
        '/api/v2/collections/example/files/audio',
      ]) {
        await dio.get<Object?>(path);
      }
      expect(adapter.requests, 4);
      expect(
        adapter.requestOptions.every((options) => !options.followRedirects),
        isTrue,
      );
      expect(
        adapter.requestOptions.every(
          (options) => !options.headers.containsKey('Authorization'),
        ),
        isTrue,
      );
      for (final path in [
        '/api/entitlements',
        '/api/v1/ai/translate',
        '/api/v2/collections/example/delete',
        '/api/v2/collections/example/files',
        '/api/v2/collections/example/files/audio/subtitle',
        'https://other.invalid/api/v1/catalog',
      ]) {
        await expectLater(dio.get<Object?>(path), throwsA(isA<DioException>()));
      }
      await expectLater(
        dio.post<Object?>('/api/v2/collections'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, 4);
    },
    skip: !isLocalEdition,
  );

  test(
    'anonymous translation caches complete results and isolates model changes',
    () async {
      final dao = _Dao();
      final cache = <String, String>{};
      when(() => dao.getByHash(any(), any())).thenAnswer(
        (call) async =>
            cache['${call.positionalArguments[0]}:${call.positionalArguments[1]}'],
      );
      when(() => dao.upsert(any(), any(), any())).thenAnswer((call) async {
        cache['${call.positionalArguments[0]}:${call.positionalArguments[1]}'] =
            call.positionalArguments[2].toString();
      });
      final adapter = _Adapter({'translation': '你好'});
      final transport = CustomAiClient(
        const CustomAiSettings(
          baseUrl: 'https://test.invalid/v1',
          model: 'one',
        ),
        readKey: () async => 'key',
        dio: Dio()..httpClientAdapter = adapter,
      );
      final api = CustomSentenceAiClient(
        transport,
        transcribe: (_, __) async => 'Hello',
      );
      addTearDown(() {
        api.dispose();
        transport.dispose();
      });
      final notifier = SentenceAiNotifier(
        cacheDao: dao,
        apiClient: api,
        cacheNamespace: 'model-one',
      );
      expect(
        (await notifier
                .getTranslationStream('Hello', targetLanguage: 'zh-CN')
                .last)
            .translation,
        '你好',
      );
      await notifier
          .getTranslationStream('Hello', targetLanguage: 'zh-CN')
          .last;
      expect(adapter.requests, 1);
      final restarted = SentenceAiNotifier(
        cacheDao: dao,
        apiClient: api,
        cacheNamespace: 'model-one',
      );
      expect(
        await restarted.preloadTranslationFromDb(
          'Hello',
          targetLanguage: 'zh-CN',
        ),
        isTrue,
      );
      expect(adapter.requests, 1);
      final changed = SentenceAiNotifier(
        cacheDao: dao,
        apiClient: api,
        cacheNamespace: 'model-two',
      );
      expect(
        await changed.preloadTranslationFromDb(
          'Hello',
          targetLanguage: 'zh-CN',
        ),
        isFalse,
      );
      await changed.getTranslationStream('Hello', targetLanguage: 'zh-CN').last;
      expect(adapter.requests, 2);
      final source = AiDictionarySource(
        cacheDao: () => dao,
        apiClient: () => api,
        cacheNamespace: () => 'model-one',
      );
      adapter.value = {
        'headword': 'hello',
        'meanings': [
          {
            'translation': ['你好'],
            'examples': [
              {'sentence': 'Hello!', 'translation': '你好！'},
            ],
          },
        ],
      };
      await source.lookup(const DictionaryLookupRequest(word: 'hello'));
      expect(adapter.requests, 3);
      adapter.value = {
        'medium': ['wrong'],
        'fine': ['wrong'],
      };
      await expectLater(
        notifier.getSenseGroupsStream('Hello').toList(),
        throwsA(isA<CustomAiException>()),
      );
      expect(notifier.getCachedSenseGroups('Hello'), isNull);
    },
    skip: !isLocalEdition,
  );

  test(
    'review sends recognized text and opens a partial frame before final feedback',
    () async {
      final adapter = _Adapter({'summary': '准确', 'rating': 'good'});
      final transport = CustomAiClient(
        const CustomAiSettings(
          baseUrl: 'https://test.invalid/v1',
          model: 'one',
        ),
        readKey: () async => 'key',
        dio: Dio()..httpClientAdapter = adapter,
      );
      final api = CustomSentenceAiClient(
        transport,
        transcribe: (_, __) async => 'Hello',
      );
      addTearDown(() {
        api.dispose();
        transport.dispose();
      });
      final frames = await api
          .evaluateReviewStream(
            audioFile: File('not-uploaded'),
            originalText: 'Hello',
            targetLanguage: 'zh-CN',
            accessToken: null,
          )
          .toList();
      expect(frames.first.isFinal, isFalse);
      expect(frames.first.evaluation.transcript, 'Hello');
      expect(frames.last.isFinal, isTrue);
    },
  );

  testWidgets(
    'model settings rejects invalid endpoint before writing credentials',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: CustomAiSettingsScreen()),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'http://invalid');
      await tester.enterText(find.byType(TextField).at(1), 'test');
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(find.text('请填写有效的 HTTPS API 地址和模型名称'), findsOneWidget);
      expect(prefs.getString('custom_ai_base_url'), isNull);
    },
  );
}
