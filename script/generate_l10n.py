"""Validate ARB coverage/placeholders and generate the shared Dart lookup."""
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1] / 'crossplatform/packages/waytty_l10n'
sources = json.loads((root / 'source_messages.json').read_text())
messages = {}
missing = []
for locale in ('zh', 'en'):
    path = root / 'l10n' / f'waytty_{locale}.arb'
    resources = json.loads(path.read_text())
    output = {}
    for source in sources:
        key = 'm_' + hashlib.sha256(source.encode()).hexdigest()[:12]
        if key not in resources:
            chinese = bool(re.search('[\u3400-\u9fff]', source))
            if (locale == 'zh' and chinese) or (locale == 'en' and not chinese):
                resources[key] = source
            else:
                missing.append((locale, source))
                continue
        translated = resources[key]
        if sorted(re.findall(r'\{\d+\}', source)) != sorted(re.findall(r'\{\d+\}', translated)):
            raise ValueError(f'Placeholder mismatch ({locale}): {source!r} -> {translated!r}')
        output[source] = translated
    messages[locale] = output
    if '--check' not in sys.argv:
        path.write_text(json.dumps(resources, ensure_ascii=False, indent=2) + '\n')
if missing:
    for locale, text in missing:
        print(f'{locale}: {text}')
    raise SystemExit(f'{len(missing)} translations missing')
generated = ('// Generated from l10n/*.arb by script/generate_l10n.py.\n'
             'const wayttyMessages = <String, Map<String, String>>' +
             json.dumps(messages, ensure_ascii=False, indent=2).replace('$', r'\$') + ';\n')
destination = root / 'lib/src/messages.g.dart'
if '--check' in sys.argv:
    if destination.read_text() != generated:
        raise SystemExit('Generated translations are stale; run script/generate_l10n.py')
else:
    destination.write_text(generated)
print(f'{len(sources)} messages validated in Chinese and English.')
