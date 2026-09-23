import 'dart:io';

import 'package:dio/dio.dart';
import 'package:echo_loop/features/podcast/data/podcast_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this.body);

  String body;
  int callCount = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    callCount++;
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

const _firstBody = '''
{
  "podcastCatalogs": [
    {
      "id": "podcast-1",
      "applePodcastUrl": "https://podcasts.apple.com/example",
      "rssUrl": "https://example.com/feed.xml",
      "imageUrl": null,
      "title": "Featured English",
      "description": "Short English lessons"
    }
  ]
}
''';

void main() {
  test('解析 Podcast catalog、写入缓存，并在非 force 刷新时节流', () async {
    final directory = await Directory.systemTemp.createTemp('podcast-catalog-');
    addTearDown(() => directory.delete(recursive: true));
    final dio = _FakeDio(_firstBody);
    final service = PodcastCatalogService.withDio(
      dio: dio,
      resolveDir: () async => directory,
    );

    final updated = await service.refresh(force: true);

    expect(updated, isA<PodcastCatalogUpdated>());
    expect(service.cached?.podcasts.single.title, 'Featured English');
    expect(
      service.cached?.podcasts.single.subscriptionInputUrl,
      'https://podcasts.apple.com/example',
    );
    expect(dio.callCount, 1);
    expect(await File('${directory.path}/catalog.json').exists(), isTrue);
    expect(await service.refresh(), isA<PodcastCatalogThrottled>());
    expect(dio.callCount, 1);
  });

  test('新 service 可以从本地缓存恢复精选 Podcast', () async {
    final directory = await Directory.systemTemp.createTemp('podcast-catalog-');
    addTearDown(() => directory.delete(recursive: true));
    final writer = PodcastCatalogService.withDio(
      dio: _FakeDio(_firstBody),
      resolveDir: () async => directory,
    );
    await writer.refresh(force: true);

    final readerDio = _FakeDio('should not be requested');
    final reader = PodcastCatalogService.withDio(
      dio: readerDio,
      resolveDir: () async => directory,
    );

    final snapshot = await reader.loadCachedCatalog();

    expect(snapshot?.podcasts.single.id, 'podcast-1');
    expect(reader.hasInitialized, isTrue);
    expect(readerDio.callCount, 0);
  });
}
