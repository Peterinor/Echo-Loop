import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_loop/services/dictionary_download_manager.dart';
import 'package:echo_loop/services/dictionary/dictionary_catalog.dart';
import 'package:echo_loop/services/app_logger.dart';
import 'package:echo_loop/services/reliable_http_downloader.dart';
import 'package:echo_loop/services/resource_install_manifest.dart';

/// 按固定下载 URL 返回预置 ZIP；其余请求 404。
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({
    required this.downloadUrl,
    this.payload,
    this.downloadStatusCode = 200,
  });

  final String downloadUrl;
  final List<int>? payload;
  final int downloadStatusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == downloadUrl) {
      if (downloadStatusCode != 200 || payload == null) {
        return ResponseBody(
          const Stream.empty(),
          downloadStatusCode,
          headers: {},
        );
      }
      return ResponseBody(
        Stream.fromIterable([Uint8List.fromList(payload!)]),
        200,
        headers: {
          'content-length': [payload!.length.toString()],
        },
      );
    }
    return ResponseBody(const Stream.empty(), 404, headers: {});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog 包含当前两种语言的固定版本资源', () {
    expect(
      dictionarySpecOf('zh-CN').archiveUrl,
      'https://cdn.echo-loop.top/dictionary/en_zh-CN/'
      'dict_en_zh-CN-v1.sqlite.zip',
    );
    expect(
      dictionarySpecOf('zh-CN').archiveSha256,
      '2acfc22aae4658b707973c508e1356d4c8ce4bc07c502c6d2c3030a95bc5f5e9',
    );
    expect(dictionarySpecOf('zh-TW').resourceId, 'dict-en_zh-TW-v1');
    expect(dictionarySpecOf('zh-CN').estimatedDownloadBytes, 12552930);
    expect(dictionarySpecOf('zh-TW').estimatedDownloadBytes, 12552893);
  });

  late Directory fakeAppSupportDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.clear();
    fakeAppSupportDir = Directory.systemTemp.createTempSync(
      'dict_manager_support_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return fakeAppSupportDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (fakeAppSupportDir.existsSync()) {
      fakeAppSupportDir.deleteSync(recursive: true);
    }
  });

  DictionaryDownloadManager manager(_MockAdapter adapter) {
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final zip = _dictionaryArchivePayload();
    final sha = sha256.convert(zip).toString();
    return DictionaryDownloadManager.withDio(
      dio,
      specs: {
        'zh': DictionarySpec(
          nativeLanguage: 'zh',
          resourceId: 'dict-en_zh-v1',
          archiveUrl: adapter.downloadUrl,
          archiveSha256: sha,
          estimatedDownloadBytes: zip.length,
        ),
      },
    );
  }

  test('download 成功 → 固定 URL 解压为 dict.sqlite 并写入安装清单', () async {
    final payload = _dictionaryArchivePayload();
    final m = manager(
      _MockAdapter(
        downloadUrl: 'http://mock.local/dict-v1.sqlite.zip',
        payload: payload,
      ),
    );

    final path = await m.download('zh');

    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsBytesSync(), List<int>.filled(16, 7));
    final manifest = await readResourceInstallManifest(
      Directory(p.dirname(path)),
    );
    expect(manifest?.resourceId, 'dict-en_zh-v1');
    expect(manifest?.resourceSize, 16);
    expect(
      AppLogger.instance.entries.any(
        (entry) =>
            entry.tag == 'Dict' &&
            entry.message.contains('download finished lang=zh') &&
            entry.message.contains('elapsedMs='),
      ),
      isTrue,
    );
  });

  test('归档下载网络失败 → 抛结构化 ReliableDownloadException(httpStatus) 且不留残留', () async {
    final m = manager(
      _MockAdapter(
        downloadUrl: 'http://mock.local/dict-v1.sqlite.zip',
        downloadStatusCode: 404,
      ),
    );

    await expectLater(
      m.download('zh'),
      throwsA(
        isA<ReliableDownloadException>().having(
          (e) => e.kind,
          'kind',
          ReliableDownloadFailure.httpStatus,
        ),
      ),
    );
    expect(
      AppLogger.instance.entries.any(
        (entry) =>
            entry.tag == 'Dict' &&
            entry.message.contains('download failed lang=zh') &&
            entry.message.contains('elapsedMs='),
      ),
      isTrue,
    );

    final dictDir = Directory(
      p.join(fakeAppSupportDir.path, 'dictionary', 'en_zh'),
    );
    final leftovers = dictDir.existsSync()
        ? dictDir.listSync().whereType<File>()
        : const <File>[];
    expect(leftovers, isEmpty);
  });
}

List<int> _dictionaryArchivePayload() {
  final file = ArchiveFile('dict_en_zh-v1.sqlite', 16, List<int>.filled(16, 7))
    ..lastModTime = DateTime.utc(2020).millisecondsSinceEpoch ~/ 1000;
  return ZipEncoder().encode(Archive()..addFile(file));
}
