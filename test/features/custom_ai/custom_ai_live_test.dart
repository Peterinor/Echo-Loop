import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_client.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings.dart';
import 'package:echo_loop/features/custom_ai/custom_sentence_ai_client.dart';

/// 显式传入本机凭据时才运行；测试代码和输出均不记录密钥。
class _RealHttp extends HttpOverrides {}

void main() {
  const key = String.fromEnvironment('REASONING_API_KEY');
  const url = String.fromEnvironment('REASONING_BASE_URL');
  const model = String.fromEnvironment('REASONING_MODEL');
  test(
    'live user model: translation, analysis, dictionaries, chunks, chat and review',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final transport = CustomAiClient(
        const CustomAiSettings(baseUrl: url, model: model),
        readKey: () async => key,
      );
      final client = CustomSentenceAiClient(
        transport,
        transcribe: (_, __) async => 'I enjoy learning English every day.',
      );
      try {
        const sentence = 'I enjoy learning English every day.';
        final translation = await client
            .translateStream(
              sentence,
              accessToken: null,
              targetLanguage: 'zh-CN',
            )
            .last;
        expect(translation.translation.translation, isNotEmpty);
        final analysis = await client
            .analyzeStream(sentence, accessToken: null, targetLanguage: 'zh-CN')
            .last;
        expect(analysis.analysis.grammar, isNotEmpty);
        expect(
          (await client
                  .lookupWordStreamFrames(
                    'enjoy',
                    accessToken: null,
                    targetLanguage: 'zh-CN',
                  )
                  .last)
              .entry
              .isEmpty,
          isFalse,
        );
        expect(
          (await client
                  .lookupPhraseStreamFrames(
                    'look forward to',
                    accessToken: null,
                    targetLanguage: 'zh-CN',
                  )
                  .last)
              .entry
              .isEmpty,
          isFalse,
        );
        expect(
          (await client.senseGroupsStream(sentence, accessToken: null).last)
              .isFinal,
          isTrue,
        );
        expect(
          (await transport.chat([
            {
              'role': 'user',
              'content':
                  'Explain the word enjoy in one short Chinese sentence.',
            },
          ]).last).isFinal,
          isTrue,
        );
        final review = await client
            .evaluateReviewStream(
              audioFile: File('unused-in-text-evaluation-test'),
              originalText: sentence,
              targetLanguage: 'zh-CN',
              accessToken: null,
            )
            .last;
        expect(review.evaluation.rating, isNotNull);
        expect(review.evaluation.transcript, sentence);
      } finally {
        client.dispose();
        transport.dispose();
      }
    }, _RealHttp()),
    skip: key.isEmpty || url.isEmpty || model.isEmpty,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
