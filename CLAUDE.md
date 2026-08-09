# CLAUDE.md

Guidance for AI assistants (Claude Code and similar) working in this repository.
Read this first; it captures the architecture, conventions, and gotchas that
aren't obvious from any single file. For a user-facing feature tour see
`README.md`.

## What this is

**AR Synth** is a Flutter app: a camera hand-gesture virtual piano and
synthesizer. The camera tracks your hands (and optionally your face) and turns
gestures into music, rendered by a real-time audio engine.

- **Package name:** `ar_synth` (see `pubspec.yaml`).
- **Platform:** Android-first. Hand tracking uses native MediaPipe via JNI, so
  gesture mode only works on Android; on other platforms it shows an "Android
  only" notice. The app is locked to **portrait** and keeps the screen awake
  while playing.
- **Toolchain:** Flutter **≥ 3.35** / Dart **≥ 3.9** (required by `camera` /
  `hand_landmarker`). CI pins Flutter `3.44.9` on the `stable` channel with
  JDK 17. Do not use language features or APIs newer than the pinned version.

## Common commands

```bash
flutter pub get            # fetch dependencies (re-run after adding assets/pkgs)
flutter run                # run on a connected Android device/emulator
flutter build apk --debug  # build an installable debug APK
flutter analyze            # static analysis — MUST stay clean (CI gates on it)
flutter test               # unit + widget tests (CI gates on it)
```

Regenerate bundled piano samples (offline, no network):
`python3 scripts/generate_samples.py`. Regenerate the launcher icon from the
SVG masters in `scripts/icon/`: `python3 scripts/icon/generate_icons.py`
(needs `cairosvg pillow`).

## Architecture

The app follows a layered **services → state → screens/widgets** structure,
wired together at startup. `provider` is the only state-management mechanism.

### Startup wiring (`lib/main.dart`)

`main()` builds the object graph explicitly, in order, then injects it via
`MultiProvider`:

1. `AudioEngine()` + `await audio.init()` — the SoLoud engine.
2. `SettingsController(audio)` + `await settings.load()` — restores persisted
   settings and pushes them to the engine.
3. `PianoController(audio, settings)` — the note router.
4. `runApp(...)` with `GestureScreen` as the home (there is no landing screen).

Dependencies flow **downward** (audio ← settings ← piano). Widgets read these
via `context.watch/read<T>()`. When adding a new service or controller, prefer
constructor injection here over service locators or globals.

### Layers (`lib/`)

- **`models/`** — plain data + enums, no Flutter-widget dependencies.
  - `music.dart` — `Note` (MIDI-backed, A4=69=440 Hz), keyboard/scale helpers,
    `quantizeToScale`. This is the single source of truth for pitch math.
  - `synth_settings.dart` — the immutable `SynthSettings` value object plus all
    the feature enums (`SoundEngine`, `SynthWave`, `GestureMode`, `FaceTarget`,
    …). `copyWith` / `toJson` / `fromJson` live here.
  - `hand_data.dart`, `face_data.dart` — normalized tracker output structs
    (`HandFrame`, `FaceFrame`) that decouple the app from plugin types.
