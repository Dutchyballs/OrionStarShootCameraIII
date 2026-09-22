"""Check repository-local Markdown links without depending on network access."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
errors = []
for source in root.rglob('*.md'):
    if '.git' in source.parts:
        continue
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', source.read_text(encoding='utf-8')):
        target = target.strip().strip('<>')
        parsed = urlsplit(target)
        if parsed.scheme or target.startswith('#'):
            continue
        path = source.parent / unquote(parsed.path)
        if parsed.path and not path.exists():
            errors.append(f'{source.relative_to(root)}: missing {target}')
if errors:
    raise SystemExit('\n'.join(errors))
print('Repository-local documentation links: OK')
