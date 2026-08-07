import 'package:flutter_test/flutter_test.dart';

import 'package:ar_synth/models/hand_data.dart';
import 'package:ar_synth/models/music.dart';
import 'package:ar_synth/services/audio_engine.dart';
import 'package:ar_synth/utils/finger_geometry.dart';

void main() {
  group('Note', () {
    test('A4 is MIDI 69 at 440 Hz', () {
      const Note a4 = Note(69);
      expect(a4.name, 'A4');
      expect(a4.frequency, closeTo(440.0, 1e-6));
    });

    test('middle C is MIDI 60 / C4', () {
      const Note c4 = Note(60);
      expect(c4.name, 'C4');
      expect(c4.pitchClass, 0);
      expect(c4.isBlack, isFalse);
    });

    test('C#4 is a black key', () {
      const Note cs4 = Note(61);
      expect(cs4.name, 'C#4');
      expect(cs4.isBlack, isTrue);
    });

    test('an octave up doubles the frequency', () {
      expect(const Note(72).frequency,
          closeTo(const Note(60).frequency * 2, 1e-6));
    });
  });

  group('keyboard layout', () {
    test('two octaves from C4 has 24 notes, 14 white keys', () {
      final List<Note> kb = buildKeyboard(startOctave: 4, octaves: 2);
      expect(kb.length, 24);
      expect(kb.first.name, 'C4');
      expect(whiteKeysOf(kb).length, 14); // 7 white keys per octave
    });
  });

  group('scale quantization', () {
    test('snaps down to the nearest C-major scale note', () {
      final List<int> major = kScales['Major']!;
      // C#4 (61) is not in C major -> snaps down to C4 (60).
      expect(quantizeToScale(61, major), 60);
      // E4 (64) is in C major -> unchanged.
      expect(quantizeToScale(64, major), 64);
    });
  });

  group('noteNameToMidi', () {
    test('parses naturals, sharps and flats', () {
      expect(noteNameToMidi('A4'), 69);
      expect(noteNameToMidi('C4'), 60);
      expect(noteNameToMidi('C#4'), 61);
      expect(noteNameToMidi('Db4'), 61);
      expect(noteNameToMidi('C2'), 36);
    });

    test('returns null on garbage', () {
      expect(noteNameToMidi('hello'), isNull);
      expect(noteNameToMidi(''), isNull);
    });
  });

  group('pose classification', () {
    test('all-extended fingers reads as an open hand', () {
      expect(classifyPose(_syntheticHand(spread: true)), HandPose.openHand);
    });

    test('all-curled fingers reads as a fist', () {
      expect(classifyPose(_syntheticHand(spread: false)), HandPose.fist);
    });
  });
}

/// Builds a crude but valid 21-landmark hand pointing up from a wrist at
/// (0.5, 0.9). When [spread] is true the fingers are extended upward; when
/// false they curl back toward the palm.
Hand _syntheticHand({required bool spread}) {
  final List<HandLandmark> lm =
      List<HandLandmark>.filled(21, const HandLandmark(0.5, 0.9, 0));

  HandLandmark at(double x, double y) => HandLandmark(x, y, 0);

  lm[kWrist] = at(0.5, 0.95);
  lm[kMiddleMcp] = at(0.5, 0.7); // sets hand scale (wrist->middle mcp)

  // Four fingers: MCP near palm, PIP above it, TIP either far up (extended)
  // or curled back down near the MCP.
  const List<double> xs = <double>[0.5, 0.44, 0.5, 0.56, 0.62];
  for (int f = 1; f < 5; f++) {
    final double x = xs[f];
    lm[kFingerMcps[f]] = at(x, 0.7);
    lm[kFingerPips[f]] = at(x, 0.6);
    lm[kFingerTips[f]] = spread ? at(x, 0.35) : at(x, 0.68);
  }

  // Thumb: extended out to the side, or tucked in.
  lm[kThumbMcp] = at(0.44, 0.8);
  lm[kThumbIp] = at(0.4, 0.75);
  lm[kThumbTip] = spread ? at(0.32, 0.72) : at(0.47, 0.74);

  return Hand(landmarks: lm);
}
