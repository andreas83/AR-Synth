import '../models/hand_data.dart';
import '../models/music.dart';
import '../models/synth_settings.dart';
import '../utils/finger_geometry.dart';

/// A fingertip cursor to visualise on top of the camera preview.
class FingerCursor {
  const FingerCursor({
    required this.x,
    required this.y,
    required this.colorIndex,
    this.note,
    this.pressing = false,
  });

  /// Normalized position (0..1) in display space.
  final double x;
  final double y;

  /// Index into `kFingerColors` (0=thumb .. 4=pinky).
  final int colorIndex;

  /// The note this fingertip is currently over (air-piano), if any.
  final Note? note;

  /// Whether the fingertip is currently pressing (past the press line).
  final bool pressing;
}

/// Result of mapping one [HandFrame] through the active [GestureMode].
class GestureOutput {
  const GestureOutput({
    this.heldNotes = const <Note>{},
    this.velocities = const <Note, double>{},
    this.cursors = const <FingerCursor>[],
    this.poses = const <HandPose>[],
    this.thereminVolume,
    this.pinchModulation,
    this.pressLineY,
    this.pitchHandY,
    this.volumeHandY,
  });

  /// Notes that should currently sound. The controller diffs successive sets
  /// to decide note-on / note-off.
  final Set<Note> heldNotes;

  /// Per-note attack velocity (0..1) for notes that turned on this frame.
  /// Notes absent from the map play at the default velocity.
  final Map<Note, double> velocities;

  /// Normalized 0..1 modulation from the non-playing hand's pinch (null when no
  /// modulator hand is present / pinch modulation is disabled).
  final double? pinchModulation;

  /// Fingertip cursors for the overlay.
  final List<FingerCursor> cursors;

  /// Recognised poses per hand (discrete mode), for on-screen feedback.
  final List<HandPose> poses;

  /// Live output volume 0..1 for theremin mode (null otherwise).
  final double? thereminVolume;

  /// Normalized y of the air-piano press line (for the overlay).
  final double? pressLineY;

  /// Normalized y of the theremin pitch hand / volume hand (for the overlay).
  final double? pitchHandY;
  final double? volumeHandY;

  static const GestureOutput empty = GestureOutput();
}

/// Translates hand landmarks into notes according to the selected gesture mode.
///
/// Holds a little per-mode state (pose de-bounce) so it must be reused across
/// frames and [reset] when the mode changes.
class GestureMapper {
  // Discrete-pose de-bounce, per detected hand slot.
  final List<HandPose> _stablePose = <HandPose>[HandPose.none, HandPose.none];
  final List<int> _poseStreak = <int>[0, 0];

  // Air-piano velocity tracking: last-seen fingertip y per [handSlot][finger].
  final List<List<double?>> _prevTipY =
      List<List<double?>>.generate(2, (_) => List<double?>.filled(5, null));
  int? _prevMicros;

  void reset() {
    for (int i = 0; i < _stablePose.length; i++) {
      _stablePose[i] = HandPose.none;
      _poseStreak[i] = 0;
    }
    for (final List<double?> row in _prevTipY) {
      for (int i = 0; i < row.length; i++) {
        row[i] = null;
      }
    }
    _prevMicros = null;
  }

  /// Maps a fingertip's downward speed (normalized units per second, where y
  /// grows downward) to an attack velocity in [0.05, 1.0]. Pure + testable.
  static double speedToVelocity(double downwardSpeed) {
    const double vMin = 0.15; // gentle press
    const double vMax = 2.5; // fast jab
    final double t = (downwardSpeed - vMin) / (vMax - vMin);
    return t.clamp(0.05, 1.0);
  }

  /// The playable Air-Piano lanes for the given settings: notes in the chosen
  /// scale + key across the keyboard span. With the defaults ('Major' / C) this
  /// equals the white keys, matching the original behavior. Pure + testable.
  static List<Note> airPianoLanes(SynthSettings settings) {
    final List<Note> keyboard = buildKeyboard(
        startOctave: settings.startOctave, octaves: settings.octaves);
    final List<int> scale =
        kScales[settings.scaleName] ?? kScales['Chromatic']!;
    final int root = ((settings.keyRoot % 12) + 12) % 12;
    return keyboard
        .where((Note n) =>
            quantizeToScale(n.midi, scale, rootPitchClass: root) == n.midi)
        .toList(growable: false);
  }

