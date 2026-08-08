import 'package:flutter/foundation.dart';

import '../models/face_data.dart';
import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/audio_engine.dart';
import '../services/gesture_mapper.dart';
import 'arpeggiator.dart';
import 'settings_controller.dart';

/// Central note router. Both the touch keyboard and the gesture pipeline feed
/// notes here; it drives the [AudioEngine] and exposes the set of currently
/// sounding notes for UI highlighting.
class PianoController extends ChangeNotifier {
  PianoController(this._audio, this._settings) {
    _arp = Arpeggiator(
      audio: _audio,
      settings: () => _settings.settings,
      onChange: notifyListeners,
    );
  }

  final AudioEngine _audio;
  final SettingsController _settings;
  late final Arpeggiator _arp;

  final Set<Note> _touchHeld = <Note>{};
  final Set<Note> _gestureHeld = <Note>{};
  bool _liveVolumeAdjusted = false;
  bool _cutoffAdjusted = false;
  bool _faceAdjusted = false;

  /// All notes currently sounding (touch ∪ gesture ∪ arp), for highlighting.
  Set<Note> get activeNotes {
    final Set<Note> notes = <Note>{..._touchHeld, ..._gestureHeld};
    final Note? arpNote = _arp.current;
    if (arpNote != null) notes.add(arpNote);
    return notes;
  }

  bool isActive(Note note) =>
      _touchHeld.contains(note) ||
      _gestureHeld.contains(note) ||
      _arp.current == note;

  // -- Touch input ------------------------------------------------------------

  void pressNote(Note note) {
    if (_touchHeld.add(note)) {
      _audio.noteOn(note);
      notifyListeners();
    }
  }

  void releaseNote(Note note) {
    if (_touchHeld.remove(note)) {
      _audio.noteOff(note);
      notifyListeners();
    }
  }

  void releaseAllTouch() {
    if (_touchHeld.isEmpty) return;
    for (final Note n in _touchHeld.toList(growable: false)) {
      _audio.noteOff(n);
    }
    _touchHeld.clear();
    notifyListeners();
  }

  // -- Gesture input ----------------------------------------------------------

  /// Applies one frame of gesture output: diffs held notes and (for theremin)
  /// updates live volume.
  void applyGesture(GestureOutput output) {
    // Handpan mode is one-shot percussion: strike each freshly-entered tone
    // field and let the handpan envelope ring it out (no sustained voices, no
    // note-off). `heldNotes` here is just the touched set, used for highlight.
    if (_settings.settings.gestureMode == GestureMode.handpan) {
      for (final MapEntry<Note, double> e in output.velocities.entries) {
        _audio.strike(e.key,
            velocity: e.value, envelope: kHandpanEnvelope);
      }
      if (!setEquals(_gestureHeld, output.heldNotes)) {
        _gestureHeld
          ..clear()
          ..addAll(output.heldNotes);
        notifyListeners();
      }
      return;
    }

    final Set<Note> next = output.heldNotes;
    bool changed = false;

    if (_settings.settings.arpEnabled) {
      // The arpeggiator drives note-on/off from the held chord on its own clock.
      if (_gestureHeld.isNotEmpty) {
        for (final Note n in _gestureHeld.toList(growable: false)) {
          _audio.noteOff(n);
        }
        _gestureHeld.clear();
        changed = true;
      }
      _arp.setChord(next);
    } else {
      _arp.setChord(const <Note>{});
      final Set<Note> toOff = _gestureHeld.difference(next);
      final Set<Note> toOn = next.difference(_gestureHeld);
      for (final Note n in toOff) {
        _audio.noteOff(n);
      }
      for (final Note n in toOn) {
        _audio.noteOn(n, velocity: output.velocities[n] ?? 1.0);
      }
      if (toOff.isNotEmpty || toOn.isNotEmpty) changed = true;
      _gestureHeld
        ..clear()
        ..addAll(next);
    }

    // Live volume for theremin mode; restore master when it stops.
    final double master = _settings.settings.masterVolume;
    if (output.thereminVolume != null) {
      _audio.setLiveMasterVolume(master * output.thereminVolume!);
      _liveVolumeAdjusted = true;
    } else if (_liveVolumeAdjusted) {
      _audio.setLiveMasterVolume(master);
      _liveVolumeAdjusted = false;
    }

    // Live filter cutoff from the pinch-to-modulate gesture.
    if (output.pinchModulation != null) {
      _audio.setLiveCutoff(output.pinchModulation!);
      _cutoffAdjusted = true;
    } else if (_cutoffAdjusted) {
      _audio.clearLiveCutoff();
      _cutoffAdjusted = false;
    }

    if (changed) notifyListeners();
  }

  /// Applies one frame of face-expression modulation to the chosen target.
  /// Hand-driven live controls take precedence over the face for shared targets
  /// (pinch > face on the cutoff; theremin > face on the volume).
  void applyFaceModulation(FaceFrame frame) {
    final SynthSettings s = _settings.settings;
    if (!s.faceControlEnabled || !frame.present) {
      if (_faceAdjusted) {
        _clearFaceTarget(s.faceTarget);
        _faceAdjusted = false;
      }
      return;
    }
    final double? value = frame.signal(s.faceSignal);
    if (value == null) return;

    switch (s.faceTarget) {
      case FaceTarget.cutoff:
        if (_cutoffAdjusted) return; // pinch (hand) wins
        _audio.setLiveCutoff(value);
        _faceAdjusted = true;
      case FaceTarget.reverb:
        _audio.setLiveReverb(value);
        _faceAdjusted = true;
      case FaceTarget.volume:
        if (_liveVolumeAdjusted) return; // theremin wins
        _audio.setLiveMasterVolume(s.masterVolume * (0.15 + 0.85 * value));
        _faceAdjusted = true;
    }
  }

  void _clearFaceTarget(FaceTarget target) {
    switch (target) {
      case FaceTarget.cutoff:
        if (!_cutoffAdjusted) _audio.clearLiveCutoff();
      case FaceTarget.reverb:
        _audio.clearLiveReverb();
      case FaceTarget.volume:
        if (!_liveVolumeAdjusted) {
          _audio.setLiveMasterVolume(_settings.settings.masterVolume);
        }
    }
  }

  /// Clears all gesture notes (e.g. when leaving the gesture screen).
  void clearGesture() {
    _arp.stop();
    if (_gestureHeld.isNotEmpty) {
      for (final Note n in _gestureHeld.toList(growable: false)) {
        _audio.noteOff(n);
      }
      _gestureHeld.clear();
      notifyListeners();
    }
    if (_liveVolumeAdjusted) {
      _audio.setLiveMasterVolume(_settings.settings.masterVolume);
      _liveVolumeAdjusted = false;
    }
    if (_cutoffAdjusted) {
      _audio.clearLiveCutoff();
      _cutoffAdjusted = false;
    }
    if (_faceAdjusted) {
      _clearFaceTarget(_settings.settings.faceTarget);
      _faceAdjusted = false;
    }
  }

  @override
  void dispose() {
    _arp.dispose();
    _audio.allNotesOff();
    super.dispose();
  }
}
