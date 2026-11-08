#!/usr/bin/env python3
"""Sign with the original local identity; never fall back to an ad hoc signature."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys

config_path = Path.home() / 'Library/Application Support/StudySide/Signing/identity.json'
if len(sys.argv) != 2:
    raise SystemExit('Usage: sign-app.py /path/to/StudySide.app')
if not config_path.exists():
    raise SystemExit('Stable signing is not configured. Run python3 scripts/setup-signing.py once, then build again. Refusing an ad hoc build because it would reset macOS permissions.')
config = json.loads(config_path.read_text())
app = Path(sys.argv[1]).resolve()
with (app / 'Contents/Info.plist').open('rb') as stream:
    identifier = plistlib.load(stream)['CFBundleIdentifier']
if identifier != 'local.keban.study-assistant':
    raise SystemExit('Unexpected app identifier. Refusing to change the permission identity.')
requirement = 'identifier "local.keban.study-assistant" and certificate leaf = H"' + config['fingerprint'] + '"'
subprocess.run(['/usr/bin/codesign', '--force', '--sign', config['fingerprint'], '--keychain', config['keychain'], '--timestamp=none', str(app)], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '--test-requirement', '=' + requirement, str(app)], check=True)
print('Verified persistent certificate and unchanged app identifier.')
