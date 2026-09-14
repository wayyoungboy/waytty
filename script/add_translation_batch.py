"""Author ARB translations against the frozen extraction inventory."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / 'crossplatform/packages/waytty_l10n'
locale = sys.argv[1]
order = json.loads((root / 'translation_order.json').read_text())
sources = json.loads((root / 'source_messages.json').read_text())
path = root / 'l10n' / f'waytty_{locale}.arb'
path.parent.mkdir(parents=True, exist_ok=True)
result = json.loads(path.read_text()) if path.exists() else {'@@locale': 'zh_CN' if locale == 'zh' else 'en'}
for key, translation in json.load(sys.stdin).items():
    source = order[int(key)] if key.isdigit() else key
    sources.setdefault(source, ['manual'])
    message_id = 'm_' + hashlib.sha256(source.encode()).hexdigest()[:12]
    result[message_id] = source if translation is None else translation
(root / 'source_messages.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2) + '\n')
path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
