#!/usr/bin/env bash
#
# Populate assets/samples/ with piano note samples for AR Synth's "Piano"
# sound engine.
#
# The app ships with lightweight, CC0, self-generated samples produced by
# scripts/generate_samples.py (this is what is committed to the repo). This
# script lets you optionally replace them with real piano recordings.
#
# Naming convention the engine expects:
#     assets/samples/piano_<Note>.<ext>     e.g.  piano_C4.wav  /  piano_A3.mp3
# where <Note> is a note name like C4, C#3, Gb5. The engine loads every such
# file as an "anchor" and pitch-shifts the nearest one to reach other notes,
# so a few anchors across the range are enough.
#
# Usage:
#     ./scripts/fetch_samples.sh            # (default) regenerate CC0 samples
#     ./scripts/fetch_samples.sh --real     # try to download real recordings
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/assets/samples"
mkdir -p "$OUT_DIR"

mode="${1:-}"

if [[ "$mode" == "--real" ]]; then
  # Real acoustic piano notes from the open-source tonejs-instruments set
  # (Salamander Grand Piano, CC-BY 3.0 — please keep attribution if you ship
  # these). Served via the jsDelivr CDN mirror of the GitHub repo.
  BASE="https://cdn.jsdelivr.net/gh/nbrosowsky/tonejs-instruments@master/samples/piano"
  NOTES=(C2 C3 C4 C5 C6 A2 A3 A4 A5)
  ok=0
  for note in "${NOTES[@]}"; do
    url="$BASE/${note}.mp3"
    out="$OUT_DIR/piano_${note}.mp3"
    echo "Fetching $url"
    if curl -fsSL "$url" -o "$out"; then
      ok=$((ok + 1))
    else
      echo "  ! failed (skipping)"
      rm -f "$out"
    fi
  done
  if [[ "$ok" -gt 0 ]]; then
    echo "Downloaded $ok real sample(s) to assets/samples/."
    echo "NOTE: Salamander Grand Piano is CC-BY 3.0 — credit the author if you"
    echo "      distribute these files."
  else
    echo "No downloads succeeded (offline or CDN blocked)."
    echo "Falling back to the built-in CC0 generator..."
    python3 "$ROOT_DIR/scripts/generate_samples.py"
  fi
else
  # Default: deterministic, offline, CC0 samples.
  python3 "$ROOT_DIR/scripts/generate_samples.py"
fi

echo "Remember to run 'flutter pub get' if you added new asset files."
