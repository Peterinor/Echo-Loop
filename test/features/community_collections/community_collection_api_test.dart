import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/features/community_collections/data/community_collection_api.dart';

class _ApiAdapter implements HttpClientAdapter {
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
            'fileCount': 1,
            'publishedAt': '2026-09-22T00:00:00.000Z',
          },
        ],
        'nextCursor': 'next-1',
      },
      '/api/v2/collections/collection-1/files' => {
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
      '/api/v2/collections/collection-1/files/file-1/subtitle' => {
        'fileId': 'file-1',
        'sentences': [
          {'text': 'Hello.', 'startTime': 0.0, 'endTime': 1.25},
        ],
        'words': [
          {'word': 'Hello', 'startTime': 0.0, 'endTime': 0.8},
        ],
      },
      _ => <String, Object?>{},
    };
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(jsonEncode(payload)))),
      200,
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
    'v2 client uses cursor-only pagination and parses collection summary',
    () async {
      final adapter = _ApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = adapter;
      final api = CommunityCollectionApi.withDio(dio);

      final page = await api.getCollections(cursor: 'cursor-2');

      expect(page.items.single.id, 'collection-1');
      expect(page.items.single.fileCount, 1);
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

      final files = await api.getCollectionFiles('collection-1');
      final subtitle = await api.getSubtitle('collection-1', 'file-1');

      expect(files.items.single.mediaType.name, 'audio');
      expect(files.items.single.difficulty?.name, 'b1');
      expect(subtitle.fileId, 'file-1');
      expect(subtitle.sentences.single.endTime.inMilliseconds, 1250);
      expect(subtitle.words.single.word, 'Hello');
    },
  );
}