  /// Detected hands sorted left→right for stable per-slot state.
  static List<Hand> _sortedHands(HandFrame frame) =>
      List<Hand>.of(frame.hands)
        ..sort((Hand a, Hand b) => a[kWrist].x.compareTo(b[kWrist].x));

  GestureOutput map(HandFrame frame, SynthSettings settings) {
    if (!frame.hasHands) {
      reset();
      return GestureOutput.empty;
    }
    return switch (settings.gestureMode) {
      GestureMode.airPiano => _mapAirPiano(frame, settings),
      GestureMode.discretePoses => _mapDiscrete(frame, settings),
      GestureMode.theremin => _mapTheremin(frame, settings),
    };
  }

  // -- Air piano --------------------------------------------------------------

  GestureOutput _mapAirPiano(HandFrame frame, SynthSettings settings) {
    final List<Note> lanes = airPianoLanes(settings);
    if (lanes.isEmpty) return GestureOutput.empty;

    // Higher sensitivity raises the press line (easier to trigger).
    final double pressLineY = 0.75 - settings.gestureSensitivity * 0.35;

    final Set<Note> held = <Note>{};
    final Map<Note, double> velocities = <Note, double>{};
    final List<FingerCursor> cursors = <FingerCursor>[];

    // Stable left→right ordering so per-slot velocity state is meaningful.
    final List<Hand> hands = _sortedHands(frame);
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final double dt =
        _prevMicros == null ? 0.0 : (nowMicros - _prevMicros!) / 1e6;

    final List<int> pressingCount = <int>[0, 0];

    for (int slot = 0; slot < hands.length && slot < 2; slot++) {
      final Hand hand = hands[slot];
      if (!hand.isValid) continue;
      // Index, middle, ring, pinky act as the "keys"; thumb is skipped.
      for (int finger = 1; finger < 5; finger++) {
        if (!FingerGeometry.isFingerExtended(hand, finger)) {
          _prevTipY[slot][finger] = null; // reset when the finger retracts
          continue;
        }
        final HandLandmark tip = FingerGeometry.tip(hand, finger);
        final int lane =
            (tip.x * lanes.length).floor().clamp(0, lanes.length - 1);
        final Note note = lanes[lane];
        final bool pressing = tip.y >= pressLineY;
        final double? prevY = _prevTipY[slot][finger];
        final bool wasPressing = prevY != null && prevY >= pressLineY;

        if (pressing) {
          held.add(note);
          pressingCount[slot]++;
          if (!wasPressing) {
            // Note-on this frame — derive velocity from downward speed.
            double v = 1.0;
            if (settings.velocityEnabled) {
              v = (dt > 0 && prevY != null)
                  ? speedToVelocity((tip.y - prevY) / dt)
                  : 0.7; // no prior sample: medium hit
            }
            velocities[note] = v;
          }
        }
        cursors.add(FingerCursor(
          x: tip.x,
          y: tip.y,
          colorIndex: finger,
          note: note,
          pressing: pressing,
        ));
        _prevTipY[slot][finger] = tip.y;
      }
    }

    _prevMicros = nowMicros;

    // Pinch-to-modulate: the first non-playing hand's pinch drives the filter.
    double? pinchMod;
    if (settings.pinchModEnabled) {
      for (int slot = 0; slot < hands.length && slot < 2; slot++) {
        if (pressingCount[slot] != 0 || !hands[slot].isValid) continue;
        final double pd = FingerGeometry.pinchDistance(hands[slot]);
        // Tight pinch (~0.1) => dark; open (~0.8) => bright.
        pinchMod = ((pd - 0.1) / (0.8 - 0.1)).clamp(0.0, 1.0);
        final HandLandmark thumb = hands[slot][kThumbTip];
        final HandLandmark idx = hands[slot][kIndexTip];
        cursors.add(FingerCursor(
          x: (thumb.x + idx.x) / 2,
          y: (thumb.y + idx.y) / 2,
          colorIndex: 0,
        ));
        break;
      }
    }

    return GestureOutput(
      heldNotes: held,
      velocities: velocities,
      cursors: cursors,
      pressLineY: pressLineY,
      pinchModulation: pinchMod,
    );
  }