- **`services/`** — side-effecting engines and I/O.
  - `audio_engine.dart` — wraps `flutter_soloud`. Polyphonic voice manager with
    ADSR envelope, reverb/echo, a wave-shaper **distortion**, a resonant
    low-pass biquad, and a Dart-driven LFO. Renders notes as either oscillators
    (`SoundEngine.synth`, sine/square/saw/triangle/bounce/jaws) or pitch-shifted
    samples (`SoundEngine.sample`). Live-modulation hooks (`setLive*`) cover
    master volume, filter cutoff, reverb wet, and **stereo pan** — pan is
    *per-voice* in SoLoud, so `setLivePan` fans out to every active voice and
    `noteOn` re-applies it to new voices. **Degrades gracefully** — if SoLoud
    fails to init, or no samples are bundled, calls become no-ops / fall back to
    synth instead of throwing (every filter access is try/caught).
  - `hand_tracking_service.dart` — owns the `CameraController` + MediaPipe
    `HandLandmarkerPlugin`, throttles synchronous `detect()` to ~15 fps
    (`minFrameInterval`), guards re-entrancy, and publishes normalized
    `HandFrame`s on a broadcast stream. Optionally forwards the same frames to
    `FaceTracker` when `faceEnabled`.
  - `face_tracker.dart` — ML Kit face detection on the shared camera stream.
  - `gesture_mapper.dart` — the heart of the app: turns a `HandFrame` into a
    `GestureOutput` (held notes, velocities, cursors, modulation), one strategy
    per `GestureMode` (`airPiano`, `discretePoses`, `theremin`, `strum`, plus
    face which is driven off the face stream). `GestureOutput` also carries the
    continuous live-modulation signals: `pinchModulation`, `pan` (from hand-x),
    and `depthModulation` (from `handScale`, a stable proxy for distance to
    camera). Holds per-mode state, so it must be **reused across frames and
    `reset()` when the mode changes**. Robustness tuning constants (press-line
    hysteresis, sticky lanes, pose de-bounce, depth near/far bounds) live at the
    top.
  - `update_service.dart` — polls the GitHub Releases API for the in-app
    self-updater.
- **`state/`** — `ChangeNotifier` controllers bridging UI and services.
  - `piano_controller.dart` — **central note router**. Both touch and gesture
    input funnel through here; it diffs held-note sets into note-on/note-off,
    routes live modulation (theremin volume, pinch→cutoff, hand pan, push/pull
    depth, face), and exposes `activeNotes` for UI highlighting. Each live
    source sets an `_xAdjusted` flag and restores its target in `clearGesture`.
    Precedence for shared targets: pinch > depth > face on cutoff; theremin >
    depth > face on volume; hand-x pan > face on pan.
  - `settings_controller.dart` — holds `SynthSettings`, persists to
    `shared_preferences`, and pushes every change to the `AudioEngine` so edits
    take effect live. All mutations go through the private `_update`.
  - `arpeggiator.dart` — clocks held chords into a rhythmic sequence.
- **`screens/`** — `gesture_screen.dart` (the main camera instrument, the
  largest file) and `settings_screen.dart`.
- **`widgets/`** — reusable UI: `piano_keyboard`, `hand_overlay` /
  `note_ripple_painter` (`CustomPainter`s over the camera feed), `synth_controls`
  (the drag-up bottom sheet), `ui_kit`, `update_dialog`.
- **`utils/`** — pure helpers, heavily unit-tested:
  - `finger_geometry.dart` — finger-extension geometry & pose classification.
  - `one_euro_filter.dart` — 1€ filter that de-jitters continuous signals.
  - `overlay_transform.dart` — maps raw sensor-frame landmarks into preview
    display space (rotate by sensor mount, mirror for the front camera).
  - `constants.dart` — spacing, prefs key, **GitHub owner/repo for the updater**,
    finger colors.

### The gesture → audio data flow

```
Camera frame
  → HandTrackingService.detect()            (throttled, native MediaPipe)
  → HandFrame (normalized landmarks)
  → GestureMapper.map(frame, mode, settings)
  → GestureOutput (heldNotes, velocities, cursors, modulation)
  → PianoController.applyGesture(output)     (diff → note on/off, live mod)
  → AudioEngine.noteOn/noteOff/setLive*()    (SoLoud voices)
```

Overlay painters consume the same `GestureOutput.cursors` / `pressLineY` to draw
the skeleton, fingertip cursors, and note ripples locked to the hand.

## Conventions

- **Style / lints:** `analysis_options.yaml` extends `flutter_lints` and adds
  `strict-casts` + `strict-raw-types`, plus enforced `prefer_const_*` and
  `prefer_final_locals`, `unnecessary_this`. Public-member API docs are *not*
  required, but `print` is allowed (use `debugPrint`). **`flutter analyze` must
  stay clean** — CI fails otherwise.
