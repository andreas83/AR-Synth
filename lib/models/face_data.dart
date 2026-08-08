/// Normalized face-expression data, decoupled from the ML Kit plugin types so
/// the rest of the app depends only on this small struct.
library;

/// A face-derived signal that can drive a synth parameter.
enum FaceSignal { mouthOpen, smile, headTilt, eyeOpen }

extension FaceSignalLabel on FaceSignal {
  String get label => switch (this) {
        FaceSignal.mouthOpen => 'Mouth open',
        FaceSignal.smile => 'Smile',
        FaceSignal.headTilt => 'Head tilt',
        FaceSignal.eyeOpen => 'Eyes open',
      };
}

/// One frame of face-expression tracking. All signals are normalized so they
/// can be mapped straight onto a 0..1 synth control.
class FaceFrame {
  const FaceFrame({
    this.present = false,
    this.smile = 0.0,
    this.eyeOpen = 1.0,
    this.mouthOpen = 0.0,
    this.tilt = 0.0,
  });

  const FaceFrame.empty()
      : present = false,
        smile = 0.0,
        eyeOpen = 1.0,
        mouthOpen = 0.0,
        tilt = 0.0;

  /// Whether a face was detected this frame.
  final bool present;

  /// Smiling probability, 0..1.
  final double smile;

  /// Average eye-open probability, 0..1.
  final double eyeOpen;

  /// How open the mouth is, 0 (closed) .. 1 (wide), from lip contours.
  final double mouthOpen;

  /// Head roll, -1 (tilted left) .. 1 (tilted right).
  final double tilt;

  /// The chosen [signal] as a 0..1 control value, or null when no face is
  /// present. Pure — safe to unit-test. See [faceSignalValue].
  double? signal(FaceSignal s) => present ? faceSignalValue(this, s) : null;
}

/// Maps a [FaceFrame] + [FaceSignal] to a normalized 0..1 control value.
/// Extracted as a top-level pure function so it can be unit-tested without ML
/// Kit. Does not check [FaceFrame.present]; callers gate on that.
double faceSignalValue(FaceFrame f, FaceSignal s) => switch (s) {
      FaceSignal.mouthOpen => f.mouthOpen.clamp(0.0, 1.0),
      FaceSignal.smile => f.smile.clamp(0.0, 1.0),
      // Head tilt is bipolar (-1..1); shift into 0..1 so centered == mid.
      FaceSignal.headTilt => ((f.tilt.clamp(-1.0, 1.0)) + 1.0) / 2.0,
      FaceSignal.eyeOpen => f.eyeOpen.clamp(0.0, 1.0),
    };
