import 'face_data.dart';

export 'face_data.dart' show FaceSignal, FaceSignalLabel;

/// Which synth parameter a face expression modulates.
enum FaceTarget { cutoff, reverb, volume, pan }

extension FaceTargetLabel on FaceTarget {
  String get label => switch (this) {
        FaceTarget.cutoff => 'Filter cutoff',
        FaceTarget.reverb => 'Reverb',
        FaceTarget.volume => 'Volume',
        FaceTarget.pan => 'Pan (L/R)',
      };
}

/// Which synth parameter the hand-depth (push/pull) gesture modulates.
enum DepthTarget { cutoff, volume }

extension DepthTargetLabel on DepthTarget {
  String get label => switch (this) {
        DepthTarget.cutoff => 'Filter cutoff',
        DepthTarget.volume => 'Volume',
      };
}

/// Which sound source the audio engine uses to render notes.
enum SoundEngine {
  /// Real-time oscillator synthesis (SoLoud `loadWaveform`).
  synth,

  /// Pitch-shifted piano samples loaded from `assets/samples/`.
  sample,
}

/// Oscillator waveform for [SoundEngine.synth].
enum SynthWave { sine, square, saw, triangle, bounce, jaws }

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

  /// Play with your face: tilt your head to choose pitch, open your mouth to
  /// sound the note. Uses the front-camera face tracker.
  face,

  /// Sweep a fingertip across the scale lanes to pluck notes like a harp —
  /// moving between lanes releases the old note and sounds the next.
  strum,
}

extension GestureModeLabel on GestureMode {
  String get label => switch (this) {
        GestureMode.airPiano => 'Air Piano',
        GestureMode.discretePoses => 'Hand Poses',
        GestureMode.theremin => 'Theremin',
        GestureMode.face => 'Face',
        GestureMode.strum => 'Strum / Harp',
      };

  String get description => switch (this) {
        GestureMode.airPiano =>
          'Move your hand over the keyboard and tap fingers down to play.',
        GestureMode.discretePoses =>
          'Hold a pose — fist, point, peace, open hand, thumbs up — to trigger notes.',
        GestureMode.theremin =>
          'Raise/lower one hand for pitch, the other for volume.',
        GestureMode.face =>
          'Tilt your head to choose pitch, open your mouth to play the note.',
        GestureMode.strum =>
          'Sweep a hand across the lanes to strum notes from the scale.',
      };
}

/// One entry in the in-app gesture guide: a short [label] and its [detail].
class GestureTip {
  const GestureTip(this.label, this.detail);

  final String label;
  final String detail;
}

/// Human-facing "how to play" content for each gesture mode, surfaced as an
/// always-visible legend plus a tappable guide sheet on the camera screen.
extension GestureGuide on GestureMode {
  /// A single compact line shown as the always-on legend for this mode.
  String get inlineHint => switch (this) {
        GestureMode.airPiano =>
          'Move your hand over the lanes, then tap a fingertip below the line.',
        GestureMode.discretePoses =>
          'Hold a pose: point, peace, open hand, thumbs-up or fist.',
        GestureMode.theremin =>
          'Right-hand height = pitch · left-hand height = volume.',
        GestureMode.face =>
          'Tilt your head for pitch · open your mouth to play.',
        GestureMode.strum =>
          'Sweep a fingertip across the lanes to pluck the scale.',
      };

  /// The per-gesture breakdown shown in the guide sheet.
  List<GestureTip> get tips => switch (this) {
        GestureMode.airPiano => const <GestureTip>[
            GestureTip('Hover & tap',
                'Move your fingers over the lanes, then push a fingertip below the press line to play that note.'),
            GestureTip('Play harder',
                'With velocity on, a faster downward tap plays louder.'),
            GestureTip('Pinch → filter',
                'With pinch-to-cutoff on, your free hand’s pinch opens and closes the filter.'),
          ],
        GestureMode.discretePoses => const <GestureTip>[
            GestureTip(
                'Point', 'Index finger only — plays the root note.'),
            GestureTip('Peace',
                'Index + middle — plays the root and the fifth.'),
            GestureTip('Open hand',
                'All fingers spread — plays a major triad.'),
            GestureTip('Thumbs up',
                'Thumb only — plays the V (dominant) chord.'),
            GestureTip('Fist', 'All fingers curled — silence.'),
          ],
        GestureMode.theremin => const <GestureTip>[
            GestureTip('Pitch hand',
                'Your right hand’s height sweeps the pitch, snapped to the theremin scale, across five octaves (C2–C7).'),
            GestureTip('Volume hand',
                'Your left hand’s height sets the volume. With one hand raised it plays at full volume.'),
          ],
        GestureMode.face => const <GestureTip>[
            GestureTip('Head tilt',
                'Tilt your head left/right to choose the pitch, snapped to your scale.'),
            GestureTip('Open mouth',
                'Open your mouth to sound the note — wider is louder.'),
          ],
        GestureMode.strum => const <GestureTip>[
            GestureTip('Sweep to play',
                'Move a fingertip across the lanes; each lane plucks the next note of your scale.'),
            GestureTip('Glissando',
                'Sweeping quickly runs up or down the scale like a harp glissando.'),
            GestureTip('Arpeggiate',
                'Turn on the arpeggiator to spread the held note into a rhythmic pattern.'),
          ],
      };
}

