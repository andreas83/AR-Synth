import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';

/// A currently sounding note. [handle] is null only briefly, while the audio
/// source for the note is still loading; [AudioEngine.noteOn] fills it in once
/// the source resolves (or stops it if the voice was released meanwhile).
class _Voice {
  _Voice(this.peak);

  /// The SoLoud voice handle, or null while the source is still loading.
  SoundHandle? handle;

  /// Attack-target amplitude (0..1), derived from note velocity.
  final double peak;

  /// Cancels the scheduled decay stage if the note is released early.
  Timer? decayTimer;

  /// Set once the note is released or retired; guards late async work (the
  /// decay timer, and the still-loading source in [AudioEngine.noteOn]).
  bool released = false;
}

/// Wraps [SoLoud] to render notes either with real-time oscillators or with
/// pitch-shifted piano samples. Provides a small polyphonic voice manager with
/// an ADSR amplitude envelope and optional global reverb/echo.
///
/// The engine degrades gracefully: if SoLoud fails to initialise, or if no
/// samples are bundled while [SoundEngine.sample] is selected, calls become
/// no-ops / fall back to the synth rather than throwing.
class AudioEngine {
  AudioEngine();

  // Resolved lazily (on first use, i.e. [init]) rather than at construction so
  // the engine can be built without loading the native SoLoud library — e.g. in
  // unit tests, where the engine is never initialised and every call no-ops.
  late final SoLoud _soloud = SoLoud.instance;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  SynthSettings _settings = const SynthSettings();

  /// One reusable oscillator source per MIDI note (frequency baked in).
  final Map<int, AudioSource> _synthSources = <int, AudioSource>{};

  /// Loaded sample sources keyed by their anchor MIDI note.
  final Map<int, AudioSource> _sampleSources = <int, AudioSource>{};

  /// Active voices keyed by the (already transposed) MIDI note.
  final Map<int, _Voice> _voices = <int, _Voice>{};

  bool _reverbActive = false;
  bool _echoActive = false;
  bool _distortionActive = false;

  /// Current live stereo pan (-1 = left .. 1 = right) and whether a live source
  /// (hand position / face) is driving it. Pan is per-voice in SoLoud, so this
  /// is fanned out to every active voice and re-applied to new voices.
  double _pan = 0.0;
  bool _panActive = false;

  /// When non-null, face modulation is live-overriding the reverb wet amount.
  double? _liveReverbWet;

  // -- Resonant low-pass filter state --
  bool _biquadActive = false;

  /// When non-null a live source (pinch gesture) is overriding the cutoff.
  double? _liveCutoffNorm;

  /// Dart-driven LFO that sweeps the filter cutoff (used instead of a native
  /// oscillator so it stays version-independent). The step is deliberately fine
  /// (~120 Hz) so cutoff sweeps sound smooth rather than stepped/"zippered".
  Timer? _lfoTimer;
  double _lfoPhase = 0.0;
  static const Duration _lfoStep = Duration(milliseconds: 8);

  /// Live (non-persisted) master volume from the theremin volume hand. When set
  /// it overrides [SynthSettings.masterVolume] until cleared.
  double? _liveMaster;

  /// How far unison detunes the stacked super-wave copies (SoLoud detune arg) at
  /// full richness. A musically pleasant spread rather than a wide chorus.
  static const double _unisonSpread = 0.6;

