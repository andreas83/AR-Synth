#!/usr/bin/env python3
"""Generate simple, CC0 piano-ish anchor samples for AR Synth.

These are synthesized with the Python standard library only (no third-party
deps) so they always build, work fully offline, and carry no licensing strings
attached. The audio engine pitch-shifts the nearest anchor to reach every note,
so a handful of anchors across the range is enough.

Usage:
    python3 scripts/generate_samples.py

Output: assets/samples/piano_<Note>.wav  (16-bit mono, 44.1 kHz)

Prefer real recordings? See scripts/fetch_samples.sh.
"""
import math
import os
import struct
import wave

SAMPLE_RATE = 44100
DURATION = 2.2  # seconds
# Anchor notes (name -> MIDI). One per octave keeps pitch-shift artifacts small.
ANCHORS = {
    "C2": 36,
    "C3": 48,
    "C4": 60,
    "C5": 72,
    "C6": 84,
}
# Relative amplitudes of the first N harmonics — a mellow, piano-like spectrum.
HARMONICS = [1.0, 0.55, 0.42, 0.28, 0.16, 0.11, 0.07, 0.045, 0.03]

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "samples")


def midi_to_freq(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def render(midi: int) -> bytes:
    freq = midi_to_freq(midi)
    n = int(SAMPLE_RATE * DURATION)
    # Higher notes decay faster, like a real piano.
    decay_tau = 1.6 * (440.0 / freq) ** 0.4
    attack = int(0.005 * SAMPLE_RATE)  # 5 ms

    frames = bytearray()
    peak = 0.0
    raw = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t / decay_tau)
        if i < attack:
            env *= i / attack
        sample = 0.0
        for h, amp in enumerate(HARMONICS, start=1):
            # Slight inharmonicity gives a subtle metallic shimmer.
            partial = freq * h * (1.0 + 0.0004 * h * h)
            if partial > SAMPLE_RATE / 2:
                break
            sample += amp * math.sin(2.0 * math.pi * partial * t)
        val = env * sample
        raw[i] = val
        peak = max(peak, abs(val))

    norm = 0.89 / peak if peak > 0 else 0.0
    for val in raw:
        s = int(max(-1.0, min(1.0, val * norm)) * 32767)
        frames += struct.pack("<h", s)
    return bytes(frames)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, midi in ANCHORS.items():
        path = os.path.join(OUT_DIR, f"piano_{name}.wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(render(midi))
        print(f"wrote {os.path.relpath(path)}")
    print(f"Done: {len(ANCHORS)} sample(s) in {os.path.relpath(OUT_DIR)}")


if __name__ == "__main__":
    main()
