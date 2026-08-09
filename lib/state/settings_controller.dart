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

  /// Like [_update], but for edits to a sound parameter that a [SoundPreset]
  /// controls: it drops the selection back to [SoundPreset.custom] so the UI no
  /// longer claims a preset is active once the user hand-tunes the sound.
  Future<void> _updateSound(SynthSettings next) =>
      _update(next.copyWith(preset: SoundPreset.custom));

  /// Applies a curated sound preset (tone + musical settings). See
  /// [applySoundPreset]; performance/layout settings are preserved.
  void applyPreset(SoundPreset preset) =>
      _update(applySoundPreset(_settings, preset));

  // Convenience mutators -------------------------------------------------------

  void setEngine(SoundEngine engine) =>
      _updateSound(_settings.copyWith(engine: engine));
  void setWave(SynthWave wave) => _updateSound(_settings.copyWith(wave: wave));
  void setAdsr(Adsr adsr) => _updateSound(_settings.copyWith(adsr: adsr));
  void setUnison(double v) =>
      _updateSound(_settings.copyWith(unison: v.clamp(0.0, 1.0)));
  void setOctaveShift(int shift) =>
      _update(_settings.copyWith(octaveShift: shift.clamp(-3, 3)));
  void setReverb(double v) => _updateSound(_settings.copyWith(reverb: v));
  void setEcho(double v) => _updateSound(_settings.copyWith(echo: v));
  void setDistortion(double v) =>
      _updateSound(_settings.copyWith(distortion: v.clamp(0.0, 1.0)));
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

  // Expressive control -------------------------------------------------------
  void setVelocityEnabled(bool v) =>
      _update(_settings.copyWith(velocityEnabled: v));
  void setFilterEnabled(bool v) =>
      _updateSound(_settings.copyWith(filterEnabled: v));
  void setFilterCutoff(double v) =>
      _updateSound(_settings.copyWith(filterCutoff: v.clamp(0.0, 1.0)));
  void setFilterResonance(double v) =>
      _updateSound(_settings.copyWith(filterResonance: v.clamp(0.0, 1.0)));
  void setLfoEnabled(bool v) => _updateSound(_settings.copyWith(lfoEnabled: v));
  void setLfoRateHz(double v) =>
      _updateSound(_settings.copyWith(lfoRateHz: v.clamp(0.05, 20.0)));
  void setLfoDepth(double v) =>
      _updateSound(_settings.copyWith(lfoDepth: v.clamp(0.0, 1.0)));
  void setPinchModEnabled(bool v) =>
      _update(_settings.copyWith(pinchModEnabled: v));
  void setPanEnabled(bool v) => _update(_settings.copyWith(panEnabled: v));
  void setDepthModEnabled(bool v) =>
      _update(_settings.copyWith(depthModEnabled: v));
  void setDepthTarget(DepthTarget t) =>
      _update(_settings.copyWith(depthTarget: t));

  // Scale lock ---------------------------------------------------------------
  void setScaleName(String s) => _updateSound(_settings.copyWith(scaleName: s));
  void setKeyRoot(int r) =>
      _updateSound(_settings.copyWith(keyRoot: ((r % 12) + 12) % 12));

  // Arpeggiator --------------------------------------------------------------
  void setArpEnabled(bool v) => _updateSound(_settings.copyWith(arpEnabled: v));
  void setArpPattern(ArpPattern p) =>
      _updateSound(_settings.copyWith(arpPattern: p));
  void setArpRate(ArpRate r) => _updateSound(_settings.copyWith(arpRate: r));
  void setBpm(double v) =>
      _updateSound(_settings.copyWith(bpm: v.clamp(20.0, 300.0)));
  void setArpGate(double v) =>
      _updateSound(_settings.copyWith(arpGate: v.clamp(0.05, 0.95)));

  // Visualizer ---------------------------------------------------------------
  void setVisualizerEnabled(bool v) =>
      _update(_settings.copyWith(visualizerEnabled: v));

  // Face control -------------------------------------------------------------
  void setFaceControlEnabled(bool v) =>
      _update(_settings.copyWith(faceControlEnabled: v));
  void setFaceSignal(FaceSignal s) =>
      _update(_settings.copyWith(faceSignal: s));
  void setFaceTarget(FaceTarget t) =>
      _update(_settings.copyWith(faceTarget: t));
}
