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

- **Camera gesture instrument** with five selectable modes:
  - **Air Piano** — fingertips hover over the keyboard; push a finger down past
    the on-screen "press line" to play the key beneath it.
  - **Hand Poses** — hold a recognised pose (fist, point, peace, open hand,
    thumbs up); each fires a note or chord.
  - **Theremin** — one hand's height sweeps pitch across a wide five-octave
    range (C2–C7, quantized to a scale of your choice), the other hand's height
    controls volume.
  - **Strum / Harp** — sweep a fingertip across the scale lanes to pluck notes;
    moving between lanes releases the old note and sounds the next, like a harp
    glissando (and it runs through the arpeggiator when that's on).
  - **Face** — tilt your head to choose the pitch (quantized to your scale) and
    open your mouth to sound it; a hands-free face-theremin.
- **Two switchable sound engines:**
  - **Synth** — real-time oscillators (sine / square / saw / triangle / bounce /
    jaws) with a full **ADSR** envelope and **reverb / echo / distortion**
    effects (via `flutter_soloud`).
  - **Piano** — pitch-shifted piano **samples** (bundled; see below).
- **Expressive & creative controls:**
  - **Velocity from tap speed** — in Air Piano, how fast you jab a finger down
    sets the note's loudness (toggle in *Performance*).
  - **Resonant low-pass filter + LFO** — sweepable cutoff & resonance, with an
    optional LFO that auto-sweeps the cutoff.
  - **Pinch → cutoff** — your *free* hand's pinch distance modulates the filter
    live (a hands-in-the-air "wah").
  - **Pan by hand position** — a playing hand's horizontal position sweeps the
    stereo image left↔right (also assignable to a face signal).
  - **Push / pull depth** — moving a hand toward or away from the camera
    modulates the filter cutoff or the volume live (the hand's size stands in
    for depth), yielding to pinch / theremin on shared targets.
  - **Scale lock** — Air-Piano lanes snap to any scale + key so you're always in
    tune (the default, C Major, matches the classic white-key layout).
  - **Arpeggiator** — held chords/poses spread into a rhythmic sequence
    (up / down / up-down / random, tempo & rate, gate).
  - **Reactive light visualizer** — notes bloom as pitch-colored ripples over
    the camera feed ("play the air, hear the light").
  - **Face control (experimental)** — your face becomes an extra modulator:
    open your mouth, smile, or tilt your head to sweep the filter cutoff,
    reverb, or volume. Runs ML Kit face detection on the *same* camera stream
    as the hand tracker (no second camera), off by default.
- **Synth controls in-context** — a drag-up **bottom sheet** on the gesture
  screen exposes engine, waveform, ADSR, effects, filter/LFO, scale, arpeggiator,
  octave and visuals without leaving the camera; a keyboard strip highlights the
  notes you're playing.
- **In-app gesture guide** — an always-on legend on the camera screen spells out
  what the current mode responds to, and an **ⓘ** button (or tapping the legend)
  opens a per-mode sheet detailing every gesture and the note/chord it plays.
- **Live, persisted settings** — engine, waveform, ADSR, octave shift, effects
  (reverb / echo / distortion), filter/LFO, velocity, pan & depth modulation,
  scale + key, arpeggiator, visualizer, gesture mode & sensitivity, keyboard
  range, theremin scale.

## Tech stack

| Concern              | Package            |
| -------------------- | ------------------ |
| Audio (synth+sample) | `flutter_soloud`   |
| Camera stream        | `camera`           |
| Hand landmarks       | `hand_landmarker`  |
| Face landmarks       | `google_mlkit_face_detection` |
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

## Installing & auto-updating on your phone

You don't need to download CI artifacts by hand. Every push to `main`:

1. builds a release APK versioned `1.0.<run number>`,
2. publishes it as a **GitHub Release** tagged `v1.0.<run number>`, marked
   *latest*, with the APK attached.

**First install:** grab the APK from the
[latest release](https://github.com/andreas83/AR-Synth/releases/latest) and
install it (allow "install unknown apps" for your browser/file manager).

**After that it updates itself.** On launch the app queries the GitHub Releases
API; if a newer version exists it offers to download and install it, showing
progress. You can also trigger a check from the version line at the bottom of
the home screen. Android will ask you to allow AR Synth to *install unknown
apps* the first time — that's the `REQUEST_INSTALL_PACKAGES` permission.

> ⚠️ **About the signing key.** Android only lets an update install over an
> existing app when both are signed with the **same** key. CI's auto-generated
> debug key differs on every run, so this repo commits a fixed keystore
> (`android/app/arsynth-shared.jks`, password `arsynth`) and signs release
> builds with it. **Its password is public — this is a convenience key for a
> personal side-project, not a production one.** If you ever publish to the Play
> Store, generate a private keystore, keep it in GitHub Secrets, and swap the
> `shared` signing config in `android/app/build.gradle.kts`.

Pointing the updater at a different repo: change `kGithubOwner` / `kGithubRepo`
in `lib/utils/constants.dart`.

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
- **Strum / Harp** reuses the Air-Piano lanes: the right-most hand's index
  fingertip x picks a lane (smoothed + sticky), holding that note while the
  finger stays and re-plucking as it sweeps to the next lane.

The raw landmarks jitter frame-to-frame, so the mapper adds a light robustness
layer: the Air-Piano press line has **hysteresis** and each held lane is
**sticky** (a fingertip must move clearly past a boundary before the note jumps),
recognised poses are **held through single-frame mis-reads**, and the Theremin's
pitch/volume run through a **1€ filter** (`utils/one_euro_filter.dart`) that kills
jitter without adding lag. The bands are constants at the top of
`gesture_mapper.dart`, easy to tune per device.

`hand_landmarker` reports landmarks in the raw camera-sensor frame, so the
overlay maps them into the preview's display space — rotating by the sensor
mount orientation and mirroring for the front (selfie) camera — in
`utils/overlay_transform.dart`. With the app locked to portrait and the preview
auto-oriented by the camera plugin, the skeleton, cursors and ripples stay
locked to the hand without any manual rotation. Gesture thresholds are
intentionally simple and easy to tune in `gesture_mapper.dart`.

## App icon

The launcher icon is a clean, minimal **sound wave** on a vibrant diagonal
gradient. It ships as an Android **adaptive icon** (separate background /
foreground / monochrome layers, so Android 8+ masks it to any shape and
Android 13+ can theme it) with legacy square PNGs as a fallback.

The gradient comes in a few ready-made colourways, defined once in the
`PALETTES` table in `scripts/icon/generate_icons.py`:

| Palette     | Gradient                              |
| ----------- | ------------------------------------- |
| `ember`     | orange-red → magenta → purple *(default, shipped)* |
| `sunset`    | amber → rose → violet                 |
| `aurora`    | mint → cyan → indigo                  |
| `synthwave` | cyan → violet → magenta *(original)*  |

Everything is generated from vector sources in [`scripts/icon/`](scripts/icon/)
(`ar_synth_icon.svg` is the master; `ar_synth_bg/fg/mono.svg` are the adaptive
layers — the waveform stays white, only the gradient recolours). To tweak the
art or switch colourways, edit the SVGs / `PALETTES` and regenerate every
density:

```bash
pip install cairosvg pillow
python3 scripts/icon/generate_icons.py                 # active (ember) palette
python3 scripts/icon/generate_icons.py --palette aurora  # try another option
```

## Testing & quality

```bash
flutter analyze     # static analysis (clean)
flutter test        # unit tests for music theory + gesture geometry
```

## Manual test checklist

- [ ] Launch → grant camera permission.
- [ ] **Gesture Mode** → verify the hand skeleton overlay lines up with your
      hand (moving/rotating your hand moves/rotates the skeleton the same way);
      notes play, and the keyboard strip highlights what's sounding.
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
