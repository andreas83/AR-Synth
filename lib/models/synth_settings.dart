/// Which sound source the audio engine uses to render notes.
enum SoundEngine {
  /// Real-time oscillator synthesis (SoLoud `loadWaveform`).
  synth,

  /// Pitch-shifted piano samples loaded from `assets/samples/`.
  sample,
}

/// Oscillator waveform for [SoundEngine.synth].
enum SynthWave { sine, square, saw, triangle }

/// How camera hand gestures are translated into notes.
enum GestureMode {
  /// Fingertips hover over the on-screen keyboard; a downward "tap" plays the
  /// key beneath the fingertip.
  airPiano,

  /// Recognised static hand poses (fist, point, peace, open hand, thumbs up)
  /// each trigger a preset note or chord.
  discretePoses,

  /// Dominant hand height sweeps pitch (optionally quantized); the other hand
  /// height controls volume. A theremin-style continuous instrument.
  theremin,
}

extension GestureModeLabel on GestureMode {
  String get label => switch (this) {
        GestureMode.airPiano => 'Air Piano',
        GestureMode.discretePoses => 'Hand Poses',
        GestureMode.theremin => 'Theremin',
      };

  String get description => switch (this) {
        GestureMode.airPiano =>
          'Move your hand over the keyboard and tap fingers down to play.',
        GestureMode.discretePoses =>
          'Hold a pose — fist, point, peace, open hand, thumbs up — to trigger notes.',
        GestureMode.theremin =>
          'Raise/lower one hand for pitch, the other for volume.',
      };
}

extension SynthWaveLabel on SynthWave {
  String get label => switch (this) {
        SynthWave.sine => 'Sine',
        SynthWave.square => 'Square',
        SynthWave.saw => 'Saw',
        SynthWave.triangle => 'Triangle',
      };
}

/// A simple attack/decay/sustain/release amplitude envelope (seconds + level).
class Adsr {
  const Adsr({
    this.attack = 0.01,
    this.decay = 0.12,
    this.sustain = 0.7,
    this.release = 0.25,
  });

  /// Time to reach full volume, in seconds.
  final double attack;

  /// Time to fall from full volume to [sustain], in seconds.
  final double decay;

  /// Sustained level, 0..1.
  final double sustain;

  /// Time to fade to silence after note-off, in seconds.
  final double release;

  Adsr copyWith({double? attack, double? decay, double? sustain, double? release}) {
    return Adsr(
      attack: attack ?? this.attack,
      decay: decay ?? this.decay,
      sustain: sustain ?? this.sustain,
      release: release ?? this.release,
    );
  }
}

/// All user-tunable settings, persisted between launches.
class SynthSettings {
  const SynthSettings({
    this.engine = SoundEngine.synth,
    this.wave = SynthWave.saw,
    this.adsr = const Adsr(),
    this.octaveShift = 0,
    this.reverb = 0.2,
    this.echo = 0.0,
    this.masterVolume = 0.8,
    this.gestureMode = GestureMode.airPiano,
    this.gestureSensitivity = 0.5,
    this.thereminScale = 'Pentatonic',
    this.startOctave = 4,
    this.octaves = 2,
  });

  final SoundEngine engine;
  final SynthWave wave;
  final Adsr adsr;

  /// Semitone transposition applied to every note (in whole octaves x12).
  final int octaveShift;

  /// Global reverb wet amount, 0..1.
  final double reverb;

  /// Global echo/delay wet amount, 0..1.
  final double echo;

  /// Master output volume, 0..1.
  final double masterVolume;

  final GestureMode gestureMode;

  /// 0..1 — how easily a gesture triggers a note (tap depth / hold time).
  final double gestureSensitivity;

  /// Scale name (see [kScales]) used to quantize theremin pitch.
  final String thereminScale;

  /// Lowest octave shown on the keyboard.
  final int startOctave;

  /// Number of octaves shown on the keyboard.
  final int octaves;

  SynthSettings copyWith({
    SoundEngine? engine,
    SynthWave? wave,
    Adsr? adsr,
    int? octaveShift,
    double? reverb,
    double? echo,
    double? masterVolume,
    GestureMode? gestureMode,
    double? gestureSensitivity,
    String? thereminScale,
    int? startOctave,
    int? octaves,
  }) {
    return SynthSettings(
      engine: engine ?? this.engine,
      wave: wave ?? this.wave,
      adsr: adsr ?? this.adsr,
      octaveShift: octaveShift ?? this.octaveShift,
      reverb: reverb ?? this.reverb,
      echo: echo ?? this.echo,
      masterVolume: masterVolume ?? this.masterVolume,
      gestureMode: gestureMode ?? this.gestureMode,
      gestureSensitivity: gestureSensitivity ?? this.gestureSensitivity,
      thereminScale: thereminScale ?? this.thereminScale,
      startOctave: startOctave ?? this.startOctave,
      octaves: octaves ?? this.octaves,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'engine': engine.name,
        'wave': wave.name,
        'attack': adsr.attack,
        'decay': adsr.decay,
        'sustain': adsr.sustain,
        'release': adsr.release,
        'octaveShift': octaveShift,
        'reverb': reverb,
        'echo': echo,
        'masterVolume': masterVolume,
        'gestureMode': gestureMode.name,
        'gestureSensitivity': gestureSensitivity,
        'thereminScale': thereminScale,
        'startOctave': startOctave,
        'octaves': octaves,
      };

  factory SynthSettings.fromJson(Map<String, dynamic> json) {
    T pick<T>(T fallback, T Function() read) {
      try {
        return read();
      } catch (_) {
        return fallback;
      }
    }

    return SynthSettings(
      engine: pick(SoundEngine.synth,
          () => SoundEngine.values.byName(json['engine'] as String)),
      wave: pick(
          SynthWave.saw, () => SynthWave.values.byName(json['wave'] as String)),
      adsr: Adsr(
        attack: (json['attack'] as num?)?.toDouble() ?? 0.01,
        decay: (json['decay'] as num?)?.toDouble() ?? 0.12,
        sustain: (json['sustain'] as num?)?.toDouble() ?? 0.7,
        release: (json['release'] as num?)?.toDouble() ?? 0.25,
      ),
      octaveShift: (json['octaveShift'] as num?)?.toInt() ?? 0,
      reverb: (json['reverb'] as num?)?.toDouble() ?? 0.2,
      echo: (json['echo'] as num?)?.toDouble() ?? 0.0,
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 0.8,
      gestureMode: pick(GestureMode.airPiano,
          () => GestureMode.values.byName(json['gestureMode'] as String)),
      gestureSensitivity:
          (json['gestureSensitivity'] as num?)?.toDouble() ?? 0.5,
      thereminScale: json['thereminScale'] as String? ?? 'Pentatonic',
      startOctave: (json['startOctave'] as num?)?.toInt() ?? 4,
      octaves: (json['octaves'] as num?)?.toInt() ?? 2,
    );
  }
}
