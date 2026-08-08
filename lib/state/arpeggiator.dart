import 'dart:async';
import 'dart:math' as math;

import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/audio_engine.dart';

/// Duration of a single arpeggiator step for the given tempo + note division.
/// Pure + testable.
Duration arpStepDuration(double bpm, ArpRate rate) {
  final double beatSeconds = 60.0 / bpm.clamp(20.0, 300.0);
  final int ms = (beatSeconds * rate.beatFraction * 1000).round();
  return Duration(milliseconds: ms.clamp(20, 4000));
}

/// Index into a chord of [n] notes for the "up/down" pattern at [step], where
/// the endpoints are not repeated (0..n-1..1). Pure + testable.
int arpUpDownIndex(int step, int n) {
  if (n <= 1) return 0;
  final int period = 2 * n - 2;
  final int pos = step % period;
  return pos < n ? pos : period - pos;
}

/// The chord index to play for [pattern] at [step] over [n] notes. [rng] is
/// only consulted for [ArpPattern.random]. Pure + testable.
int arpPatternIndex(ArpPattern pattern, int step, int n, math.Random rng) {
  if (n <= 0) return 0;
  return switch (pattern) {
    ArpPattern.down => n - 1 - (step % n),
    ArpPattern.updown => arpUpDownIndex(step, n),
    ArpPattern.random => rng.nextInt(n),
    ArpPattern.up => step % n,
  };
}

/// Drives an arpeggio over a held chord on its own clock (decoupled from the
/// ~15 fps gesture stream). Feed it the current held set via [setChord]; it
/// plays one note per step through the [AudioEngine].
class Arpeggiator {
  Arpeggiator({
    required AudioEngine audio,
    required SynthSettings Function() settings,
    required void Function() onChange,
  })  : _audio = audio,
        _settings = settings,
        _onChange = onChange;

  final AudioEngine _audio;
  final SynthSettings Function() _settings;
  final void Function() _onChange;
  final math.Random _rng = math.Random();

  List<Note> _chord = const <Note>[];
  Timer? _timer;
  Duration? _interval;
  int _step = 0;
  Note? _current;

  /// The note the arpeggiator is currently sounding (for UI highlighting).
  Note? get current => _current;

  /// Updates the chord to arpeggiate. An empty set stops the arpeggiator.
  void setChord(Set<Note> notes) {
    if (notes.isEmpty) {
      if (_chord.isNotEmpty || _timer != null) stop();
      return;
    }
    final List<Note> sorted = notes.toList(growable: false)
      ..sort((Note a, Note b) => a.midi.compareTo(b.midi));
    _chord = sorted;
    _ensureRunning();
  }

  void _ensureRunning() {
    final Duration want = arpStepDuration(_settings().bpm, _settings().arpRate);
    if (_timer != null && _interval == want) return;
    _timer?.cancel();
    _interval = want;
    _timer = Timer.periodic(want, (_) => _tick());
  }

  void _tick() {
    if (_chord.isEmpty) {
      stop();
      return;
    }
    // Release the previous step's note before starting the next.
    _releaseCurrent();

    final int idx =
        arpPatternIndex(_settings().arpPattern, _step, _chord.length, _rng);
    _step++;
    final Note note = _chord[idx.clamp(0, _chord.length - 1)];
    _current = note;
    _audio.noteOn(note, velocity: 0.9);
    _onChange();

    // Gate: release partway through the step so notes are distinct.
    final Duration gate = Duration(
        milliseconds:
            (_interval!.inMilliseconds * _settings().arpGate.clamp(0.05, 0.95))
                .round());
    Timer(gate, () {
      if (_current == note) {
        _audio.noteOff(note);
        _current = null;
        _onChange();
      }
    });
  }

  void _releaseCurrent() {
    final Note? c = _current;
    if (c != null) {
      _audio.noteOff(c);
      _current = null;
    }
  }

  /// Stops the clock and releases any sounding note.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _interval = null;
    _step = 0;
    _chord = const <Note>[];
    if (_current != null) {
      _releaseCurrent();
      _onChange();
    }
  }

  void dispose() => stop();
}