- **Types:** the codebase uses explicit types on locals and fields (e.g.
  `final Set<Note> next = ...`) rather than leaning on `var`/`final` inference.
  Match that when editing existing files.
- **Immutability:** `SynthSettings` is immutable; change it with `copyWith` and
  route through `SettingsController` so persistence + live audio update stay in
  sync. Never mutate settings in place.
- **Enums with behavior:** feature enums carry `label`/`description` via
  extensions and use Dart 3 `switch` expressions. Follow that pattern for new
  modes/options — and update the exhaustive switches (the compiler will flag
  them).
- **Comments** explain *why* (device quirks, ordering, precedence), not *what*.
  Several important decisions are documented inline (e.g. the pinned
  `google_mlkit_face_detection 0.13.2` in `pubspec.yaml`) — preserve them.
- **Graceful degradation** is a theme: the audio and tracking layers no-op or
  fall back rather than throw when a capability is missing. Keep new code in
  that spirit.
- **Tuning knobs** (gesture thresholds, frame rate, LFO step) are named
  constants near the top of their file so they're easy to tweak per device —
  add new ones the same way rather than burying magic numbers.

## Testing

- `test/unit_test.dart` — music theory (`Note`, scales, `quantizeToScale`),
  gesture geometry, filters, and pure service logic.
- `test/ui_kit_test.dart` — widget render/smoke tests under `AppTheme.dark`.

Add tests for pure logic in `models/` and `utils/` when you change it — those
layers are deliberately Flutter-free and easy to test. Run `flutter test`
before pushing.

## CI, releases & the shared keystore

`.github/workflows/build-apk.yml` runs on pushes to `main`/`master`/`claude/**`
and on PRs: `flutter pub get` → `analyze` → `test` → `build apk --release`
versioned `1.0.<run_number>`.

- On **`main` pushes only**, it publishes a GitHub Release tagged
  `v1.0.<run_number>` (marked latest) with the APK attached. The in-app updater
  polls `/releases/latest`, so this is what delivers updates to devices.
- **Signing:** release builds are signed with a *committed, public-password*
  shared keystore (`android/app/arsynth-shared.jks`, password `arsynth`, wired
  in `android/app/build.gradle.kts`). This exists so every build shares a
  signature and can install over the previous one. It is a convenience key for
  a personal side-project — **do not treat it as a secret**, and if you ever
  productionize, move to a private keystore in GitHub Secrets.
- **Android:** `applicationId com.example.ar_synth`, `minSdk` ≥ 24 (MediaPipe
  requirement). Permissions: `CAMERA`, `INTERNET`, `REQUEST_INSTALL_PACKAGES`
  (the last one powers the self-updater).

To point the updater at a different repo, change `kGithubOwner` / `kGithubRepo`
in `lib/utils/constants.dart`.

## Gotchas

- **Don't bump `google_mlkit_face_detection` past `0.13.2`** without on-device
  verification — 0.14.0's native rewrite regressed and threw on every frame.
  The pin and its rationale are documented in `pubspec.yaml`.
- **Overlay alignment** is device-sensitive. Landmarks come in the raw sensor
  frame; `overlay_transform.dart` rotates + mirrors them. The app is locked to
  portrait partly to keep this alignment stable.
- **`detect()` is synchronous** and throttled; on slow devices lower
  `ResolutionPreset` or raise `minFrameInterval` in `hand_tracking_service.dart`.
- **Samples:** the engine expects `assets/samples/piano_<Note>.<ext>` (e.g.
  `piano_A3.wav`). Re-run `flutter pub get` after adding sample files. Missing
  samples → automatic synth fallback.

## Git workflow for AI assistants

- Develop on the branch you were assigned; create it from the latest default
  branch if it doesn't exist. Don't push to other branches without permission.
- Keep commits focused with clear messages. Push with
  `git push -u origin <branch>`.
- **Do not open a pull request unless explicitly asked.**
- Before finishing a change, run `flutter analyze` and `flutter test` locally so
  you don't hand CI a red build.
