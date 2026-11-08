#!/usr/bin/env python3
"""Create a persistent local signing identity. Never stores private keys in this repository."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

base = Path.home() / 'Library/Application Support/StudySide/Signing'
base.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(base, 0o700)
config_file = base / 'identity.json'

def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout

if config_file.exists():
    config = json.loads(config_file.read_text())
    identities = run(['/usr/bin/security', 'find-identity', '-p', 'codesigning', config['keychain']])
    if config['fingerprint'] not in identities:
        raise SystemExit('The saved StudySide signing identity is missing. Restore its original keychain identity. Refusing to create a different identity because this would reset permissions.')
    print('StudySide signing identity is already configured.')
    raise SystemExit(0)

keychain = json.loads(run(['/usr/bin/security', 'default-keychain', '-d', 'user']).strip())
name = 'StudySide Local Signing ' + secrets.token_hex(8)
with tempfile.TemporaryDirectory(prefix='studyside-signing-') as folder:
    os.chmod(folder, 0o700)
    folder = Path(folder)
    key, cert, package, openssl_config = [folder / f for f in ('private.pem', 'certificate.pem', 'identity.p12', 'openssl.cnf')]
    openssl_config.write_text('''[req]
prompt = no
distinguished_name = dn
x509_extensions = signing
[dn]
CN = ''' + name + '''
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
''')
    run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256', '-days', '7300', '-config', str(openssl_config), '-keyout', str(key), '-out', str(cert)])
    os.chmod(key, 0o600)
    env = dict(os.environ, STUDYSIDE_TEMP_P12_PASSWORD=secrets.token_urlsafe(40))
    run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(key), '-in', str(cert), '-name', name, '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1', '-out', str(package), '-passout', 'env:STUDYSIDE_TEMP_P12_PASSWORD'], env=env)
    # Limit private-key access to the system codesign tool; do not grant all applications access.
    run(['/usr/bin/security', 'import', str(package), '-k', keychain, '-P', env['STUDYSIDE_TEMP_P12_PASSWORD'], '-x', '-T', '/usr/bin/codesign'])
    fingerprint = run(['/usr/bin/openssl', 'x509', '-in', str(cert), '-noout', '-fingerprint', '-sha1']).strip().split('=')[-1].replace(':', '')
    public_cert = base / 'certificate.pem'
    public_cert.write_bytes(cert.read_bytes())
    config = {'fingerprint': fingerprint, 'keychain': keychain, 'name': name}
    config_file.write_text(json.dumps(config, indent=2) + '\n')
    os.chmod(config_file, 0o600)
print('Created a persistent StudySide signing identity in your login keychain. No system certificate trust settings were changed.')
