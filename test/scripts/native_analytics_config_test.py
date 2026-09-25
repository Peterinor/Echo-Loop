"""验证原生埋点配置的模式切换及构建产物隔离。"""

import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

script = Path(__file__).resolve().parents[2] / 'scripts/configure_native_analytics.py'
spec = importlib.util.spec_from_file_location('native_analytics', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class NativeAnalyticsTest(unittest.TestCase):
    def test_local_then_official_restores_each_platform(self):
        for platform in ('ios', 'macos'):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                source = script.parents[1] / platform / 'Runner/Info.plist'
                original = plistlib.loads(source.read_bytes())
                target = Path(directory) / 'Info.plist'
                target.write_bytes(plistlib.dumps(original, fmt=plistlib.FMT_BINARY))
                defines = base64.b64encode(b'APP_EDITION=local').decode()
                module.configure(target, source, defines)
                local = plistlib.loads(target.read_bytes())
                self.assertNotIn('com.posthog.posthog.API_KEY', local)
                self.assertFalse(local['com.posthog.posthog.AUTO_INIT'])
                self.assertEqual(original['CFBundleIdentifier'], local['CFBundleIdentifier'])
                self.assertEqual(plistlib.loads(source.read_bytes()), original)
                module.configure(target, source, '')
                self.assertEqual(plistlib.loads(target.read_bytes()), original)


if __name__ == '__main__':
    unittest.main()
