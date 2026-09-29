import 'package:flutter_test/flutter_test.dart';
import 'package:echo_loop/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo.fromJson', () {
    test('解析完整 JSON', () {
      final json = {
        'latestVersion': '1.1.0',
        'minimumVersion': '1.0.0',
        'releaseNotes': {'en': 'Bug fixes', 'zh': '修复了 bug'},
        'downloadUrl': {
          'ios': 'https://testflight.apple.com/join/XXXX',
          'fallback': 'https://example.com/download',
        },
      };
      final info = AppUpdateInfo.fromJson(json);

      expect(info.latestVersion, '1.1.0');
      expect(info.minimumVersion, '1.0.0');
      expect(info.releaseNotes['en'], 'Bug fixes');
      expect(info.releaseNotes['zh'], '修复了 bug');
      expect(info.downloadUrl['ios'], 'https://testflight.apple.com/join/XXXX');
    });

    test('releaseNotes 缺失时降级为空 Map', () {
      final json = {'latestVersion': '1.1.0', 'minimumVersion': '1.0.0'};
      final info = AppUpdateInfo.fromJson(json);

      expect(info.releaseNotes, isEmpty);
      expect(info.downloadUrl, isEmpty);
    });

    test('latestVersion 缺失时抛 FormatException', () {
      final json = {'minimumVersion': '1.0.0'};
      expect(() => AppUpdateInfo.fromJson(json), throwsFormatException);
    });

    test('minimumVersion 缺失时抛 FormatException', () {
      final json = {'latestVersion': '1.1.0'};
      expect(() => AppUpdateInfo.fromJson(json), throwsFormatException);
    });

    test('latestVersion 为空字符串时抛 FormatException', () {
      final json = {'latestVersion': '', 'minimumVersion': '1.0.0'};
      expect(() => AppUpdateInfo.fromJson(json), throwsFormatException);
    });

    test('latestVersion 为非 String 时抛 FormatException', () {
      final json = {'latestVersion': 123, 'minimumVersion': '1.0.0'};
      expect(() => AppUpdateInfo.fromJson(json), throwsFormatException);
    });

    test('releaseNotes 非 Map 类型时降级为空 Map', () {
      final json = {
        'latestVersion': '1.1.0',
        'minimumVersion': '1.0.0',
        'releaseNotes': 'not a map',
      };
      final info = AppUpdateInfo.fromJson(json);
      expect(info.releaseNotes, isEmpty);
    });

    test('解析 v2 platforms 渠道配置且保持旧字段兼容', () {
      final json = {
        'schemaVersion': 2,
        'latestVersion': '1.1.0',
        'minimumVersion': '1.0.0',
        'downloadUrl': {'androidApk': 'https://cdn.example.com/app.apk'},
        'platforms': {
          'ios': {'minimumVersion': '1.0.1'},
          'android': {
            'googlePlay': {
              'minimumVersion': '1.0.2',
              'storeUrl': 'market://details?id=app.echoloop',
              'fallbackUrl': 'https://play.google.com/store/apps/details',
            },
            'apk': {
              'latestVersion': '1.1.1',
              'minimumVersion': '1.0.3',
              'downloadUrl': 'https://cdn.example.com/app-1.1.1.apk',
            },
          },
        },
      };

      final info = AppUpdateInfo.fromJson(json);

      expect(info.latestVersion, '1.1.0');
      expect(info.minimumVersion, '1.0.0');
      expect(info.platforms.ios.minimumVersion, '1.0.1');
      expect(info.platforms.android.googlePlay.minimumVersion, '1.0.2');
      expect(
        info.platforms.android.googlePlay.storeUrl,
        'market://details?id=app.echoloop',
      );
      expect(info.platforms.android.apk.latestVersion, '1.1.1');
      expect(info.platforms.android.apk.minimumVersion, '1.0.3');
      expect(
        info.platforms.android.apk.downloadUrl,
        'https://cdn.example.com/app-1.1.1.apk',
      );
    });
  });
}
