#!/usr/bin/env python3
"""Create a compact 0.45-second Android notification chime for manager approvals.

This is intentionally NOT a phone ringtone. It is only played by the approval
notifications channel, and is fully synthesized using Python's stdlib.
"""
from pathlib import Path
import math
import struct
import wave

RATE = 24000
DURATION = 0.45
SAMPLES = round(RATE * DURATION)
TARGET = Path("android/app/src/main/res/raw/vib_approval_message_short.wav")


def sample(t: float) -> int:
    # Soft two-note message-style ping; mild fade in, clear short fade out.
    attack = min(t / 0.014, 1.0)
    release = max(0.0, min((DURATION - t) / 0.18, 1.0))
    env = attack * release * release
    tone = 0.64 * math.sin(2.0 * math.pi * 880 * t)
    tone += 0.25 * math.sin(2.0 * math.pi * 1320 * t)
    tone += 0.11 * math.sin(2.0 * math.pi * 1760 * t)
    return int(14500 * env * tone)


def main() -> None:
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(TARGET), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(
            struct.pack("<h", sample(i / RATE)) for i in range(SAMPLES)
        ))
    assert TARGET.stat().st_size > 20000
    print(f"Short manager approval notification sound: {TARGET}")


if __name__ == "__main__":
    main()
