import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('check_toolchain', ROOT/'scripts/check-toolchain.py')
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


class ToolchainTests(unittest.TestCase):
    def test_validated_swift_release_line_is_accepted(self):
        toolchain.validate('swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1)')
        toolchain.validate('Apple Swift version 6.4.1 (swiftlang-6.4.1)')

    def test_crashing_and_unvalidated_compilers_are_rejected(self):
        for version in ['6.3.3', '6.2', '6.5', '16.4']:
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'requires Swift 6.4.x'):
                toolchain.validate(f'Apple Swift version {version}')

    def test_unknown_version_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Cannot identify'):
            toolchain.validate('Compiler information unavailable')


if __name__ == '__main__':
    unittest.main()
