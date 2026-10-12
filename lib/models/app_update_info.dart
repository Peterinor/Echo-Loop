/// App 版本更新信息模型
///
/// 包含远程版本信息的数据模型和更新状态的 sealed class 定义。
library;

/// 远程版本信息
class AppUpdateInfo {
  /// 最新可用版本
  final String latestVersion;

  /// 最低兼容版本（低于此版本强制更新）
  final String minimumVersion;

  /// 更新说明（locale -> text）
  final Map<String, String> releaseNotes;

  /// 下载链接（platform -> url）
  final Map<String, String> downloadUrl;

  /// v2 平台/渠道配置，缺失时使用顶层字段兜底
  final AppUpdatePlatforms platforms;

  /// 当前检查结果对应的更新渠道
  final AppUpdateChannel channel;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.minimumVersion,
    this.releaseNotes = const {},
    this.downloadUrl = const {},
    this.platforms = const AppUpdatePlatforms(),
    this.channel = AppUpdateChannel.generic,
  });

  /// 从 JSON 解析
  ///
  /// [latestVersion] 和 [minimumVersion] 为必填字段，缺失或非 String 时抛 [FormatException]。
  /// [releaseNotes] 和 [downloadUrl] 缺失时降级为空 Map。
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final latestVersion = json['latestVersion'];
    final minimumVersion = json['minimumVersion'];

    if (latestVersion is! String || latestVersion.isEmpty) {
      throw const FormatException(
        'latestVersion is required and must be a non-empty string',
      );
    }
    if (minimumVersion is! String || minimumVersion.isEmpty) {
      throw const FormatException(
        'minimumVersion is required and must be a non-empty string',
      );
    }

    return AppUpdateInfo(
      latestVersion: latestVersion,
      minimumVersion: minimumVersion,
      releaseNotes: _parseStringMap(json['releaseNotes']),
      downloadUrl: _parseStringMap(json['downloadUrl']),
      platforms: AppUpdatePlatforms.fromJson(json['platforms']),
    );
  }

  static Map<String, String> _parseStringMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(key.toString(), val?.toString() ?? ''),
    );
  }
}

/// 更新渠道
enum AppUpdateChannel {
  /// 未区分平台/渠道的旧版配置
  generic,

  /// iOS App Store
  iosAppStore,

  /// Android Google Play
  androidGooglePlay,

  /// Android 官网/GitHub APK
  androidApk,
}

/// v2 平台配置
class AppUpdatePlatforms {
  final IosUpdateConfig ios;
  final AndroidUpdateConfig android;

  const AppUpdatePlatforms({
    this.ios = const IosUpdateConfig(),
    this.android = const AndroidUpdateConfig(),
  });

  factory AppUpdatePlatforms.fromJson(dynamic value) {
    if (value is! Map) return const AppUpdatePlatforms();
    return AppUpdatePlatforms(
      ios: IosUpdateConfig.fromJson(value['ios']),
      android: AndroidUpdateConfig.fromJson(value['android']),
    );
  }
}

/// iOS App Store 更新配置
class IosUpdateConfig {
  final String? minimumVersion;

  const IosUpdateConfig({this.minimumVersion});

  factory IosUpdateConfig.fromJson(dynamic value) {
    if (value is! Map) return const IosUpdateConfig();
    return IosUpdateConfig(
      minimumVersion: _stringOrNull(value['minimumVersion']),
    );
  }
}

/// Android 更新配置
class AndroidUpdateConfig {
  final AndroidGooglePlayUpdateConfig googlePlay;
  final AndroidApkUpdateConfig apk;

  const AndroidUpdateConfig({
    this.googlePlay = const AndroidGooglePlayUpdateConfig(),
    this.apk = const AndroidApkUpdateConfig(),
  });

  factory AndroidUpdateConfig.fromJson(dynamic value) {
    if (value is! Map) return const AndroidUpdateConfig();
    return AndroidUpdateConfig(
      googlePlay: AndroidGooglePlayUpdateConfig.fromJson(value['googlePlay']),
      apk: AndroidApkUpdateConfig.fromJson(value['apk']),
    );
  }
}

/// Google Play 更新配置
class AndroidGooglePlayUpdateConfig {
  final String? minimumVersion;
  final String? storeUrl;
  final String? fallbackUrl;

  const AndroidGooglePlayUpdateConfig({
    this.minimumVersion,
    this.storeUrl,
    this.fallbackUrl,
  });

  factory AndroidGooglePlayUpdateConfig.fromJson(dynamic value) {
    if (value is! Map) return const AndroidGooglePlayUpdateConfig();
    return AndroidGooglePlayUpdateConfig(
      minimumVersion: _stringOrNull(value['minimumVersion']),
      storeUrl: _stringOrNull(value['storeUrl']),
      fallbackUrl: _stringOrNull(value['fallbackUrl']),
    );
  }
}

/// Android APK 更新配置
class AndroidApkUpdateConfig {
  final String? latestVersion;
  final String? minimumVersion;
  final String? downloadUrl;

  /// 中国区 APK 下载地址；未配置或确认文件缺失时回退到 [downloadUrl]。
  final String? downloadUrlChina;

  const AndroidApkUpdateConfig({
    this.latestVersion,
    this.minimumVersion,
    this.downloadUrl,
    this.downloadUrlChina,
  });

  factory AndroidApkUpdateConfig.fromJson(dynamic value) {
    if (value is! Map) return const AndroidApkUpdateConfig();
    return AndroidApkUpdateConfig(
      latestVersion: _stringOrNull(value['latestVersion']),
      minimumVersion: _stringOrNull(value['minimumVersion']),
      downloadUrl: _stringOrNull(value['downloadUrl']),
      downloadUrlChina: _stringOrNull(value['downloadUrlChina']),
    );
  }
}

String? _stringOrNull(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}

/// 更新类型
enum AppUpdateType {
  /// 无需更新
  none,

  /// 可选更新（可跳过）
  softUpdate,

  /// 强制更新（阻断）
  forceUpdate,
}

/// 更新状态
sealed class AppUpdateState {
  const AppUpdateState();
}

/// 初始状态
class AppUpdateInitial extends AppUpdateState {
  const AppUpdateInitial();
}

/// 检查中
class AppUpdateChecking extends AppUpdateState {
  const AppUpdateChecking();
}

/// 检查结果
class AppUpdateResult extends AppUpdateState {
  final AppUpdateType type;
  final AppUpdateInfo? info;

  const AppUpdateResult({required this.type, this.info});
}

/// 用户已忽略
class AppUpdateDismissed extends AppUpdateState {
  const AppUpdateDismissed();
}
