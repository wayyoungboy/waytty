import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


privacy = load('check_privacy')
site = load('build_site')


class PrivacyTests(unittest.TestCase):
    def test_modified_key_is_not_approved(self):
        original = b'public test fixture\n'
        entry = dict(path='fixture', rule='private-key', scope='file',
                     sha256=hashlib.sha256(original).hexdigest())
        finding = dict(File='fixture', RuleID='private-key', StartLine=1, EndLine=1)
        self.assertTrue(privacy.approved(finding, original, [entry]))
        self.assertFalse(privacy.approved(finding, original + b'new credential', [entry]))
        self.assertFalse(privacy.approved(dict(finding, File='elsewhere'), original, [entry]))

    def test_reviewed_translation_does_not_allow_other_credentials(self):
        original = b'display label\n'
        entry = dict(path='messages', rule='generic-api-key', scope='lines',
                     sha256=hashlib.sha256(original).hexdigest())
        finding = dict(File='messages', RuleID='generic-api-key', StartLine=2, EndLine=2)
        content = b'new credential\n' + original
        self.assertTrue(privacy.approved(finding, content, [entry]))
        self.assertFalse(privacy.approved(dict(finding, StartLine=1, EndLine=1), content, [entry]))
        self.assertFalse(privacy.approved(dict(finding, RuleID='private-key'), content, [entry]))

    def test_website_never_copies_unlisted_private_files(self):
        old_root, old_dest = site.ROOT, site.DEST
        try:
            with tempfile.TemporaryDirectory() as tmp:
                site.ROOT = Path(tmp)
                site.DEST = site.ROOT / 'dist/site'
                (site.ROOT / 'website').mkdir()
                (site.ROOT / 'docs/screenshots').mkdir(parents=True)
                for name in site.SITE_FILES:
                    (site.ROOT / 'website' / name).write_text('public')
                for name in site.SCREENSHOTS:
                    (site.ROOT / 'docs/screenshots' / name).write_bytes(b'public')
                (site.ROOT / 'website/credentials.json').write_text('private')
                site.DEST.mkdir(parents=True)
                (site.DEST / 'old-private.txt').write_text('private')
                site.build()
                self.assertFalse((site.DEST / 'credentials.json').exists())
                self.assertFalse((site.DEST / 'old-private.txt').exists())
                self.assertEqual(len([p for p in site.DEST.rglob('*') if p.is_file()]), 10)
        finally:
            site.ROOT, site.DEST = old_root, old_dest


if __name__ == '__main__':
    unittest.main()
