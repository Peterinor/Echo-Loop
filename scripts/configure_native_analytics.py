"""在 Apple 构建产物中关闭本地版原生埋点，不修改源码 plist 或写入 Dart 凭据。"""

import base64
import os
from pathlib import Path
import plistlib
import sys


def configure(target: Path, source: Path, defines: str) -> None:
    values = [base64.b64decode(item, validate=True).decode() for item in defines.split(',') if item]
    data = target.read_bytes()
    result = plistlib.loads(data)
    original = plistlib.loads(source.read_bytes())
    # 官方构建从源码恢复，防止增量构建沿用上一次本地版的禁用状态。
    for key in ('com.posthog.posthog.API_KEY', 'com.posthog.posthog.AUTO_INIT'):
        result.pop(key, None)
        if key in original:
            result[key] = original[key]
    if 'APP_EDITION=local' in values:
        result.pop('com.posthog.posthog.API_KEY', None)
        result['com.posthog.posthog.AUTO_INIT'] = False
    fmt = plistlib.FMT_BINARY if data.startswith(b'bplist') else plistlib.FMT_XML
    target.write_bytes(plistlib.dumps(result, fmt=fmt, sort_keys=False))


if __name__ == '__main__':
    configure(Path(sys.argv[1]), Path(sys.argv[2]), os.environ.get('DART_DEFINES', ''))
