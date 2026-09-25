import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../analytics/geo_interceptor.dart';
import '../../../config/api_config.dart';
import '../../../providers/package_info_provider.dart';
import '../../../services/backend_dio.dart';
import '../models/community_collection_models.dart';

part 'community_collection_api.g.dart';

/// v2 社区合集字幕不可用时的领域错误。
class CommunitySubtitleUnavailable implements Exception {
  final String fileId;

  const CommunitySubtitleUnavailable(this.fileId);

  @override
  String toString() => 'CommunitySubtitleUnavailable($fileId)';
}

/// 社区合集 v2 匿名只读 API 客户端。
class CommunityCollectionApi {
  final Dio _dio;

  CommunityCollectionApi({required String baseUrl, String? appVersion})
    : _dio = createBackendDio(
        baseUrl: baseUrl,
        allowAnonymousResources: true,
        appVersion: appVersion,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        apiLogTag: 'COMMUNITY-COLLECTION',
      ) {
    SharedPreferences.getInstance().then(
      (prefs) => _dio.interceptors.add(GeoInterceptor(prefs)),
    );
  }

  /// 测试用构造，允许注入 Dio。
  CommunityCollectionApi.withDio(this._dio);

  /// 获取公开社区合集，固定由服务端按 20 条分页。
  Future<PublicCollectionPage> getCollections({
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v2/collections',
      queryParameters: _cursorParameters(cursor),
      cancelToken: cancelToken,
    );
    return _parsePage(response.data);
  }

  /// 从合集详情读取分页文件；线上 v2 没有独立的 `/files` 列表端点。
  Future<CommunityCollectionFilesPage> getCollectionFiles(
    String collectionId, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v2/collections/${Uri.encodeComponent(collectionId)}',
      queryParameters: _cursorParameters(cursor),
      cancelToken: cancelToken,
    );
    final data = _responseObject(response.data);
    final items = _list(data, 'items')
        .map(_object)
        .map(CommunityCollectionFile.fromJson)
        .toList(growable: false);
    return CommunityCollectionFilesPage(
      items: items,
      nextCursor: _nullableString(data, 'nextCursor'),
    );
  }

  /// 从文件详情的 subtitle 字段读取字幕，保留现有下载层使用的 DTO。
  Future<CommunitySubtitle> getSubtitle(
    String collectionId,
    String fileId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v2/collections/${Uri.encodeComponent(collectionId)}/files/${Uri.encodeComponent(fileId)}',
        cancelToken: cancelToken,
      );
      final data = _responseObject(response.data);
      return CommunitySubtitle.fromJson({
        ..._object(data['subtitle']),
        'fileId': fileId,
      });
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 ||
          error.response?.statusCode == 422) {
        throw CommunitySubtitleUnavailable(fileId);
      }
      rethrow;
    }
  }

  Map<String, String>? _cursorParameters(String? cursor) {
    final value = cursor?.trim();
    return value == null || value.isEmpty ? null : {'cursor': value};
  }

  PublicCollectionPage _parsePage(Map<String, dynamic>? raw) {
    final data = _responseObject(raw);
    final items = _list(data, 'items')
        .map(_object)
        .map(PublicCollectionSummary.fromJson)
        .toList(growable: false);
    return PublicCollectionPage(
      items: items,
      nextCursor: _nullableString(data, 'nextCursor'),
    );
  }
}

Map<String, Object?> _responseObject(Map<String, dynamic>? value) {
  if (value == null) throw const FormatException('Empty API response');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) return value;
  throw FormatException('Missing or invalid $key');
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map<String, dynamic>) return Map<String, Object?>.from(value);
  throw const FormatException('Expected JSON object');
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Invalid $key');
}

@Riverpod(keepAlive: true)
CommunityCollectionApi communityCollectionApi(Ref ref) {
  return CommunityCollectionApi(
    baseUrl: resourceApiBaseUrl,
    appVersion: readAppVersion(ref),
  );
}