extension SynthWaveLabel on SynthWave {
  String get label => switch (this) {
        SynthWave.sine => 'Sine',
        SynthWave.square => 'Square',
        SynthWave.saw => 'Saw',
        SynthWave.triangle => 'Triangle',
        SynthWave.bounce => 'Bounce',
        SynthWave.jaws => 'Jaws',
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

/// Arpeggiator note-step patterns.
enum ArpPattern { up, down, updown, random }

extension ArpPatternLabel on ArpPattern {
  String get label => switch (this) {
        ArpPattern.up => 'Up',
        ArpPattern.down => 'Down',
        ArpPattern.updown => 'Up/Down',
        ArpPattern.random => 'Random',
      };
}

/// Arpeggiator step rate as a musical note division.
enum ArpRate { quarter, eighth, eighthTriplet, sixteenth }

extension ArpRateInfo on ArpRate {
  String get label => switch (this) {
        ArpRate.quarter => '1/4',
        ArpRate.eighth => '1/8',
        ArpRate.eighthTriplet => '1/8T',
        ArpRate.sixteenth => '1/16',
      };

  /// Fraction of a quarter-note beat that one arp step lasts.
  double get beatFraction => switch (this) {
        ArpRate.quarter => 1.0,
        ArpRate.eighth => 0.5,
        ArpRate.eighthTriplet => 1.0 / 3.0,
        ArpRate.sixteenth => 0.25,
      };
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
    this.cameraQuarterTurns = 1,
    // -- New expressive / creative features (all default to prior behavior) --
    this.velocityEnabled = true,
    this.filterEnabled = false,
    this.filterCutoff = 1.0,
    this.filterResonance = 0.1,
    this.lfoEnabled = false,
    this.lfoRateHz = 2.0,
    this.lfoDepth = 0.0,
    this.pinchModEnabled = false,
    this.scaleName = 'Major',
    this.keyRoot = 0,
    this.arpEnabled = false,
    this.arpPattern = ArpPattern.up,
    this.arpRate = ArpRate.eighth,
    this.bpm = 120.0,
    this.arpGate = 0.5,
    this.visualizerEnabled = true,
    this.faceControlEnabled = false,
    this.faceSignal = FaceSignal.mouthOpen,
    this.faceTarget = FaceTarget.cutoff,
    this.distortion = 0.0,
    this.panEnabled = false,
    this.depthModEnabled = false,
    this.depthTarget = DepthTarget.cutoff,
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

  /// Quarter-turns (0..3) applied to the camera preview + overlay so it shows
  /// upright in portrait. Device-dependent; the user can cycle it with the
  /// rotate button on the gesture screen.
  final int cameraQuarterTurns;

  /// When true, Air-Piano note loudness follows how fast the finger taps down.
  final bool velocityEnabled;

  /// Resonant low-pass filter enable + normalized cutoff (0=dark, 1=open) and
  /// resonance (0..1, mapped to the filter's Q range).
  final bool filterEnabled;
  final double filterCutoff;
  final double filterResonance;

  /// Low-frequency oscillator that sweeps the filter cutoff.
  final bool lfoEnabled;
  final double lfoRateHz;
  final double lfoDepth;

  /// When true, the non-playing hand's pinch distance modulates the filter
  /// cutoff live (a hands-in-the-air "wah").
  final bool pinchModEnabled;

  /// Scale + key root (0=C..11=B) that Air-Piano lanes are locked to.
  /// The defaults ('Major' / C) reproduce the original white-keys layout.
  final String scaleName;
  final int keyRoot;

  /// Arpeggiator: spread held chords/poses into a rhythmic sequence.
  final bool arpEnabled;
  final ArpPattern arpPattern;
  final ArpRate arpRate;
  final double bpm;

  /// Fraction of each step the arp note sounds for (0..1).
  final double arpGate;

  /// Reactive note-ripple visualizer on the gesture screen.
  final bool visualizerEnabled;

  /// Face-expression modulation: drive [faceTarget] from [faceSignal].
  final bool faceControlEnabled;
  final FaceSignal faceSignal;
  final FaceTarget faceTarget;

  /// Global wave-shaper distortion / drive, 0..1 (0 = clean).
  final double distortion;

  /// When true, a playing hand's horizontal position pans the mix left/right.
  final bool panEnabled;

  /// When true, pushing a hand toward the camera modulates [depthTarget] live.
  final bool depthModEnabled;
  final DepthTarget depthTarget;

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
    int? cameraQuarterTurns,
    bool? velocityEnabled,
    bool? filterEnabled,
    double? filterCutoff,
    double? filterResonance,
    bool? lfoEnabled,
    double? lfoRateHz,
    double? lfoDepth,
    bool? pinchModEnabled,
    String? scaleName,
    int? keyRoot,
    bool? arpEnabled,
    ArpPattern? arpPattern,
    ArpRate? arpRate,
    double? bpm,
    double? arpGate,
    bool? visualizerEnabled,
    bool? faceControlEnabled,
    FaceSignal? faceSignal,
    FaceTarget? faceTarget,
    double? distortion,
    bool? panEnabled,
    bool? depthModEnabled,
    DepthTarget? depthTarget,
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
      cameraQuarterTurns: cameraQuarterTurns ?? this.cameraQuarterTurns,
      velocityEnabled: velocityEnabled ?? this.velocityEnabled,
      filterEnabled: filterEnabled ?? this.filterEnabled,
      filterCutoff: filterCutoff ?? this.filterCutoff,
      filterResonance: filterResonance ?? this.filterResonance,
      lfoEnabled: lfoEnabled ?? this.lfoEnabled,
      lfoRateHz: lfoRateHz ?? this.lfoRateHz,
      lfoDepth: lfoDepth ?? this.lfoDepth,
      pinchModEnabled: pinchModEnabled ?? this.pinchModEnabled,
      scaleName: scaleName ?? this.scaleName,
      keyRoot: keyRoot ?? this.keyRoot,
      arpEnabled: arpEnabled ?? this.arpEnabled,
      arpPattern: arpPattern ?? this.arpPattern,
      arpRate: arpRate ?? this.arpRate,
      bpm: bpm ?? this.bpm,
      arpGate: arpGate ?? this.arpGate,
      visualizerEnabled: visualizerEnabled ?? this.visualizerEnabled,
      faceControlEnabled: faceControlEnabled ?? this.faceControlEnabled,
      faceSignal: faceSignal ?? this.faceSignal,
      faceTarget: faceTarget ?? this.faceTarget,
      distortion: distortion ?? this.distortion,
      panEnabled: panEnabled ?? this.panEnabled,
      depthModEnabled: depthModEnabled ?? this.depthModEnabled,
      depthTarget: depthTarget ?? this.depthTarget,
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
        'cameraQuarterTurns': cameraQuarterTurns,
        'velocityEnabled': velocityEnabled,
        'filterEnabled': filterEnabled,
        'filterCutoff': filterCutoff,
        'filterResonance': filterResonance,
        'lfoEnabled': lfoEnabled,
        'lfoRateHz': lfoRateHz,
        'lfoDepth': lfoDepth,
        'pinchModEnabled': pinchModEnabled,
        'scaleName': scaleName,
        'keyRoot': keyRoot,
        'arpEnabled': arpEnabled,
        'arpPattern': arpPattern.name,
        'arpRate': arpRate.name,
        'bpm': bpm,
        'arpGate': arpGate,
        'visualizerEnabled': visualizerEnabled,
        'faceControlEnabled': faceControlEnabled,
        'faceSignal': faceSignal.name,
        'faceTarget': faceTarget.name,
        'distortion': distortion,
        'panEnabled': panEnabled,
        'depthModEnabled': depthModEnabled,
        'depthTarget': depthTarget.name,
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
      cameraQuarterTurns: (json['cameraQuarterTurns'] as num?)?.toInt() ?? 1,
      velocityEnabled: json['velocityEnabled'] as bool? ?? true,
      filterEnabled: json['filterEnabled'] as bool? ?? false,
      filterCutoff: (json['filterCutoff'] as num?)?.toDouble() ?? 1.0,
      filterResonance: (json['filterResonance'] as num?)?.toDouble() ?? 0.1,
      lfoEnabled: json['lfoEnabled'] as bool? ?? false,
      lfoRateHz: (json['lfoRateHz'] as num?)?.toDouble() ?? 2.0,
      lfoDepth: (json['lfoDepth'] as num?)?.toDouble() ?? 0.0,
      pinchModEnabled: json['pinchModEnabled'] as bool? ?? false,
      scaleName: json['scaleName'] as String? ?? 'Major',
      keyRoot: (json['keyRoot'] as num?)?.toInt() ?? 0,
      arpEnabled: json['arpEnabled'] as bool? ?? false,
      arpPattern: pick(ArpPattern.up,
          () => ArpPattern.values.byName(json['arpPattern'] as String)),
      arpRate: pick(ArpRate.eighth,
          () => ArpRate.values.byName(json['arpRate'] as String)),
      bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
      arpGate: (json['arpGate'] as num?)?.toDouble() ?? 0.5,
      visualizerEnabled: json['visualizerEnabled'] as bool? ?? true,
      faceControlEnabled: json['faceControlEnabled'] as bool? ?? false,
      faceSignal: pick(FaceSignal.mouthOpen,
          () => FaceSignal.values.byName(json['faceSignal'] as String)),
      faceTarget: pick(FaceTarget.cutoff,
          () => FaceTarget.values.byName(json['faceTarget'] as String)),
      distortion: (json['distortion'] as num?)?.toDouble() ?? 0.0,
      panEnabled: json['panEnabled'] as bool? ?? false,
      depthModEnabled: json['depthModEnabled'] as bool? ?? false,
      depthTarget: pick(DepthTarget.cutoff,
          () => DepthTarget.values.byName(json['depthTarget'] as String)),
    );
  }
}
