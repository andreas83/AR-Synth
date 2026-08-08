import 'package:flutter/painting.dart' show Offset;

/// Maps a normalized hand landmark from the coordinate space `hand_landmarker`
/// reports into the normalized display space that lines up with the on-screen
/// [CameraPreview].
///
/// The `hand_landmarker` plugin returns landmarks relative to the *unrotated
/// sensor* image (0..1), while the camera preview is shown rotated by the
/// sensor's mount orientation and, for a front camera, mirrored like a selfie.
/// The plugin's own example reconciles the two by transforming its overlay
/// canvas — `rotate(sensorOrientation)`, then `scale(-1, 1) + rotate(180)` for
/// the front camera. This function is the same transform expressed directly on
/// the normalized coordinates: because we work in normalized space the sensor
/// width/height factors cancel, so callers keep their simple
/// `x * width, y * height` mapping.
///
/// The overlay used to draw landmarks straight through (`x, y`), which left the
/// skeleton rotated by the sensor orientation and mirror-flipped from the hand —
/// e.g. rotating the hand left spun the skeleton right, and moving the hand
/// sideways moved the skeleton up/down.
///
/// The width/height cancellation assumes the display box's aspect matches the
/// rotated image orientation (portrait for a 90°/270° mount, which is the case
/// for a phone held upright — the only orientation this app runs in).
Offset displayPoint(
  double x,
  double y,
  int sensorOrientation,
  bool frontCamera,
) {
  // Front camera: the preview is mirrored. The example writes this as
  // scale(-1, 1) + rotate(180) applied after the sensor rotation, which reduces
  // to negating the sensor Y *before* the rotation.
  final double sy = frontCamera ? 1.0 - y : y;

  // Center on the image origin so rotation is about the middle.
  final double u = x - 0.5;
  final double v = sy - 0.5;

  // Rotate by the sensor mount orientation (clockwise in screen coords, y-down).
  final int quarter = ((sensorOrientation ~/ 90) % 4 + 4) % 4;
  final double ru;
  final double rv;
  switch (quarter) {
    case 1: // 90°
      ru = -v;
      rv = u;
      break;
    case 2: // 180°
      ru = -u;
      rv = -v;
      break;
    case 3: // 270°
      ru = v;
      rv = -u;
      break;
    default: // 0°
      ru = u;
      rv = v;
  }

  return Offset(ru + 0.5, rv + 0.5);
}
