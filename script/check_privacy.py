#!/usr/bin/env python3
"""Scan publishable files; never print credential contents or upload reports."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def approved(finding, content, allowlist):
    lines = content.splitlines(keepends=True)
    excerpt = b"".join(lines[finding["StartLine"] - 1:finding["EndLine"]])
    for entry in allowlist:
        if entry["path"] != finding["File"] or entry["rule"] != finding["RuleID"]:
            continue
        value = content if entry["scope"] == "file" else excerpt
        if hashlib.sha256(value).hexdigest() == entry["sha256"]:
            return True
    return False


def scan(binary, kind, target, report, allowlist, historical=False):
    args = [binary, kind, str(target), "--redact=100", "--no-banner",
            "--report-format", "json", "--report-path", str(report)]
    if historical:
        args += ["--log-opts=--all"]
    result = subprocess.run(args, cwd=ROOT, capture_output=True)
    if result.returncode not in (0, 1) or not report.is_file():
        raise RuntimeError("Gitleaks could not complete the scan; publication is blocked")
    findings = json.loads(report.read_text())
    rejected = []
    for finding in findings:
        path = finding["File"]
        if not historical:
            path = str(Path(path).relative_to(target)) if Path(path).is_absolute() else path
            finding["File"] = path
            content = (target / path).read_bytes()
        else:
            content = git("show", f'{finding["Commit"]}:{path}')
        if not approved(finding, content, allowlist):
            rejected.append(finding)
    for finding in rejected:
        print(f'SECRET {finding["RuleID"]}: {finding["File"]}:{finding["StartLine"]}')
    print(f'{kind}: {len(findings)} detections, '
          f'{len(findings) - len(rejected)} exact reviewed fixtures, {len(rejected)} unresolved')
    return len(rejected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="also scan all reachable commits")
    args = parser.parse_args()
    binary = shutil.which(os.environ.get("WAYTTY_GITLEAKS", "gitleaks"))
    if not binary:
        raise RuntimeError("Install Gitleaks or set WAYTTY_GITLEAKS first")
    allowlist = json.loads((ROOT / "privacy-allowlist.json").read_text())["entries"]
    files = set(git("ls-files", "-co", "--exclude-standard", "-z").decode().split("\0")) - {""}
    problems = 0
    with tempfile.TemporaryDirectory(prefix="waytty-privacy-") as tmp:
        candidate = Path(tmp) / "source"
        candidate.mkdir()
        for name in sorted(files):
            source = ROOT / name
            if source.is_symlink():
                print(f'SYMLINK requires review: {name}')
                problems += 1
                continue
            if not source.is_file():
                continue
            data = source.read_bytes()
            for match in re.finditer(rb'/Users/([A-Za-z0-9._-]+)/', data):
                if match[1] not in (b'demo', b'user', b'example', b'runner'):
                    print(f'PERSONAL_PATH: {name}')
                    problems += 1
                    break
            if re.search(r'(^|/)(\.env(\..+)?|credentials\.json|hosts\.json|known_hosts|authorized_keys)$', name):
                if Path(name).name not in ('.env.example', '.env.sample'):
                    print(f'PRIVATE_DATA_FILE: {name}')
                    problems += 1
            if name.endswith(('.cast', '.db', '.sqlite', '.sqlite3', '.p12', '.pfx', '.jks', '.keystore', '.dylib')):
                print(f'PRIVATE_OR_BUILT_FILE: {name}')
                problems += 1
            destination = candidate / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        print(f'Candidate files: {len(files)}')
        problems += scan(binary, 'dir', candidate, Path(tmp) / 'source.json', allowlist)
        if args.history:
            problems += scan(binary, 'git', ROOT, Path(tmp) / 'history.json', allowlist, historical=True)
            identities = git('log', '--all', '--format=%ae%n%ce').decode().splitlines()
            personal = {value for value in identities if not value.endswith('@users.noreply.github.com')}
            if personal:
                print(f'AUTHOR_PRIVACY: {len(personal)} non-noreply email identities in history; '
                      'review before publishing (addresses not printed)')
                problems += 1
    print('Privacy check passed.' if not problems else f'Privacy check blocked: {problems} findings.')
    return 1 if problems else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        detail = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print(f'Privacy check did not complete: {detail}', file=sys.stderr)
        sys.exit(2)
