"""覆盖 iOS 产物校验的重要失败路径，防止错误模式被作为本地版交付。"""

import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

script = Path(__file__).resolve().parents[2] / 'scripts/verify_local_ios_build.py'
spec = importlib.util.spec_from_file_location('local_ios_build', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LocalIosBuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / 'Runner.app'
        self.app.mkdir()
        self.config = Path(self.directory.name) / 'Generated.xcconfig'
        self.config.write_text('DART_DEFINES=' + base64.b64encode(b'APP_EDITION=local').decode())
        self.info = {'CFBundleExecutable': 'Runner', 'com.posthog.posthog.AUTO_INIT': False}
        (self.app / 'Runner').write_bytes(b'build-output')

    def verify(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        module.verify(self.app, self.config)

    def test_accepts_local_build(self):
        self.verify()

    def test_rejects_official_or_missing_edition(self):
        for value in ('APP_EDITION=official', 'OTHER=value'):
            with self.subTest(value=value):
                self.config.write_text('DART_DEFINES=' + base64.b64encode(value.encode()).decode())
                with self.assertRaisesRegex(ValueError, 'APP_EDITION=local'):
                    self.verify()

    def test_rejects_enabled_or_missing_analytics_flag(self):
        for value in (True, None):
            with self.subTest(value=value):
                self.info.pop('com.posthog.posthog.AUTO_INIT', None)
                if value is not None:
                    self.info['com.posthog.posthog.AUTO_INIT'] = value
                with self.assertRaisesRegex(ValueError, '自动初始化'):
                    self.verify()

    def test_rejects_remaining_analytics_key(self):
        self.info['com.posthog.posthog.API_KEY'] = 'test-key'
        with self.assertRaisesRegex(ValueError, 'API_KEY'):
            self.verify()

    def test_rejects_missing_or_empty_executable(self):
        (self.app / 'Runner').write_bytes(b'')
        with self.assertRaisesRegex(ValueError, '可执行文件'):
            self.verify()
        (self.app / 'Runner').unlink()
        with self.assertRaisesRegex(ValueError, '可执行文件'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