  // -- Discrete poses ---------------------------------------------------------

  GestureOutput _mapDiscrete(HandFrame frame, SynthSettings settings) {
    final int rootMidi = (settings.startOctave + 1) * 12; // C of start octave.
    // Higher sensitivity -> shorter hold required to lock a pose.
    final int required = (3 - settings.gestureSensitivity * 2).round().clamp(1, 3);

    final Set<Note> held = <Note>{};
    final List<HandPose> poses = <HandPose>[];
    final List<FingerCursor> cursors = <FingerCursor>[];

    for (int i = 0; i < frame.hands.length && i < _stablePose.length; i++) {
      final Hand hand = frame.hands[i];
      final HandPose raw = classifyPose(hand);
      if (raw == _stablePose[i]) {
        _poseStreak[i] = (_poseStreak[i] + 1).clamp(0, 99);
      } else {
        _stablePose[i] = raw;
        _poseStreak[i] = 1;
      }
      final HandPose locked =
          _poseStreak[i] >= required ? _stablePose[i] : HandPose.none;
      poses.add(locked);
      held.addAll(_poseToNotes(locked, rootMidi));

      // Show the index fingertip as a cursor for feedback.
      final HandLandmark tip = hand[kIndexTip];
      cursors.add(FingerCursor(x: tip.x, y: tip.y, colorIndex: 1));
    }

    return GestureOutput(heldNotes: held, poses: poses, cursors: cursors);
  }

  Set<Note> _poseToNotes(HandPose pose, int root) {
    switch (pose) {
      case HandPose.point:
        return <Note>{Note(root)}; // single root
      case HandPose.peace:
        return <Note>{Note(root), Note(root + 7)}; // root + fifth
      case HandPose.openHand:
        return <Note>{Note(root), Note(root + 4), Note(root + 7)}; // major triad
      case HandPose.thumbsUp:
        return <Note>{Note(root + 7), Note(root + 11), Note(root + 14)}; // V chord
      case HandPose.fist:
      case HandPose.none:
        return const <Note>{};
    }
  }

  // -- Theremin ---------------------------------------------------------------

  GestureOutput _mapTheremin(HandFrame frame, SynthSettings settings) {
    const int midiLow = 48; // C3
    const int midiHigh = 84; // C6
    final List<int> scale = kScales[settings.thereminScale] ?? kScales['Chromatic']!;

    // Sort hands left→right; left hand controls volume, right controls pitch.
    final List<Hand> hands = List<Hand>.of(frame.hands)
      ..sort((Hand a, Hand b) => a[kWrist].x.compareTo(b[kWrist].x));

    Hand pitchHand;
    double volume;
    double? volumeHandY;
    if (hands.length >= 2) {
      final Hand volumeHand = hands.first;
      pitchHand = hands.last;
      volumeHandY = volumeHand[kWrist].y;
      volume = (1.0 - volumeHandY).clamp(0.0, 1.0);
    } else {
      pitchHand = hands.first;
      volume = 0.85; // single-hand play stays audible
    }

    final double py = pitchHand[kIndexTip].y.clamp(0.0, 1.0);
    // Higher hand (smaller y) => higher pitch.
    final int rawMidi = (midiHigh - (py * (midiHigh - midiLow))).round();
    final int midi = quantizeToScale(rawMidi, scale, rootPitchClass: 0);

    return GestureOutput(
      heldNotes: <Note>{Note(midi)},
      thereminVolume: volume,
      pitchHandY: py,
      volumeHandY: volumeHandY,
      cursors: <FingerCursor>[
        FingerCursor(x: pitchHand[kIndexTip].x, y: py, colorIndex: 1, note: Note(midi)),
        if (volumeHandY != null)
          FingerCursor(x: hands.first[kWrist].x, y: volumeHandY, colorIndex: 3),
      ],
    );
  }
}
