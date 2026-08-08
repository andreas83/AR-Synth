import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ar_synth/models/face_data.dart';
import 'package:ar_synth/models/hand_data.dart';
import 'package:ar_synth/models/music.dart';
import 'package:ar_synth/models/synth_settings.dart';
import 'package:ar_synth/services/audio_engine.dart';
import 'package:ar_synth/services/face_tracker.dart';
import 'package:ar_synth/services/gesture_mapper.dart';
import 'package:ar_synth/services/update_service.dart';
import 'package:ar_synth/state/arpeggiator.dart';
import 'package:ar_synth/utils/finger_geometry.dart';
import 'package:ar_synth/utils/overlay_transform.dart';

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

  group('overlay coordinate transform', () {
    void expectPoint(Offset got, double x, double y) {
      expect(got.dx, closeTo(x, 1e-9));
      expect(got.dy, closeTo(y, 1e-9));
    }

    test('back camera at 0deg is the identity', () {
      expectPoint(displayPoint(0.2, 0.7, 0, false), 0.2, 0.7);
    });

    test('the image center is fixed under every rotation/mirror', () {
      for (final int o in <int>[0, 90, 180, 270]) {
        expectPoint(displayPoint(0.5, 0.5, o, false), 0.5, 0.5);
        expectPoint(displayPoint(0.5, 0.5, o, true), 0.5, 0.5);
      }
    });

    test('back camera at 90deg rotates the axes', () {
      // R90: (x,y) -> (1-y, x) about the center.
      expectPoint(displayPoint(0.2, 0.7, 90, false), 0.3, 0.2);
    });

    test('front camera at 270deg matches the plugin example', () {
      // Typical front sensor: net transform is x' = 1 - y, y' = 1 - x, so the
      // skeleton tracks the mirrored, upright selfie preview.
      expectPoint(displayPoint(0.2, 0.7, 270, true), 0.3, 0.8);
    });

    test('front mirror flips the display axis (vs back) at 270deg', () {
      // Back 270deg: (x,y) -> (y, 1-x). The front selfie mirror negates the
      // sensor Y, which after the 270deg rotation lands on the display X axis.
      final Offset back = displayPoint(0.5, 0.8, 270, false);
      final Offset front = displayPoint(0.5, 0.8, 270, true);
      expect(back.dx, closeTo(1.0 - front.dx, 1e-9));
    });
  });

  group('face signal mapping', () {
    test('direct signals pass through, clamped to 0..1', () {
      const FaceFrame f = FaceFrame(
          present: true, mouthOpen: 0.5, smile: 0.8, eyeOpen: 0.3);
      expect(faceSignalValue(f, FaceSignal.mouthOpen), 0.5);
      expect(faceSignalValue(f, FaceSignal.smile), 0.8);
      expect(faceSignalValue(f, FaceSignal.eyeOpen), 0.3);
    });

    test('head tilt is centered at 0.5 and spans the bipolar range', () {
      expect(faceSignalValue(const FaceFrame(present: true, tilt: 0.0),
          FaceSignal.headTilt), 0.5);
      expect(faceSignalValue(const FaceFrame(present: true, tilt: -1.0),
          FaceSignal.headTilt), 0.0);
      expect(faceSignalValue(const FaceFrame(present: true, tilt: 1.0),
          FaceSignal.headTilt), 1.0);
    });

    test('signal() returns null when no face is present', () {
      expect(const FaceFrame.empty().signal(FaceSignal.mouthOpen), isNull);
      expect(const FaceFrame(present: true, mouthOpen: 0.4)
          .signal(FaceSignal.mouthOpen), 0.4);
    });
  });

  group('face play-mode mapping', () {
    final GestureMapper mapper = GestureMapper();

    test('silent with no face or a closed mouth', () {
      expect(mapper.mapFace(const FaceFrame.empty(), const SynthSettings())
          .heldNotes, isEmpty);
      expect(mapper
          .mapFace(const FaceFrame(present: true, mouthOpen: 0.0),
              const SynthSettings())
          .heldNotes, isEmpty);
    });

    test('open mouth sounds a note; head tilt raises the pitch', () {
      const SynthSettings s = SynthSettings(scaleName: 'Chromatic', keyRoot: 0);
      final GestureOutput low = mapper.mapFace(
          const FaceFrame(present: true, mouthOpen: 0.8, tilt: -1.0), s);
      final GestureOutput high = mapper.mapFace(
          const FaceFrame(present: true, mouthOpen: 0.8, tilt: 1.0), s);
      expect(low.heldNotes, isNotEmpty);
      expect(high.heldNotes, isNotEmpty);
      expect(high.heldNotes.first.midi, greaterThan(low.heldNotes.first.midi));
      expect(low.thereminVolume, isNotNull);
    });
  });

  group('face tracker input rotation', () {
    test('portrait lock: both lenses use the sensor mount orientation', () {
      // Device rotation 0 (the app is portrait-locked): front and back reduce
      // to the same value, matching the working hand-tracking convention.
      expect(FaceTracker.rotationDegrees(270, true, 0), 270); // Pixel front
      expect(FaceTracker.rotationDegrees(270, false, 0), 270);
      expect(FaceTracker.rotationDegrees(90, false, 0), 90);
      expect(FaceTracker.rotationDegrees(0, true, 0), 0);
    });

    test('device rotation compensates per the ML Kit camera convention', () {
      // Front adds device rotation, back subtracts it (mod 360).
      expect(FaceTracker.rotationDegrees(270, true, 90), 0);
      expect(FaceTracker.rotationDegrees(270, false, 90), 180);
      expect(FaceTracker.rotationDegrees(90, true, 270), 0);
      expect(FaceTracker.rotationDegrees(90, false, 270), 180);
    });
  });

  group('YUV → RGB conversion (face bitmap path)', () {
    test('greyscale axis: chroma at 128 maps Y straight to grey', () {
      expect(FaceTracker.yuvToRgb(0, 128, 128), (0, 0, 0));
      expect(FaceTracker.yuvToRgb(128, 128, 128), (128, 128, 128));
      expect(FaceTracker.yuvToRgb(255, 128, 128), (255, 255, 255));
    });

    test('primary colours land in the right corner of the cube', () {
      // BT.601 encodings of pure red / green / blue.
      final (int rr, int rg, int rb) = FaceTracker.yuvToRgb(81, 90, 240);
      expect(rr, greaterThan(200));
      expect(rg, lessThan(80));
      expect(rb, lessThan(80));

      final (int br, int bg, int bb) = FaceTracker.yuvToRgb(41, 240, 110);
      expect(bb, greaterThan(200));
      expect(br, lessThan(80));
      expect(bg, lessThan(90));
    });

    test('outputs are always clamped to 0..255', () {
      for (final (int, int, int) c in <(int, int, int)>[
        FaceTracker.yuvToRgb(255, 0, 255),
        FaceTracker.yuvToRgb(0, 255, 0),
        FaceTracker.yuvToRgb(255, 255, 255),
      ]) {
        expect(c.$1, inInclusiveRange(0, 255));
        expect(c.$2, inInclusiveRange(0, 255));
        expect(c.$3, inInclusiveRange(0, 255));
      }
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
