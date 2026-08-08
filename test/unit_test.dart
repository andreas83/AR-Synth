import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ar_synth/models/hand_data.dart';
import 'package:ar_synth/models/music.dart';
import 'package:ar_synth/models/synth_settings.dart';
import 'package:ar_synth/services/audio_engine.dart';
import 'package:ar_synth/services/gesture_mapper.dart';
import 'package:ar_synth/services/update_service.dart';
import 'package:ar_synth/state/arpeggiator.dart';
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

  group('update version comparison', () {
    test('normalizes release tags', () {
      expect(normalizeVersion('v1.0.42'), '1.0.42');
      expect(normalizeVersion('1.2.3'), '1.2.3');
      expect(normalizeVersion('AR Synth 1.0.7'), '1.0.7');
      expect(normalizeVersion('nightly'), '');
    });

    test('detects a newer build', () {
      expect(isNewer('1.0.43', '1.0.42'), isTrue);
      expect(isNewer('1.1.0', '1.0.99'), isTrue);
      expect(isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('does not offer same or older builds', () {
      expect(isNewer('1.0.42', '1.0.42'), isFalse);
      expect(isNewer('1.0.41', '1.0.42'), isFalse);
      expect(isNewer('0.9.9', '1.0.0'), isFalse);
    });

    test('handles differing component counts', () {
      expect(isNewer('1.0.1', '1.0'), isTrue);
      expect(isNewer('1.0', '1.0.0'), isFalse);
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

  group('velocity mapping', () {
    test('clamps to [0.05, 1.0]', () {
      expect(GestureMapper.speedToVelocity(-1.0), 0.05);
      expect(GestureMapper.speedToVelocity(0.0), 0.05);
      expect(GestureMapper.speedToVelocity(100.0), 1.0);
    });

    test('is monotonic in speed', () {
      final double slow = GestureMapper.speedToVelocity(0.5);
      final double fast = GestureMapper.speedToVelocity(1.5);
      expect(fast, greaterThan(slow));
    });
  });

  group('air-piano scale-lock lanes', () {
    test('default (Major / C) reproduces the white keys', () {
      const SynthSettings s = SynthSettings();
      final List<Note> lanes = GestureMapper.airPianoLanes(s);
      final List<Note> whites =
          whiteKeysOf(buildKeyboard(startOctave: 4, octaves: 2));
      expect(lanes.length, whites.length);
      expect(lanes.map((Note n) => n.midi).toList(),
          whites.map((Note n) => n.midi).toList());
      expect(lanes.first.name, 'C4');
    });

    test('a non-zero key root shifts the scale (D major)', () {
      const SynthSettings s = SynthSettings(scaleName: 'Major', keyRoot: 2);
      final List<Note> lanes = GestureMapper.airPianoLanes(s);
      const Set<int> dMajorPitchClasses = <int>{1, 2, 4, 6, 7, 9, 11};
      expect(lanes, isNotEmpty);
      for (final Note n in lanes) {
        expect(dMajorPitchClasses.contains(n.pitchClass), isTrue,
            reason: '${n.name} should be in D major');
      }
      expect(lanes.first.name, 'C#4');
    });
  });

  group('arpeggiator helpers', () {
    test('step duration follows tempo + note division', () {
      expect(arpStepDuration(120, ArpRate.quarter).inMilliseconds, 500);
      expect(arpStepDuration(120, ArpRate.eighth).inMilliseconds, 250);
      expect(arpStepDuration(120, ArpRate.sixteenth).inMilliseconds, 125);
    });

    test('up/down index bounces between endpoints without repeats', () {
      final List<int> seq =
          List<int>.generate(8, (int i) => arpUpDownIndex(i, 3));
      expect(seq, <int>[0, 1, 2, 1, 0, 1, 2, 1]);
      expect(arpUpDownIndex(5, 1), 0); // single note is always index 0
    });

    test('pattern indices for up and down', () {
      final math.Random rng = math.Random(0);
      final List<int> up = List<int>.generate(
          6, (int i) => arpPatternIndex(ArpPattern.up, i, 3, rng));
      final List<int> down = List<int>.generate(
          6, (int i) => arpPatternIndex(ArpPattern.down, i, 3, rng));
      expect(up, <int>[0, 1, 2, 0, 1, 2]);
      expect(down, <int>[2, 1, 0, 2, 1, 0]);
    });

    test('random stays within chord bounds', () {
      final math.Random rng = math.Random(42);
      for (int i = 0; i < 50; i++) {
        final int idx = arpPatternIndex(ArpPattern.random, i, 4, rng);
        expect(idx, inInclusiveRange(0, 3));
      }
    });
  });

  group('filter cutoff mapping', () {
    test('normalized cutoff stays within the audible/biquad range', () {
      // AudioEngine maps 0..1 -> ~80..11200 Hz on a log curve.
      double hz(double norm) => 80.0 * math.pow(140.0, norm).toDouble();
      expect(hz(0.0), closeTo(80.0, 1e-6));
      expect(hz(1.0), lessThan(16000.0));
      expect(hz(1.0), greaterThan(hz(0.5)));
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
