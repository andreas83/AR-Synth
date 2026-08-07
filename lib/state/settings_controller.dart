import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/synth_settings.dart';
import '../services/audio_engine.dart';
import '../utils/constants.dart';

/// Holds [SynthSettings], persists them, and pushes relevant changes to the
/// [AudioEngine] so edits take effect live.
class SettingsController extends ChangeNotifier {
  SettingsController(this._audio);

  final AudioEngine _audio;
  SynthSettings _settings = const SynthSettings();
  SharedPreferences? _prefs;

  SynthSettings get settings => _settings;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final String? raw = _prefs?.getString(kSettingsPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        _settings = SynthSettings.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('SettingsController: load failed: $e');
    }
    await _audio.applySettings(_settings);
    notifyListeners();
  }

  Future<void> _update(SynthSettings next) async {
    _settings = next;
    notifyListeners();
    await _audio.applySettings(next);
    try {
      await _prefs?.setString(kSettingsPrefsKey, jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('SettingsController: save failed: $e');
    }
  }

  // Convenience mutators -------------------------------------------------------

  void setEngine(SoundEngine engine) => _update(_settings.copyWith(engine: engine));
  void setWave(SynthWave wave) => _update(_settings.copyWith(wave: wave));
  void setAdsr(Adsr adsr) => _update(_settings.copyWith(adsr: adsr));
  void setOctaveShift(int shift) =>
      _update(_settings.copyWith(octaveShift: shift.clamp(-3, 3)));
  void setReverb(double v) => _update(_settings.copyWith(reverb: v));
  void setEcho(double v) => _update(_settings.copyWith(echo: v));
  void setMasterVolume(double v) => _update(_settings.copyWith(masterVolume: v));
  void setGestureMode(GestureMode m) =>
      _update(_settings.copyWith(gestureMode: m));
  void setGestureSensitivity(double v) =>
      _update(_settings.copyWith(gestureSensitivity: v));
  void setThereminScale(String s) =>
      _update(_settings.copyWith(thereminScale: s));
  void setStartOctave(int o) =>
      _update(_settings.copyWith(startOctave: o.clamp(1, 6)));
  void setOctaves(int n) => _update(_settings.copyWith(octaves: n.clamp(1, 3)));

  /// Cycle the camera preview rotation (0→1→2→3→0). Persisted, so once the
  /// user gets it upright it stays that way on their device.
  void rotateCameraPreview() => _update(
      _settings.copyWith(cameraQuarterTurns: (_settings.cameraQuarterTurns + 1) % 4));
}
