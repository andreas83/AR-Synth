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
    this.cursors = const <FingerCursor>[],
    this.poses = const <HandPose>[],
    this.thereminVolume,
    this.pressLineY,
    this.pitchHandY,
    this.volumeHandY,
  });

  /// Notes that should currently sound. The controller diffs successive sets
  /// to decide note-on / note-off.
  final Set<Note> heldNotes;

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

  void reset() {
    for (int i = 0; i < _stablePose.length; i++) {
      _stablePose[i] = HandPose.none;
      _poseStreak[i] = 0;
    }
  }

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
    final List<Note> keyboard =
        buildKeyboard(startOctave: settings.startOctave, octaves: settings.octaves);
    final List<Note> whites = whiteKeysOf(keyboard);
    if (whites.isEmpty) return GestureOutput.empty;

    // Higher sensitivity raises the press line (easier to trigger).
    final double pressLineY = 0.75 - settings.gestureSensitivity * 0.35;

    final Set<Note> held = <Note>{};
    final List<FingerCursor> cursors = <FingerCursor>[];

    for (final Hand hand in frame.hands) {
      if (!hand.isValid) continue;
      // Index, middle, ring, pinky act as the "keys"; thumb is skipped.
      for (int finger = 1; finger < 5; finger++) {
        if (!FingerGeometry.isFingerExtended(hand, finger)) continue;
        final HandLandmark tip = FingerGeometry.tip(hand, finger);
        final int lane =
            (tip.x * whites.length).floor().clamp(0, whites.length - 1);
        final Note note = whites[lane];
        final bool pressing = tip.y >= pressLineY;
        if (pressing) held.add(note);
        cursors.add(FingerCursor(
          x: tip.x,
          y: tip.y,
          colorIndex: finger,
          note: note,
          pressing: pressing,
        ));
      }
    }

    return GestureOutput(
      heldNotes: held,
      cursors: cursors,
      pressLineY: pressLineY,
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
