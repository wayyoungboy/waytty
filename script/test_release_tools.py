import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import assemble_release


class BundleVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name) / "waytty.app"
        self.bundle.mkdir()

    def test_rejects_link_to_file_outside_bundle(self):
        external = self.bundle.parent / "outside"
        external.write_text("not distributable")
        (self.bundle / "escape").symlink_to(external)
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            assemble_release.verify_bundle(self.bundle)

    def test_rejects_personal_build_paths_in_binary_bytes(self):
        (self.bundle / "binary").write_bytes(b"\x00/Users/" + b"private-owner/build\x00")
        with self.assertRaisesRegex(ValueError, "Personal build path"):
            assemble_release.verify_bundle(self.bundle)

    def test_requires_both_architectures(self):
        with patch.object(assemble_release, "run", return_value="arm64"):
            with self.assertRaisesRegex(ValueError, "Not a Universal binary"):
                assemble_release.verify_bundle(self.bundle)

    def test_accepts_internal_links_and_both_architectures(self):
        (self.bundle / "binary").write_bytes(b"\x00/Users/runner/work\x00")
        (self.bundle / "link").symlink_to("binary")
        with patch.object(assemble_release, "run", return_value="arm64 x86_64") as run:
            assemble_release.verify_bundle(self.bundle)
        self.assertEqual(run.call_count, 3)


if __name__ == "__main__":
    unittest.main()
