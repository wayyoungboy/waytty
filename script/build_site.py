#!/usr/bin/env python3
"""Build a Pages artifact from an explicit public-file allowlist."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'dist' / 'site'
SITE_FILES = ('index.html', 'style.css', 'app.js', 'favicon.svg')
SCREENSHOTS = ('connections-zh.png', 'connections-en.png', 'serial-zh.png',
               'workspace-demo.png')


def build():
    if DEST.is_symlink() or DEST.parent.is_symlink():
        raise RuntimeError('Site output must not be a symlink')
    if DEST.exists():
        shutil.rmtree(DEST)
    (DEST / 'assets').mkdir(parents=True)
    for name in SITE_FILES:
        shutil.copyfile(ROOT / 'website' / name, DEST / name)
    for name in SCREENSHOTS:
        shutil.copyfile(ROOT / 'docs' / 'screenshots' / name, DEST / 'assets' / name)
    (DEST / '.nojekyll').touch()
    print(f'Site built: {len(SITE_FILES) + len(SCREENSHOTS) + 1} public files in dist/site')


if __name__ == '__main__':
    build()
