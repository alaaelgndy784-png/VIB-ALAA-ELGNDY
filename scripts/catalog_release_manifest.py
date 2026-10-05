"""Produce an immutable update manifest with APK integrity and signing identity."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct


def certificate_digest(data):
    def length_prefixed(value):
        length = struct.unpack_from('<I', value)[0]
        return value[4:4 + length], value[4 + length:]
    eocd = data.rfind(b'PK\x05\x06')
    central = struct.unpack_from('<I', data, eocd + 16)[0]
    if data[central - 16:central] != b'APK Sig Block 42':
        raise ValueError('APK signing block missing')
    size = struct.unpack_from('<Q', data, central - 24)[0]
    entries = data[central - size:central - 24]
    while entries:
        length = struct.unpack_from('<Q', entries)[0]
        entry, entries = entries[8:8 + length], entries[8 + length:]
        if struct.unpack_from('<I', entry)[0] == 0x7109871a:
            signers, _ = length_prefixed(entry[4:])
            signer, _ = length_prefixed(signers)
            signed, _ = length_prefixed(signer)
            _, rest = length_prefixed(signed)
            certs, _ = length_prefixed(rest)
            cert, _ = length_prefixed(certs)
            return hashlib.sha256(cert).hexdigest()
    raise ValueError('APK v2 signature missing')


def main():
    config = Path('app/build.gradle.kts').read_text()
    code = int(re.search(r'versionCode = (\d+)', config).group(1))
    version = re.search(r'versionName = "([^"]+)"', config).group(1)
    tag = os.environ['CATALOG_RELEASE_TAG']
    apk = Path('VIB-CUSTOMER.apk').read_bytes()
    manifest = {
        'versionCode': code, 'versionName': version,
        'packageName': 'com.aistudio.sanitaryware.vibalaaelgndy',
        'apkUrl': 'https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/' + tag + '/VIB-CUSTOMER.apk',
        'sha256': hashlib.sha256(apk).hexdigest(),
        'signingSha256': certificate_digest(apk)
    }
    if certificate_digest(Path('VIB-ADMIN.apk').read_bytes()) != manifest['signingSha256']:
        raise ValueError('Admin and customer signing identities differ')
    Path('VIB-CATALOG-UPDATE.json').write_text(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
