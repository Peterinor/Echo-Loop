import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers/asr_engine_provider.dart';
import '../../providers/local_transcription_task_provider.dart';
import '../../providers/offline_asr_settings_provider.dart';
import '../../services/asr/offline_asr_engine.dart';
import 'custom_ai_client.dart';

/// 复述录音只在设备上解码和识别，模型服务仅接收转录文字。
final localReviewTranscriberProvider =
    Provider<Future<String> Function(File, CancelToken?)>((ref) {
      final manager = ref.read(asrModelManagerProvider);
      final model = ref.watch(
        offlineAsrSettingsProvider.select((s) => s.selectedModel),
      );
      final createEngine = ref.read(localTranscriptionEngineFactoryProvider);
      final transcode = ref.read(localTranscriptionTranscodeServiceProvider);
      return (audio, token) async {
        checkAiCancelled(token);
        if (!await manager.isModelDownloaded(model.id)) {
          throw const CustomAiException('请先在语音识别设置中下载模型');
        }
        final directory = await Directory(
          p.join((await getTemporaryDirectory()).path, 'local_review'),
        ).createTemp();
        final engine = createEngine();
        try {
          final wav = File(p.join(directory.path, 'recording.wav'));
          if (!await transcode.transcodeToPcmWav16k(
            source: audio,
            output: wav,
          )) {
            throw const CustomAiException('录音解码失败，请重新录音');
          }
          checkAiCancelled(token);
          await engine.initialize(
            AsrModelConfig(
              model: model,
              modelDir: await manager.modelDir(model.id),
              numThreads: AsrModelConfig.recommendedThreads(),
            ),
          );
          checkAiCancelled(token);
          final result = await engine.transcribe(wav.path);
          checkAiCancelled(token);
          return result.text;
        } finally {
          // 原生识别结束后才能释放引擎；取消仅作废结果，避免销毁仍在推理的资源。
          await engine.dispose();
          await directory.delete(recursive: true);
        }
      };
    });
