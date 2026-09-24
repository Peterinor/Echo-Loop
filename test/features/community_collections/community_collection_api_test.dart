import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/features/community_collections/data/community_collection_api.dart';

class _ApiAdapter implements HttpClientAdapter {
  final int statusCode;

  _ApiAdapter({this.statusCode = 200});

  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final payload = switch (options.uri.path) {
      '/api/v2/collections' => {
        'items': [
          {
            'id': 'collection-1',
            'name': 'Community English',
            'description': null,
            'coverUrl': 'https://cdn.example/cover.jpg',
            'authorNickname': 'Echo Studio',
            'fileCount': 1,
            'publishedAt': '2026-09-22T00:00:00.000Z',
            'updatedAt': '2026-09-23T00:00:00.000Z',
          },
        ],
        'nextCursor': 'next-1',
      },
      '/api/v2/collections/collection-1' => {
        'collection': {
          'id': 'collection-1',
          'name': 'Community English',
          'description': 'Fresh description',
          'coverUrl': 'https://cdn.example/cover.jpg',
          'authorNickname': 'Echo Studio',
          'fileCount': 1,
          'publishedAt': '2026-09-22T00:00:00.000Z',
          'updatedAt': '2026-09-23T00:00:00.000Z',
        },
        'items': [
          {
            'id': 'file-1',
            'title': 'Lesson 1',
            'description': null,
            'mediaType': 'audio',
            'durationSec': 42,
            'fileSizeBytes': 1234,
            'difficulty': 'B1',
            'publishedAt': '2026-09-21T00:00:00.000Z',
            'sortOrder': 0,
            'mediaUrl': 'https://cdn.example/file.m4a',
          },
        ],
        'nextCursor': null,
      },
      '/api/v2/collections/collection-1/files/file-1' => {
        'file': {
          'id': 'file-1',
          'title': 'Lesson 1',
          'description': null,
          'mediaType': 'audio',
          'durationSec': 42,
          'fileSizeBytes': 1234,
          'difficulty': 'B1',
          'publishedAt': '2026-09-21T00:00:00.000Z',
          'sortOrder': 0,
          'mediaUrl': 'https://cdn.example/file.m4a',
        },
        'subtitle': {
          'sentences': [
            {'text': 'Hello.', 'startTime': 0.0, 'endTime': 1.25},
          ],
          'words': [
            {'word': 'Hello', 'startTime': 0.0, 'endTime': 0.8},
          ],
        },
      },
      _ => <String, Object?>{},
    };
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(jsonEncode(payload)))),
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'v2 client uses cursor-only pagination and parses collection catalog entry',
    () async {
      final adapter = _ApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = adapter;
      final api = CommunityCollectionApi.withDio(dio);

      final page = await api.getCollections(cursor: 'cursor-2');

      expect(page.items.single.id, 'collection-1');
      expect(page.items.single.fileCount, 1);
      expect(page.items.single.authorNickname, 'Echo Studio');
      expect(page.items.single.updatedAt, DateTime.utc(2026, 9, 23));
      expect(adapter.requests.single.queryParameters, {'cursor': 'cursor-2'});
      expect(
        adapter.requests.single.queryParameters.containsKey('page'),
        isFalse,
      );
    },
  );

  test(
    'v2 client parses file metadata and second-level subtitle timestamps',
    () async {
      final adapter = _ApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = adapter;
      final api = CommunityCollectionApi.withDio(dio);

      final detail = await api.getCollectionDetail('collection-1');
      final fileDetail = await api.getFileDetail('collection-1', 'file-1');

      expect(detail.collection.description, 'Fresh description');
      expect(detail.collection.updatedAt, DateTime.utc(2026, 9, 23));
      expect(detail.items.single.mediaType.name, 'audio');
      expect(detail.items.single.difficulty?.name, 'b1');
      expect(fileDetail.file.fileSizeBytes, 1234);
      expect(fileDetail.subtitle.sentences.single.endTime.inMilliseconds, 1250);
      expect(fileDetail.subtitle.words.single.word, 'Hello');
      expect(adapter.requests[0].uri.path, '/api/v2/collections/collection-1');
      expect(
        adapter.requests[1].uri.path,
        '/api/v2/collections/collection-1/files/file-1',
      );
    },
  );

  test(
    'v2 file detail keeps missing-file and missing-subtitle errors distinct',
    () async {
      final missingFileDio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = _ApiAdapter(statusCode: 404);
      final missingSubtitleDio = Dio(
        BaseOptions(baseUrl: 'https://api.example'),
      )..httpClientAdapter = _ApiAdapter(statusCode: 422);

      await expectLater(
        CommunityCollectionApi.withDio(
          missingFileDio,
        ).getFileDetail('collection-1', 'file-1'),
        throwsA(isA<CommunityFileNotFound>()),
      );
      await expectLater(
        CommunityCollectionApi.withDio(
          missingSubtitleDio,
        ).getFileDetail('collection-1', 'file-1'),
        throwsA(isA<CommunitySubtitleUnavailable>()),
      );
    },
  );
}
