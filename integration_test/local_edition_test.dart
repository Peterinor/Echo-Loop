/// Android 本地版真实启动、资源下载、播放、TTS/ASR 和备份验证。
/// 使用 APP_EDITION=local；不清空既有数据库，也不写入测试账号。
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_loop/main.dart' as app;
import 'package:echo_loop/config/app_capabilities.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings.dart';
import 'package:echo_loop/services/sentence_ai_api_client.dart';
import 'package:echo_loop/database/providers.dart';
import 'package:echo_loop/providers/audio_library_provider.dart';
import 'package:echo_loop/providers/dictionary_provider.dart';
import 'package:echo_loop/providers/pronunciation/pronunciation_providers.dart';
import 'package:echo_loop/providers/startup_bootstrap_provider.dart';
import 'package:echo_loop/router/app_router.dart';
import 'package:echo_loop/services/asr/asr_model_manager.dart';
import 'package:echo_loop/services/asr/offline_asr_engine.dart';
import 'package:echo_loop/services/asr/sherpa_onnx_engine.dart';
import 'package:echo_loop/services/backup/backup_service.dart';
import 'package:echo_loop/services/dictionary_service.dart';
import 'package:echo_loop/services/tts/kokoro_model_catalog.dart';
import 'package:echo_loop/services/tts/kokoro_model_manager.dart';
import 'package:echo_loop/services/tts/kokoro_tts_engine.dart';
import 'package:echo_loop/services/tts/tts_engine.dart';
import 'package:echo_loop/features/audio_import/audio_transcode_service.dart';

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String label, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Timeout: $label');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'original app local edition: startup, settings, resources and native audio',
    (tester) async {
      expect(isLocalEdition, isTrue);
      final prefs = await SharedPreferences.getInstance();
      // 设备验收直接进入功能页；不改写用户问卷答案或学习记录。
      if (!prefs.containsKey('onboarding_completed_at_ms')) {
        await prefs.setInt(
          'onboarding_completed_at_ms',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      app.main();
      await _until(
        tester,
        () => find.byType(app.EchoLoopApp).evaluate().isNotEmpty,
        'first frame',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.EchoLoopApp)),
      );
      await _until(
        tester,
        () => container.read(localStartupProvider).hasValue,
        'local startup',
      );
      final thirdParty = await container.read(thirdPartyStartupProvider.future);
      expect(thirdParty.isSupabaseReady, isFalse);
      expect(thirdParty.isRevenueCatReady, isFalse);
      final router = container.read(appRouterProvider);
      router.go(AppRoutes.settings);
      await _until(
        tester,
        () => find.text('AI 模型设置').evaluate().isNotEmpty,
        'settings',
      );
      expect(find.text('Account'), findsNothing);
      await tester.tap(find.text('AI 模型设置'));
      await _until(
        tester,
        () => find.text('API Base URL').evaluate().isNotEmpty,
        'model configuration',
      );
      expect(find.text('API Key'), findsOneWidget);
      const key = String.fromEnvironment('REASONING_API_KEY');
      const url = String.fromEnvironment('REASONING_BASE_URL');
      const model = String.fromEnvironment('REASONING_MODEL');
      if (key.isNotEmpty && url.isNotEmpty && model.isNotEmpty) {
        // 只在显式提供验收凭据时操作真实配置页；正式包不注入这些值。
        await tester.enterText(find.byType(TextField).at(0), url);
        await tester.enterText(find.byType(TextField).at(1), model);
        await tester.enterText(find.byType(TextField).at(2), key);
        await tester.ensureVisible(find.text('保存配置'));
        await tester.tap(find.text('保存配置'));
        await _until(
          tester,
          () => find.text('配置已保存').evaluate().isNotEmpty,
          'secure model settings',
        );
        expect(container.read(customAiSettingsProvider).model, model);
        final translated = await container
            .read(sentenceAiApiClientProvider)
            .translateStream(
              'I enjoy learning English.',
              accessToken: null,
              targetLanguage: 'zh-CN',
            )
            .last;
        expect(translated.translation.translation, isNotEmpty);
        debugPrint(
          '[LocalEdition] device secure settings and real AI translation verified',
        );
      }
      await tester.pageBack();
      await tester.pump();
      router.go('/discover');
      await _until(
        tester,
        () =>
            router.routerDelegate.currentConfiguration.uri.path ==
            AppRoutes.settings,
        'blocked remote route',
      );
      expect(tester.takeException(), isNull);

      await _until(
        tester,
        () =>
            container.read(dictionaryProvider).status ==
                DictionaryStatus.downloaded ||
            container.read(dictionaryProvider).status ==
                DictionaryStatus.failed,
        'dictionary download',
        timeout: const Duration(minutes: 10),
      );
      expect(
        container.read(dictionaryProvider).status,
        DictionaryStatus.downloaded,
      );
      expect(DictionaryService.instance.lookup('hello'), isNotNull);
      await _until(
        tester,
        () =>
            container.read(pronunciationLibraryProvider).isReady ||
            container.read(pronunciationLibraryProvider).status ==
                PronunciationLibraryStatus.failed,
        'pronunciation download',
        timeout: const Duration(minutes: 10),
      );
      expect(container.read(pronunciationLibraryProvider).isReady, isTrue);
      debugPrint(
        '[LocalEdition] dictionary and pronunciation resources verified',
      );

      await container.read(audioLibraryProvider.notifier).loadLibrary();
      final items = container.read(audioLibraryProvider).audioItems;
      expect(items, isNotEmpty);
      final path = await items
          .firstWhere((item) => item.audioPath != null)
          .getFullAudioPath();
      expect(path, isNotNull);
      if (path != null) {
        final player = Player();
        try {
          await player.open(Media(path));
          await player.stream.position
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 30));
          await player.pause();
        } finally {
          await player.dispose();
        }
      }
      debugPrint('[LocalEdition] original local audio playback verified');

      final temp = await getTemporaryDirectory();
      final backup = BackupService(container.read(appDatabaseProvider));
      final backupPath = await backup.exportData(
        outputDir: temp.path,
        appVersion: 'local-test',
        platform: 'android',
      );
      await backup.readManifest(backupPath);
      expect(await File(backupPath).length(), greaterThan(0));
      await File(backupPath).delete();
      debugPrint('[LocalEdition] real database backup verified');

      final ttsManager = KokoroModelManager(
        spec: kokoroSpecOf(KokoroModelVariant.int8),
      );
      final asrManager = AsrModelManager();
      final tts = KokoroTtsEngine(
        resolvePaths: ttsManager.kokoroConfigPaths,
        numThreads: 2,
      );
      final asr = SherpaOnnxEngine();
      try {
        if (!await ttsManager.isModelDownloaded()) {
          await ttsManager.downloadModel();
        }
        final speech = await tts.synthesize(
          'Hello, I enjoy learning English every day.',
          outputDir: temp.path,
          baseName: 'local-edition-native-test',
          config: const TtsSpeechConfig(languageTag: 'en-US'),
        );
        expect(speech, isNotNull);
        if (speech == null) return;
        expect(await File(speech.filePath).length(), greaterThan(44));
        await tts.dispose();
        debugPrint('[LocalEdition] real Kokoro synthesis verified');
        const model = AsrModelInfo(
          id: 'whisper-tiny-en-int8',
          displayName: 'Whisper Tiny',
          type: AsrModelType.whisper,
        );
        await asrManager.downloadModel(model.id);
        await asrManager.downloadModel(vadModelId);
        expect(await asrManager.isModelDownloaded(model.id), isTrue);
        final wav = File('${temp.path}/local-edition-asr-test.wav');
        expect(
          await AudioTranscodeService().transcodeToPcmWav16k(
            source: File(speech.filePath),
            output: wav,
          ),
          isTrue,
        );
        await asr.initialize(
          AsrModelConfig(
            model: model,
            modelDir: await asrManager.modelDir(model.id),
            numThreads: 2,
          ),
        );
        final result = await asr.transcribe(wav.path);
        expect(result.text.trim(), isNotEmpty);
        debugPrint('[LocalEdition] real Whisper recognition verified');
        await File(speech.filePath).delete();
        await wav.delete();
      } finally {
        await asr.dispose();
        await tts.dispose();
        asrManager.dispose();
        ttsManager.dispose();
      }
      router.go(AppRoutes.study);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