  bool get hasSamples => _sampleSources.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _soloud.init();
      _initialized = true;
      _pushGlobalVolume();
      await _loadSamples();
      _applyEffects();
      _applyFilter();
    } catch (e) {
      _initialized = false;
      debugPrint('AudioEngine: SoLoud init failed: $e');
    }
  }

  /// Push new settings; updates master volume, oscillator waveform and effects
  /// live without dropping currently held notes.
  Future<void> applySettings(SynthSettings settings) async {
    final SynthSettings previous = _settings;
    _settings = settings;
    if (!_initialized) return;

    if (settings.masterVolume != previous.masterVolume) {
      // A deliberate master-slider (or preset) change re-asserts the base level.
      _liveMaster = null;
      _pushGlobalVolume();
    }
    if (settings.wave != previous.wave) {
      final WaveForm wf = _mapWave(settings.wave);
      for (final AudioSource src in _synthSources.values) {
        try {
          _soloud.setWaveform(src, wf);
        } catch (_) {}
      }
    }
    // Unison (super-wave) is baked in at load time, so cached oscillator sources
    // must be rebuilt. Drop those not held by a live voice; leave sounding ones
    // so held notes don't cut out. New notes lazily recreate with the new detune.
    if (settings.unison != previous.unison) {
      await _rebuildIdleSynthSources();
    }
    if (settings.reverb != previous.reverb ||
        settings.echo != previous.echo ||
        settings.distortion != previous.distortion) {
      _applyEffects();
    }
    if (settings.filterEnabled != previous.filterEnabled ||
        settings.filterCutoff != previous.filterCutoff ||
        settings.filterResonance != previous.filterResonance ||
        settings.lfoEnabled != previous.lfoEnabled ||
        settings.lfoRateHz != previous.lfoRateHz ||
        settings.lfoDepth != previous.lfoDepth) {
      _applyFilter();
    }
  }

  /// Sets the output volume live without persisting it (used by theremin mode
  /// for continuous volume control). Does not modify the stored settings.
  Future<void> setLiveMasterVolume(double v) async {
    if (!_initialized) return;
    _liveMaster = v.clamp(0.0, 1.0);
    _pushGlobalVolume();
  }

  /// Live-sets the low-pass cutoff from a normalized 0..1 control (used by the
  /// pinch-to-modulate gesture). Activates the filter on demand and takes
  /// precedence over the static cutoff / LFO until [clearLiveCutoff] is called.
  void setLiveCutoff(double norm01) {
    _liveCutoffNorm = norm01.clamp(0.0, 1.0);
    if (!_initialized) return;
    if (!_ensureBiquad()) return;
    _writeCutoffHz(_cutoffHz(_liveCutoffNorm!));
  }

  /// Ends live cutoff control; restores the static cutoff / LFO, or deactivates
  /// the filter if it isn't otherwise enabled.
  void clearLiveCutoff() {
    if (_liveCutoffNorm == null) return;
    _liveCutoffNorm = null;
    if (!_initialized) return;
    _applyFilter();
  }

  /// Live-sets the reverb wet amount without persisting it (used by face
  /// modulation). Activates reverb on demand.
  void setLiveReverb(double wet01) {
    _liveReverbWet = wet01.clamp(0.0, 1.0);
    if (!_initialized) return;
    try {
      final filters = _soloud.filters;
      if (!_reverbActive) {
        filters.freeverbFilter.activate();
        _reverbActive = true;
        filters.freeverbFilter.roomSize.value = 0.6;
      }
      filters.freeverbFilter.wet.value = _liveReverbWet!;
    } catch (_) {}
  }

  /// Ends live reverb control; restores the persisted reverb setting.
  void clearLiveReverb() {
    if (_liveReverbWet == null) return;
    _liveReverbWet = null;
    if (!_initialized) return;
    _applyEffects();
  }

  /// Live-sets the stereo pan from a normalized -1..1 control (hand position /
  /// face). SoLoud pan is per-voice, so this fans out to every active voice and
  /// [noteOn] re-applies it to new voices while [_panActive].
  void setLivePan(double pan) {
    _pan = pan.clamp(-1.0, 1.0);
    _panActive = true;
    if (!_initialized) return;
    for (final _Voice v in _voices.values) {
      final SoundHandle? h = v.handle;
      if (h == null) continue; // still loading; noteOn applies the pan on arrival
      try {
        _soloud.setPan(h, _pan);
      } catch (_) {}
    }
  }

  /// Ends live pan control and recenters every voice.
  void clearLivePan() {
    if (!_panActive) return;
    _panActive = false;
    _pan = 0.0;
    if (!_initialized) return;
    for (final _Voice v in _voices.values) {
      final SoundHandle? h = v.handle;
      if (h == null) continue;
      try {
        _soloud.setPan(h, 0.0);
      } catch (_) {}
    }
  }

  /// The effective MIDI number after applying the octave shift.
  int _effectiveMidi(Note note) => note.midi + _settings.octaveShift * 12;

  /// Start a note. Safe to call repeatedly; retriggers if already sounding.
  Future<void> noteOn(Note note, {double velocity = 1.0}) async {
    if (!_initialized) return;
    final int midi = _effectiveMidi(note);
    if (midi < 0 || midi > 127) return;

    // Retrigger: retire any existing (or still-loading) voice for this note.
    final _Voice? prev = _voices.remove(midi);
    if (prev != null) _retire(prev);

    final Adsr env = _settings.adsr;
    final double peak = (0.9 * velocity).clamp(0.0, 1.0);
    final bool useSamples =
        _settings.engine == SoundEngine.sample && hasSamples;

    // Reserve the voice slot *synchronously*, before awaiting the source load.
    // A note-off that lands while the source is loading then finds this voice
    // and marks it released, so the resolved handle is stopped below instead of
    // leaking a stuck, untracked oscillator (which would silently pile up and
    // degrade the output over time).
    final _Voice voice = _Voice(peak);
    _voices[midi] = voice;

    SoundHandle? handle;
    try {
      handle = useSamples ? await _playSample(midi) : await _playSynth(midi);
    } catch (e) {
      debugPrint('AudioEngine.noteOn failed for $note: $e');
    }

    // If the source failed to load, drop the placeholder (unless a newer voice
    // already took the slot).
    if (handle == null) {
      if (identical(_voices[midi], voice)) _voices.remove(midi);
      return;
    }
    // If this voice was released or replaced while loading, don't install it —
    // stop the orphan handle instead.
    if (voice.released || !identical(_voices[midi], voice)) {
      try {
        await _soloud.stop(handle);
      } catch (_) {}
      return;
    }
    voice.handle = handle;

    // A note started mid-pan must inherit the current pan, not play centered.
    if (_panActive) {
      try {
        _soloud.setPan(handle, _pan);
      } catch (_) {}
    }

    // Attack: ramp from silence to peak.
    final Duration attack = _secs(env.attack);
    try {
      _soloud.fadeVolume(handle, peak, attack);
    } catch (_) {}

    // Decay: fall to the sustain level after the attack completes.
    voice.decayTimer = Timer(attack, () {
      if (voice.released) return;
      try {
        _soloud.fadeVolume(handle!, peak * env.sustain, _secs(env.decay));
      } catch (_) {}
    });
  }

  /// Retires a voice immediately: cancels its envelope and stops its handle, or
  /// — if the source is still loading — marks it released so [noteOn] stops the
  /// handle as soon as it resolves.
  void _retire(_Voice voice) {
    voice.released = true;
    voice.decayTimer?.cancel();
    final SoundHandle? handle = voice.handle;
    if (handle != null) _hardStopHandle(handle);
  }

  /// Release a note (enters the ADSR release stage, then stops).
  Future<void> noteOff(Note note) async {
    if (!_initialized) return;
    final int midi = _effectiveMidi(note);
    final _Voice? voice = _voices.remove(midi);
    if (voice == null) return;
    voice.released = true;
    voice.decayTimer?.cancel();

    final SoundHandle? handle = voice.handle;
    // Still loading: noteOn sees `released` and stops the handle on arrival.
    if (handle == null) return;

    final Duration release = _secs(_settings.adsr.release);
    try {
      _soloud.fadeVolume(handle, 0.0, release);
      _soloud.scheduleStop(handle, release);
    } catch (_) {
      await _hardStopHandle(handle);
    }
  }

  /// Immediately silence everything.
  Future<void> allNotesOff() async {
    final List<_Voice> voices = _voices.values.toList(growable: false);
    _voices.clear();
    for (final _Voice v in voices) {
      _retire(v);
    }
  }

  Future<void> dispose() async {
    _stopLfo();
    await allNotesOff();
    if (_initialized) {
      try {
        _soloud.deinit();
      } catch (_) {}
    }
    _initialized = false;
  }

  // -- Internals --------------------------------------------------------------

  /// Writes the effective global volume: the live (theremin) master when set,
  /// else the persisted master. This is a single, steady output gain — it is
  /// deliberately *not* modulated by the live voice count, so releasing notes
  /// never get momentarily boosted (which was audible as a loud tail at the end
  /// of a gesture) and a busy passage never ducks the whole mix toward silence.
  void _pushGlobalVolume() {
    if (!_initialized) return;
    final double base = (_liveMaster ?? _settings.masterVolume).clamp(0.0, 1.0);
    try {
      _soloud.setGlobalVolume(base);
    } catch (_) {}
  }

  Future<SoundHandle> _playSynth(int midi) async {
    final AudioSource src = await _synthSourceFor(midi);
    return _soloud.play(src, volume: 0.0);
  }

  Future<AudioSource> _synthSourceFor(int midi) async {
    final AudioSource? existing = _synthSources[midi];
    if (existing != null) return existing;
    // Unison > 0 enables SoLoud's detuned super-wave for a wider, lusher tone;
    // 0 keeps a single oscillator (identical to the original sound).
    final double unison = _settings.unison.clamp(0.0, 1.0);
    final bool superWave = unison > 0.001;
    final double detune = 1.0 + unison * _unisonSpread;
    final AudioSource src = await _soloud.loadWaveform(
        _mapWave(_settings.wave), superWave, 1.0, detune);
    _soloud.setWaveformFreq(src, Note(midi).frequency);
    _synthSources[midi] = src;
    return src;
  }

  /// Disposes cached oscillator sources that no live voice is currently using,
  /// so the next note for that pitch is rebuilt with the current unison setting.
  /// Sources backing a sounding voice are kept so held notes are not cut off.
  Future<void> _rebuildIdleSynthSources() async {
    final Set<int> heldMidis = _voices.keys.toSet();
    final List<int> idle = _synthSources.keys
        .where((int midi) => !heldMidis.contains(midi))
        .toList(growable: false);
    for (final int midi in idle) {
      final AudioSource? src = _synthSources.remove(midi);
      if (src == null) continue;
      try {
        await _soloud.disposeSource(src);
      } catch (_) {}
    }
  }

  Future<SoundHandle?> _playSample(int midi) async {
    final int anchor = _nearestAnchor(midi);
    final AudioSource? src = _sampleSources[anchor];
    if (src == null) return null;
    final SoundHandle handle = await _soloud.play(src, volume: 0.0);
    // Resample to shift pitch: ratio 2^(semitones/12).
    final double ratio = _pitchRatio(midi - anchor);
    try {
      _soloud.setRelativePlaySpeed(handle, ratio);
    } catch (_) {}
    return handle;
  }

  int _nearestAnchor(int midi) {
    int best = _sampleSources.keys.first;
    int bestDist = (best - midi).abs();
    for (final int anchor in _sampleSources.keys) {
      final int d = (anchor - midi).abs();
      if (d < bestDist) {
        best = anchor;
        bestDist = d;
      }
    }
    return best;
  }

  Future<void> _hardStopHandle(SoundHandle handle) async {
    try {
      await _soloud.stop(handle);
    } catch (_) {}
  }

  /// Discovers bundled samples via the asset manifest and loads any file named
  /// like `assets/samples/piano_<Note>.<ext>` (e.g. `piano_A4.wav`).
  Future<void> _loadSamples() async {
    List<String> assetKeys;
    try {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      assetKeys = manifest
          .listAssets()
          .where((String k) => k.startsWith('assets/samples/'))
          .where((String k) => _midiFromSampleName(k) != null)
          .toList(growable: false);
    } catch (_) {
      assetKeys = const <String>[];
    }

    for (final String key in assetKeys) {
      final int? midi = _midiFromSampleName(key);
      if (midi == null) continue;
      try {
        final AudioSource src = await _soloud.loadAsset(key);
        _sampleSources[midi] = src;
      } catch (e) {
        debugPrint('AudioEngine: failed to load sample $key: $e');
      }
    }
    if (_sampleSources.isNotEmpty) {
      debugPrint('AudioEngine: loaded ${_sampleSources.length} sample(s).');
    }
  }

  void _applyEffects() {
    if (!_initialized) return;
    // Global filters. The exact filter API can vary between flutter_soloud
    // minor versions, so every access is guarded.
    final filters = _soloud.filters;
    // Reverb — track activation locally so we never double-activate.
    try {
      if (_settings.reverb > 0.001) {
        if (!_reverbActive) {
          filters.freeverbFilter.activate();
          _reverbActive = true;
        }
        filters.freeverbFilter.wet.value = _settings.reverb.clamp(0.0, 1.0);
        filters.freeverbFilter.roomSize.value = 0.6;
      } else if (_reverbActive) {
        filters.freeverbFilter.deactivate();
        _reverbActive = false;
      }
    } catch (e) {
      debugPrint('AudioEngine: reverb unavailable on this version: $e');
    }
    // Echo
    try {
      if (_settings.echo > 0.001) {
        if (!_echoActive) {
          filters.echoFilter.activate();
          _echoActive = true;
        }
        filters.echoFilter.wet.value = _settings.echo.clamp(0.0, 1.0);
        filters.echoFilter.delay.value = 0.25;
        filters.echoFilter.decay.value = 0.4;
      } else if (_echoActive) {
        filters.echoFilter.deactivate();
        _echoActive = false;
      }
    } catch (e) {
      debugPrint('AudioEngine: echo unavailable on this version: $e');
    }
    // Distortion (wave shaper) — drive/wet both follow the single 0..1 amount.
    try {
      if (_settings.distortion > 0.001) {
        if (!_distortionActive) {
          filters.waveShaperFilter.activate();
          _distortionActive = true;
        }
        final double amt = _settings.distortion.clamp(0.0, 1.0);
        filters.waveShaperFilter.wet.value = amt;
        filters.waveShaperFilter.amount.value = amt;
      } else if (_distortionActive) {
        filters.waveShaperFilter.deactivate();
        _distortionActive = false;
      }
    } catch (e) {
      debugPrint('AudioEngine: distortion unavailable on this version: $e');
    }
  }

  // -- Low-pass filter + LFO --------------------------------------------------

  /// Maps a normalized 0..1 cutoff to Hz on a log curve (~80 Hz .. ~11.2 kHz),
  /// which feels natural for a filter sweep.
  static double _cutoffHz(double norm) =>
      (80.0 * math.pow(140.0, norm.clamp(0.0, 1.0))).toDouble();

  /// Ensures the biquad filter is active and configured. Returns false if the
  /// filter API is unavailable on this flutter_soloud build.
  bool _ensureBiquad() {
    try {
      final filters = _soloud.filters;
      if (!_biquadActive) {
        filters.biquadResonantFilter.activate();
        _biquadActive = true;
      }
      filters.biquadResonantFilter.type.value = 0.0; // 0 == low-pass
      filters.biquadResonantFilter.resonance.value =
          0.1 + _settings.filterResonance.clamp(0.0, 1.0) * 19.9;
      return true;
    } catch (e) {
      debugPrint('AudioEngine: biquad filter unavailable: $e');
      return false;
    }
  }

  void _writeCutoffHz(double hz) {
    try {
      _soloud.filters.biquadResonantFilter.frequency.value =
          hz.clamp(10.0, 16000.0);
    } catch (_) {}
  }

  /// (Re)configures the filter from the current settings + live-cutoff state.
  void _applyFilter() {
    if (!_initialized) return;
    final bool wantActive =
        _settings.filterEnabled || _liveCutoffNorm != null;

    if (wantActive) {
      if (!_ensureBiquad()) return;
    } else {
      if (_biquadActive) {
        try {
          _soloud.filters.biquadResonantFilter.deactivate();
        } catch (_) {}
        _biquadActive = false;
      }
      _stopLfo();
      return;
    }

    _refreshCutoff();
    _refreshLfo();
  }

  /// Writes the current static/live cutoff. The LFO (when running) drives the
  /// frequency itself, so this only writes when the LFO is not in charge.
  void _refreshCutoff() {
    if (!_initialized || !_biquadActive) return;
    if (_liveCutoffNorm != null) {
      _writeCutoffHz(_cutoffHz(_liveCutoffNorm!));
    } else if (!(_settings.lfoEnabled && _settings.lfoDepth > 0.001)) {
      _writeCutoffHz(_cutoffHz(_settings.filterCutoff));
    }
  }

  void _refreshLfo() {
    final bool wantLfo = _initialized &&
        _biquadActive &&
        _settings.lfoEnabled &&
        _settings.lfoDepth > 0.001;
    if (wantLfo) {
      _lfoTimer ??= Timer.periodic(_lfoStep, (_) => _lfoTick());
    } else {
      _stopLfo();
      _refreshCutoff();
    }
  }

  void _stopLfo() {
    _lfoTimer?.cancel();
    _lfoTimer = null;
  }

  void _lfoTick() {
    // Pinch modulation takes precedence over the LFO.
    if (_liveCutoffNorm != null) return;
    final double rate = _settings.lfoRateHz.clamp(0.05, 20.0);
    _lfoPhase += 2 * math.pi * rate * (_lfoStep.inMilliseconds / 1000.0);
    if (_lfoPhase > 2 * math.pi) _lfoPhase -= 2 * math.pi;
    final double depth = _settings.lfoDepth.clamp(0.0, 1.0);
    final double base = _settings.filterCutoff.clamp(0.0, 1.0);
    final double norm = (base + depth * 0.5 * math.sin(_lfoPhase)).clamp(0.0, 1.0);
    _writeCutoffHz(_cutoffHz(norm));
  }

  static WaveForm _mapWave(SynthWave w) => switch (w) {
        SynthWave.sine => WaveForm.sin,
        SynthWave.square => WaveForm.square,
        SynthWave.saw => WaveForm.saw,
        SynthWave.triangle => WaveForm.triangle,
        SynthWave.bounce => WaveForm.bounce,
        SynthWave.jaws => WaveForm.jaws,
      };

  static double _pitchRatio(int semitones) {
    // 2^(semitones/12)
    double r = 1.0;
    const double step = 1.0594630943592953; // 2^(1/12)
    if (semitones >= 0) {
      for (int i = 0; i < semitones; i++) {
        r *= step;
      }
    } else {
      for (int i = 0; i < -semitones; i++) {
        r /= step;
      }
    }
    return r;
  }

  static Duration _secs(double s) =>
      Duration(milliseconds: (s.clamp(0.0, 10.0) * 1000).round());

  /// Parses an anchor MIDI number from a sample filename such as
  /// `assets/samples/piano_C#4.wav`. Returns null if it can't be parsed.
  static int? _midiFromSampleName(String assetKey) {
    final String file = assetKey.split('/').last;
    final int dot = file.lastIndexOf('.');
    final String stem = dot >= 0 ? file.substring(0, dot) : file;
    final int underscore = stem.lastIndexOf('_');
    final String noteToken =
        underscore >= 0 ? stem.substring(underscore + 1) : stem;
    return noteNameToMidi(noteToken);
  }
}

/// Converts a note name like `A4`, `C#3`, `Gb5` to a MIDI number, or null.
int? noteNameToMidi(String name) {
  final RegExp re = RegExp(r'^([A-Ga-g])([#b]?)(-?\d+)$');
  final RegExpMatch? m = re.firstMatch(name.trim());
  if (m == null) return null;
  const Map<String, int> base = <String, int>{
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };
  final int letter = base[m.group(1)!.toUpperCase()]!;
  final String accidental = m.group(2)!;
  final int octave = int.parse(m.group(3)!);
  int semitone = letter;
  if (accidental == '#') semitone += 1;
  if (accidental == 'b') semitone -= 1;
  return (octave + 1) * 12 + semitone;
}
