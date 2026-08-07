# AR Synth 🎹👋

[![Build APK](https://github.com/andreas83/AR-Synth/actions/workflows/build-apk.yml/badge.svg)](https://github.com/andreas83/AR-Synth/actions/workflows/build-apk.yml)

Play a virtual piano and synthesizer **in the air** — a Flutter app that tracks
your hands through the camera (MediaPipe Hand Landmarker) and turns your
gestures into music.

> **Platform:** Android-first. The camera hand-tracking runs on Android (native
> MediaPipe via JNI); on other platforms gesture mode shows a friendly
> "Android only" notice. The screen is kept awake while playing, and the app
> runs in portrait.

---

## Features

- **Camera hand-gesture instrument** with three selectable modes:
  - **Air Piano** — fingertips hover over the keyboard; push a finger down past
    the on-screen "press line" to play the key beneath it.
  - **Hand Poses** — hold a recognised pose (fist, point, peace, open hand,
    thumbs up); each fires a note or chord.
  - **Theremin** — one hand's height sweeps pitch (quantized to a scale of your
    choice), the other hand's height controls volume.
- **Two switchable sound engines:**
  - **Synth** — real-time oscillators (sine / square / saw / triangle) with a
    full **ADSR** envelope and **reverb / echo** effects (via `flutter_soloud`).
  - **Piano** — pitch-shifted piano **samples** (bundled; see below).
- **Expressive & creative controls:**
  - **Velocity from tap speed** — in Air Piano, how fast you jab a finger down
    sets the note's loudness (toggle in *Performance*).
  - **Resonant low-pass filter + LFO** — sweepable cutoff & resonance, with an
    optional LFO that auto-sweeps the cutoff.
  - **Pinch → cutoff** — your *free* hand's pinch distance modulates the filter
    live (a hands-in-the-air "wah").
  - **Scale lock** — Air-Piano lanes snap to any scale + key so you're always in
    tune (the default, C Major, matches the classic white-key layout).
  - **Arpeggiator** — held chords/poses spread into a rhythmic sequence
    (up / down / up-down / random, tempo & rate, gate).
  - **Reactive light visualizer** — notes bloom as pitch-colored ripples over
    the camera feed ("play the air, hear the light").
- **Synth controls in-context** — a drag-up **bottom sheet** on the gesture
  screen exposes engine, waveform, ADSR, effects, filter/LFO, scale, arpeggiator,
  octave and visuals without leaving the camera; a keyboard strip highlights the
  notes you're playing.
- **Live, persisted settings** — engine, waveform, ADSR, octave shift, effects,
  filter/LFO, velocity, scale + key, arpeggiator, visualizer, gesture mode &
  sensitivity, keyboard range, theremin scale.

## Tech stack

| Concern              | Package            |
| -------------------- | ------------------ |
| Audio (synth+sample) | `flutter_soloud`   |
| Camera stream        | `camera`           |
| Hand landmarks       | `hand_landmarker`  |
| Permissions          | `permission_handler` |
| State                | `provider`         |
| Persistence          | `shared_preferences` |

## Project layout

```
lib/
  main.dart                 # bootstraps audio + providers
  theme.dart
  models/                   # Note/music, SynthSettings, hand data structs
  services/
    audio_engine.dart       # SoLoud wrapper: synth voices, samples, ADSR, FX
    hand_tracking_service.dart  # camera + MediaPipe -> normalized HandFrame stream
    gesture_mapper.dart     # HandFrame -> notes, one strategy per gesture mode
  state/
    settings_controller.dart
    piano_controller.dart   # routes touch + gesture notes to the audio engine
  screens/                  # home, piano, gesture, settings
  widgets/                  # piano_keyboard, hand_overlay (CustomPainter), synth_controls
  utils/                    # constants, finger geometry / pose classification
assets/samples/             # piano_<Note>.wav anchor samples
scripts/                    # sample generation / download helpers
test/unit_test.dart         # music theory + gesture geometry unit tests
```

## Getting started

Requires **Flutter ≥ 3.35** (stable; Dart ≥ 3.9, needed by `camera` /
`hand_landmarker`) and an Android device or emulator with a camera for gesture
mode. The Android project is committed, so no extra scaffolding step is needed.

```bash
flutter pub get

# Run on a connected Android device/emulator...
flutter run
# ...or build an installable APK:
flutter build apk --debug
```

Grant the **camera permission** when prompted, then open **Gesture Mode**.

## Piano samples

The repo ships with small, **CC0, self-generated** anchor samples
(`assets/samples/piano_C2.wav` … `piano_C6.wav`) so the "Piano" engine works out
of the box. The audio engine pitch-shifts the nearest anchor to reach every
note, so a few anchors are enough.

Regenerate or replace them:

```bash
# Regenerate the built-in CC0 samples (offline, no dependencies)
python3 scripts/generate_samples.py
#   or
./scripts/fetch_samples.sh

# Download real acoustic piano recordings instead
#   (Salamander Grand Piano, CC-BY 3.0 — keep attribution if you ship them)
./scripts/fetch_samples.sh --real
```

Naming convention the engine expects: `assets/samples/piano_<Note>.<ext>`, e.g.
`piano_A3.wav` or `piano_C#4.mp3`. Re-run `flutter pub get` after adding files.
If no samples are present, the app automatically falls back to the synth.

## How gesture → note mapping works

`hand_landmarker` returns 21 normalized landmarks per hand. `gesture_mapper.dart`
turns those into notes:

- **Air Piano** maps each extended fingertip's horizontal position to a white
  key and triggers it when the fingertip drops below the press line (the line
  height follows the *sensitivity* setting).
- **Hand Poses** classifies the hand from finger-extension geometry
  (`utils/finger_geometry.dart`) and maps each pose to a note/chord, with a short
  de-bounce so poses don't flicker.
- **Theremin** sorts detected hands left→right: the right hand's height sets the
  pitch (snapped to the selected scale), the left hand's height sets volume.

Front-camera coordinates are mirrored so the overlay lines up with the selfie
preview. Overlay/keyboard alignment and thresholds are intentionally simple and
easy to tune in `gesture_mapper.dart` / `hand_tracking_service.dart`.

## Testing & quality

```bash
flutter analyze     # static analysis (clean)
flutter test        # unit tests for music theory + gesture geometry
```

## Manual test checklist

- [ ] Launch → grant camera permission.
- [ ] **Gesture Mode** → verify the camera preview is upright (not sideways) and
      the hand skeleton overlay lines up with your hand; notes play, and the
      keyboard strip highlights what's sounding.
- [ ] Switch gesture mode from the app-bar hand icon (Air Piano / Poses /
      Theremin) and adjust sensitivity in **Settings**.
- [ ] Open the **Synth** bottom sheet → toggle **Synth ↔ Piano** engine and
      confirm the timbre changes; adjust **waveform / ADSR / reverb / echo /
      octave** and hear the effect.
- [ ] Confirm the **screen stays awake** while the gesture screen is open.

## Known limitations

- Hand tracking is **Android only** (MediaPipe native bridge).
- `detect()` runs synchronously per frame and is throttled to ~15 fps; on slower
  devices lower `ResolutionPreset` or raise `minFrameInterval` in
  `hand_tracking_service.dart`.
- Overlay↔preview alignment and press thresholds may need per-device tuning.

## License

Application code: MIT (or your preference). Bundled generated samples are CC0.
If you swap in Salamander Grand Piano samples via `--real`, honour their CC-BY
3.0 attribution.
