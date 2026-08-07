import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_soloud/flutter_soloud.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';

/// A currently sounding note.
class _Voice {
  _Voice(this.handle, this.peak);

  final SoundHandle handle;
  final double peak;

  /// Cancels the scheduled decay stage if the note is released early.
  Timer? decayTimer;
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

  final SoLoud _soloud = SoLoud.instance;

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

  bool get hasSamples => _sampleSources.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _soloud.init();
      _initialized = true;
      _soloud.setGlobalVolume(_settings.masterVolume);
      await _loadSamples();
      _applyEffects();
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
      _soloud.setGlobalVolume(settings.masterVolume);
    }
    if (settings.wave != previous.wave) {
      final WaveForm wf = _mapWave(settings.wave);
      for (final AudioSource src in _synthSources.values) {
        try {
          _soloud.setWaveform(src, wf);
        } catch (_) {}
      }
    }
    if (settings.reverb != previous.reverb || settings.echo != previous.echo) {
      _applyEffects();
    }
  }

  /// Sets the output volume live without persisting it (used by theremin mode
  /// for continuous volume control). Does not modify the stored settings.
  Future<void> setLiveMasterVolume(double v) async {
    if (!_initialized) return;
    try {
      _soloud.setGlobalVolume(v.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// The effective MIDI number after applying the octave shift.
  int _effectiveMidi(Note note) => note.midi + _settings.octaveShift * 12;

  /// Start a note. Safe to call repeatedly; retriggers if already sounding.
  Future<void> noteOn(Note note, {double velocity = 1.0}) async {
    if (!_initialized) return;
    final int midi = _effectiveMidi(note);
    if (midi < 0 || midi > 127) return;

    // Retrigger: stop any existing voice for this note first.
    if (_voices.containsKey(midi)) {
      await _hardStop(midi);
    }

    final Adsr env = _settings.adsr;
    final double peak = (0.9 * velocity).clamp(0.0, 1.0);
    final bool useSamples =
        _settings.engine == SoundEngine.sample && hasSamples;

    SoundHandle? handle;
    try {
      if (useSamples) {
        handle = await _playSample(midi);
      } else {
        handle = await _playSynth(midi);
      }
    } catch (e) {
      debugPrint('AudioEngine.noteOn failed for $note: $e');
      return;
    }
    if (handle == null) return;

    final _Voice voice = _Voice(handle, peak);
    _voices[midi] = voice;

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

  /// Release a note (enters the ADSR release stage, then stops).
  Future<void> noteOff(Note note) async {
    if (!_initialized) return;
    final int midi = _effectiveMidi(note);
    final _Voice? voice = _voices.remove(midi);
    if (voice == null) return;
    voice.released = true;
    voice.decayTimer?.cancel();

    final Duration release = _secs(_settings.adsr.release);
    try {
      _soloud.fadeVolume(voice.handle, 0.0, release);
      _soloud.scheduleStop(voice.handle, release);
    } catch (_) {
      await _hardStopHandle(voice.handle);
    }
  }

  /// Immediately silence everything.
  Future<void> allNotesOff() async {
    final List<int> midis = _voices.keys.toList(growable: false);
    for (final int midi in midis) {
      await _hardStop(midi);
    }
  }

  Future<void> dispose() async {
    await allNotesOff();
    if (_initialized) {
      try {
        _soloud.deinit();
      } catch (_) {}
    }
    _initialized = false;
  }

  // -- Internals --------------------------------------------------------------

  Future<SoundHandle> _playSynth(int midi) async {
    final AudioSource src = await _synthSourceFor(midi);
    return _soloud.play(src, volume: 0.0);
  }

  Future<AudioSource> _synthSourceFor(int midi) async {
    final AudioSource? existing = _synthSources[midi];
    if (existing != null) return existing;
    final AudioSource src =
        await _soloud.loadWaveform(_mapWave(_settings.wave), false, 1.0, 1.0);
    _soloud.setWaveformFreq(src, Note(midi).frequency);
    _synthSources[midi] = src;
    return src;
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

  Future<void> _hardStop(int midi) async {
    final _Voice? voice = _voices.remove(midi);
    if (voice == null) return;
    voice.decayTimer?.cancel();
    await _hardStopHandle(voice.handle);
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
  }

  static WaveForm _mapWave(SynthWave w) => switch (w) {
        SynthWave.sine => WaveForm.sin,
        SynthWave.square => WaveForm.square,
        SynthWave.saw => WaveForm.saw,
        SynthWave.triangle => WaveForm.triangle,
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
