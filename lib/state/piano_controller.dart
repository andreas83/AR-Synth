import 'package:flutter/foundation.dart';

import '../models/music.dart';
import '../services/audio_engine.dart';
import '../services/gesture_mapper.dart';
import 'settings_controller.dart';

/// Central note router. Both the touch keyboard and the gesture pipeline feed
/// notes here; it drives the [AudioEngine] and exposes the set of currently
/// sounding notes for UI highlighting.
class PianoController extends ChangeNotifier {
  PianoController(this._audio, this._settings);

  final AudioEngine _audio;
  final SettingsController _settings;

  final Set<Note> _touchHeld = <Note>{};
  final Set<Note> _gestureHeld = <Note>{};
  bool _liveVolumeAdjusted = false;

  /// All notes currently sounding (touch ∪ gesture), for keyboard highlighting.
  Set<Note> get activeNotes => <Note>{..._touchHeld, ..._gestureHeld};

  bool isActive(Note note) =>
      _touchHeld.contains(note) || _gestureHeld.contains(note);

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
    final Set<Note> next = output.heldNotes;

    final Set<Note> toOff = _gestureHeld.difference(next);
    final Set<Note> toOn = next.difference(_gestureHeld);
    for (final Note n in toOff) {
      _audio.noteOff(n);
    }
    for (final Note n in toOn) {
      _audio.noteOn(n);
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

    if (toOff.isNotEmpty || toOn.isNotEmpty) {
      _gestureHeld
        ..clear()
        ..addAll(next);
      notifyListeners();
    } else {
      _gestureHeld
        ..clear()
        ..addAll(next);
    }
  }

  /// Clears all gesture notes (e.g. when leaving the gesture screen).
  void clearGesture() {
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
  }

  @override
  void dispose() {
    _audio.allNotesOff();
    super.dispose();
  }
}
