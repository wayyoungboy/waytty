#!/usr/bin/env python3
"""Validate only the built website, including project-subpath-safe assets."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import sys

ROOT = Path(__file__).resolve().parents[1] / 'dist' / 'site'


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []
        self.errors = []

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs:
            if attrs['id'] in self.ids:
                self.errors.append('duplicate id')
            self.ids.add(attrs['id'])
        for field in ('href', 'src'):
            if attrs.get(field):
                self.links.append(attrs[field])
        # Empty alt is intentional for decorative images beside a wordmark.
        if tag == 'img' and 'alt' not in attrs:
            self.errors.append('image missing alt text')
        if tag == 'script' and not attrs.get('src'):
            self.errors.append('inline script is not allowed')


def main():
    page = Page()
    page.feed((ROOT / 'index.html').read_text())
    for link in page.links:
        parsed = urlsplit(link)
        if parsed.scheme:
            if parsed.scheme != 'https' or parsed.hostname != 'github.com':
                page.errors.append('unexpected external link or resource')
        elif parsed.path:
            path = ROOT / unquote(parsed.path)
            if parsed.path.startswith('/') or ROOT not in path.resolve().parents or not path.is_file():
                page.errors.append(f'missing or nonportable resource: {parsed.path}')
        elif parsed.fragment and parsed.fragment not in page.ids:
            page.errors.append(f'missing section: {parsed.fragment}')
    for path in ROOT.rglob('*'):
        if path.is_file() and path.suffix not in ('.html', '.css', '.js', '.svg', '.png') and path.name != '.nojekyll':
            page.errors.append(f'unexpected artifact: {path.name}')
    for error in page.errors:
        print(error)
    print(f'Website: {len(page.links)} links/resources checked, {len(page.errors)} errors')
    return bool(page.errors)


if __name__ == '__main__':
    sys.exit(main())
