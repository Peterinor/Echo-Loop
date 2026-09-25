import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/dictionary/dictionary_entry.dart';
import '../../models/retell_review_evaluation.dart';
import '../../models/sense_group_result.dart';
import '../../models/sentence_ai_result.dart';
import '../../services/sentence_ai_api_client.dart';
import '../../utils/sense_group_validate.dart';
import 'custom_ai_client.dart';
import 'custom_ai_prompts.dart';

/// 复用原版业务结果与缓存；直连实现不读取或发送官方 token。
class CustomSentenceAiClient extends SentenceAiApiClient {
  CustomSentenceAiClient(this.client, {required this.transcribe})
    : super.withDio(Dio());
  final CustomAiClient client;
  final Future<String> Function(File audio, CancelToken? cancelToken)
  transcribe;

  Future<Map<String, Object?>> _object(
    String prompt,
    Map<String, Object?> input,
    CancelToken? token,
  ) => client.object(
    '$learningAiInstruction\n$prompt',
    input,
    cancelToken: token,
  );

  @override
  Stream<SentenceTranslationStreamFrame> translateStream(
    String text, {
    required String? accessToken,
    String? previousText,
    String? nextText,
    String? targetLanguage,
    CancelToken? cancelToken,
  }) async* {
    final json = await _object(translationPrompt, {
      'text': text,
      'previousText': previousText,
      'nextText': nextText,
      'targetLanguage': targetLanguage,
    }, cancelToken);
    final result = SentenceTranslation.fromJson(json);
    if (result.translation.trim().isEmpty) {
      throw const CustomAiException('模型未返回有效译文');
    }
    yield SentenceTranslationStreamFrame(translation: result, isFinal: true);
  }

  @override
  Stream<SentenceAnalysisStreamFrame> analyzeStream(
    String text, {
    required String? accessToken,
    String? targetLanguage,
    CancelToken? cancelToken,
  }) async* {
    final json = await _object(analysisPrompt, {
      'text': text,
      'targetLanguage': targetLanguage,
    }, cancelToken);
    final result = SentenceAnalysis.fromJson(json);
    if (result.grammar.isEmpty ||
        result.grammar.every((point) => point.isEmpty)) {
      throw const CustomAiException('模型未返回有效句子解析');
    }
    yield SentenceAnalysisStreamFrame(analysis: result, isFinal: true);
  }

  @override
  Stream<AiDictionaryStreamFrame> lookupWordStreamFrames(
    String word, {
    required String? accessToken,
    String? targetLanguage,
    CancelToken? cancelToken,
  }) async* {
    final json = await _object(wordPrompt, {
      'text': word,
      'targetLanguage': targetLanguage,
    }, cancelToken);
    final result = DictionaryEntry.fromJson(json);
    if (result.headword.trim().isEmpty ||
        result.meanings.isEmpty ||
        result.meanings.every(
          (m) => m.translation.isEmpty || m.examples.isEmpty,
        )) {
      throw const CustomAiException('模型未返回有效单词释义');
    }
    yield AiDictionaryStreamFrame(entry: result, isFinal: true);
  }

  @override
  Stream<AiDictionaryStreamFrame> lookupPhraseStreamFrames(
    String phrase, {
    required String? accessToken,
    String? targetLanguage,
    CancelToken? cancelToken,
  }) async* {
    final json = await _object(phrasePrompt, {
      'text': phrase,
      'targetLanguage': targetLanguage,
    }, cancelToken);
    final result = MultiWordDictionaryEntry.fromJson(json);
    if (result.headword.trim().isEmpty ||
        result.meanings.isEmpty ||
        result.meanings.every(
          (m) => m.translation.isEmpty || m.examples.isEmpty,
        )) {
      throw const CustomAiException('模型未返回有效词组释义');
    }
    yield AiDictionaryStreamFrame(entry: result, isFinal: true);
  }

  @override
  Stream<SenseGroupsStreamFrame> senseGroupsStream(
    String text, {
    required String? accessToken,
    CancelToken? cancelToken,
  }) async* {
    final json = await _object(senseGroupsPrompt, {'text': text}, cancelToken);
    final medium = json['medium'];
    final fine = json['fine'];
    if (medium is! List ||
        fine is! List ||
        medium.any((v) => v is! String) ||
        fine.any((v) => v is! String)) {
      throw const CustomAiException('模型意群格式不正确');
    }
    final result = SenseGroupResult(
      medium: medium.whereType<String>().toList(),
      fine: fine.whereType<String>().toList(),
    );
    if (!validateSenseGroupChunks(result.medium, text) ||
        !validateSenseGroupChunks(result.fine, text)) {
      throw const CustomAiException('模型意群未完整保留原句，请重试');
    }
    yield SenseGroupsStreamFrame(result: result, isFinal: true);
  }

  @override
  Stream<RetellReviewStreamFrame> evaluateReviewStream({
    required File audioFile,
    required String originalText,
    required String targetLanguage,
    required String? accessToken,
    CancelToken? cancelToken,
  }) async* {
    final transcript = await transcribe(audioFile, cancelToken);
    checkAiCancelled(cancelToken);
    if (transcript.trim().isEmpty) {
      throw const CustomAiException('未识别到有效语音，请重新录音');
    }
    yield RetellReviewStreamFrame(
      evaluation: RetellReviewEvaluation.fromJson({'transcript': transcript}),
      isFinal: false,
    );
    final json = await _object(retellPrompt, {
      'originalText': originalText,
      'transcript': transcript,
      'targetLanguage': targetLanguage,
    }, cancelToken);
    final result = RetellReviewEvaluation.fromJson({
      ...json,
      'transcript': transcript,
    });
    if (result.rating == null || result.summary.trim().isEmpty) {
      throw const CustomAiException('模型未返回有效复述评估');
    }
    yield RetellReviewStreamFrame(evaluation: result, isFinal: true);
  }
}
