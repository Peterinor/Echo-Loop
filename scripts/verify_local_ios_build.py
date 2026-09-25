"""检查真实 iOS 产物的本地版配置，避免 CI 成功却构建了官方模式。"""

import base64
from pathlib import Path
import plistlib


def verify(app: Path, xcconfig: Path) -> None:
    """拒绝缺失可执行文件、错误构建模式或仍启用原生埋点的产物。"""
    settings = {}
    for line in xcconfig.read_text(encoding='utf-8').splitlines():
        key, separator, value = line.partition('=')
        if separator:
            settings[key.strip()] = value.strip()
    defines = {
        base64.b64decode(value, validate=True).decode('utf-8')
        for value in settings.get('DART_DEFINES', '').split(',') if value
    }
    if 'APP_EDITION=local' not in defines:
        raise ValueError('构建配置缺少 APP_EDITION=local')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('com.posthog.posthog.AUTO_INIT') is not False:
        raise ValueError('本地版原生 PostHog 自动初始化未关闭')
    if 'com.posthog.posthog.API_KEY' in info:
        raise ValueError('本地版仍包含原生 PostHog API_KEY')
    executable = app / info['CFBundleExecutable']
    if not executable.is_file() or executable.stat().st_size == 0:
        raise ValueError('iOS 可执行文件缺失或为空')


if __name__ == '__main__':
    verify(Path('build/ios/iphoneos/Runner.app'), Path('ios/Flutter/Generated.xcconfig'))
    print('iOS 本地版配置与构建产物检查通过')
