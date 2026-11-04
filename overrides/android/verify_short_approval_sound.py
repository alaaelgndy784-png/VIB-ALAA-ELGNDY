#!/usr/bin/env python3
"""Fail the manager APK release if the short approval message sound was stripped."""
from pathlib import Path
import sys
import zipfile


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_short_approval_sound.py <manager.apk>")
    apk = Path(sys.argv[1])
    if not apk.is_file():
        raise SystemExit(f"Manager APK not found: {apk}")
    found = []
    with zipfile.ZipFile(apk) as archive:
        if "AndroidManifest.xml" not in archive.namelist():
            raise SystemExit("Missing AndroidManifest.xml")
        for item in archive.infolist():
            if not item.filename.startswith("res/") or not (20000 <= item.file_size <= 80000):
                continue
            content = archive.read(item)
            if content[:4] == b"RIFF" and content[8:12] == b"WAVE":
                found.append(item.filename)
    if not found:
        raise SystemExit("Manager APK is missing its short approval notification WAV resource")
    print("Confirmed embedded manager approval sound:", ", ".join(found))


if __name__ == "__main__":
    main()
