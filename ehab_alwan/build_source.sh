#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
OUTPUT="$ROOT/ehab_dist"
APP="$OUTPUT/Ehab_Alwan_Sales_Source"
rm -rf "$OUTPUT"
mkdir -p "$APP" "$APP/lib" "$APP/test" "$APP/ehab_backend" "$APP/vib_overrides"
unzip -q "$ROOT/VIB-SALES-INDEPENDENT-SOURCE.zip" -d "$APP"
cp "$ROOT"/overrides/lib/*.dart "$APP/lib/"
cp "$ROOT/overrides/pubspec.yaml" "$APP/pubspec.yaml"
cp "$ROOT"/overrides/test/*.dart "$APP/test/"
cp "$ROOT"/overrides/assets/login-chime.wav "$APP/assets/login-chime.wav"
cp "$ROOT"/overrides/android/*.py "$APP/vib_overrides/"
cp -r "$ROOT/overrides/firebase/." "$APP/ehab_backend/"

# Client Firebase config inside original VIB source must NOT survive.
# The functions/rules templates are copied, not deployed.
python3 - "$APP/ehab_backend" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1])
for f in base.rglob('*'):
    if f.is_file() and f.suffix in ('.js','.cjs','.json','.md','.yaml','.yml'):
        try: data=f.read_text(encoding='utf-8')
        except UnicodeError: continue
        data=data.replace('vib-sales','ehab-alwan-sales')
        data=data.replace('VIB','EHAB ALWAN')
        f.write_text(data, encoding='utf-8')
PY

python3 "$ROOT/ehab_alwan/rebrand.py" "$APP"
(
 cd "$OUTPUT"
 zip -q -r Ehab_Alwan_Sales_Source.zip Ehab_Alwan_Sales_Source
)
echo "Created $OUTPUT/Ehab_Alwan_Sales_Source.zip"
