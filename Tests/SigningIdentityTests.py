#!/usr/bin/env python3
"""Verify update identity with different executables, and reject ad hoc substitution."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
config_path = Path.home() / 'Library/Application Support/StudySide/Signing/identity.json'
if not config_path.exists():
    print('SKIP: stable-signing update checks require a configured local signing identity.')
    raise SystemExit(0)
config = json.loads(config_path.read_text())

def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, check=True, **kwargs)

def signature(app):
    result = run(['/usr/bin/codesign', '-d', '-r-', str(app)])
    text = result.stdout + result.stderr
    return next(line for line in text.splitlines() if line.startswith('designated => ')).removeprefix('designated => ')

def cdhash(app):
    text = run(['/usr/bin/codesign', '-d', '--verbose=4', str(app)]).stderr
    return re.search(r'^CDHash=(.+)$', text, re.MULTILINE).group(1)

with tempfile.TemporaryDirectory(prefix='studyside-update-check-') as folder:
    folder = Path(folder)
    builds = []
    for version in (1, 2):
        app = folder / f'Build{version}.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': 'local.keban.study-assistant', 'CFBundleExecutable': 'StudySide', 'CFBundleName': 'StudySide', 'CFBundleVersion': str(version)}, stream)
        source = folder / f'build{version}.c'
        source.write_text(f'int main(void) {{ return {version}; }}\n')
        run(['/usr/bin/clang', str(source), '-o', str(app / 'Contents/MacOS/StudySide')])
        run(['/usr/bin/python3', str(root / 'scripts/sign-app.py'), str(app)])
        builds.append(app)
    first, second = builds
    original_requirement = signature(first)
    assert signature(second) == original_requirement
    assert cdhash(first) != cdhash(second), 'Test builds must have different code hashes'
    assert 'certificate leaf' in original_requirement and 'cdhash' not in original_requirement
    run(['/usr/bin/codesign', '--verify', '--strict', '--test-requirement', '=' + original_requirement, str(second)])
    run(['/usr/bin/codesign', '--force', '--sign', '-', str(second)])
    rejected = subprocess.run(['/usr/bin/codesign', '--verify', '--test-requirement', '=' + original_requirement, str(second)], capture_output=True)
    assert rejected.returncode != 0, 'A different signer must not inherit the permission identity'
print('PASS: different executable updates retain the same certificate-based identity; ad hoc substitution is rejected')
