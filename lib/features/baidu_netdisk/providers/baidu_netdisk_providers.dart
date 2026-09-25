/// 百度网盘功能的基础 Provider。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/package_info_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../utils/transcript_picker.dart';
import '../data/baidu_credential_repository.dart';
import '../data/baidu_credential_store.dart';
import '../data/baidu_netdisk_api.dart';
import '../data/baidu_netdisk_import_service.dart';
import '../data/baidu_oauth_api.dart';
import '../services/baidu_oauth_launcher.dart';

/// 后端 OAuth API provider。
final baiduOAuthApiProvider = Provider<BaiduOAuthApi>((ref) {
  return createDefaultBaiduOAuthApi(appVersion: readAppVersion(ref));
});

/// 百度 credential secure storage provider。
final baiduCredentialStoreProvider = Provider<BaiduCredentialStore>((ref) {
  return SecureBaiduCredentialStore();
});

/// 百度 credential repository provider。
final baiduCredentialRepositoryProvider = Provider<BaiduCredentialRepository>((
  ref,
) {
  return DefaultBaiduCredentialRepository(
    api: ref.watch(baiduOAuthApiProvider),
    store: ref.watch(baiduCredentialStoreProvider),
  );
});

/// 百度 OAuth 浏览器启动器 provider。
final baiduOAuthLauncherProvider = Provider<BaiduOAuthLauncher>((ref) {
  return const UrlLauncherBaiduOAuthLauncher();
});

/// 百度网盘文件 API provider。
final baiduNetdiskApiProvider = Provider<BaiduNetdiskApi>((ref) {
  return DefaultBaiduNetdiskApi(
    backgroundDownloader: ref.watch(backgroundFileDownloadServiceProvider),
  );
});

/// 百度网盘音频导入服务 provider。
final baiduNetdiskImportServiceProvider = Provider<BaiduNetdiskImportService>((
  ref,
) {
  return DefaultBaiduNetdiskImportService(
    credentialRepository: ref.watch(baiduCredentialRepositoryProvider),
    api: ref.watch(baiduNetdiskApiProvider),
    subtitleImporter: (item, {required text, required ext}) =>
        importLocalSubtitleWithRef(ref, item, text: text, ext: ext),
  );
});
