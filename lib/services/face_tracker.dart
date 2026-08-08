import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_data.dart';

/// A downscaled RGBA frame ready for ML Kit's bitmap path.
class _RgbaImage {
  const _RgbaImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Runs ML Kit face detection on camera frames handed to it by
/// [HandTrackingService] (so it shares the one allowed camera image stream
/// rather than opening its own). Detection is async and self-throttled; the
/// heavy pixel conversion happens synchronously before the first await, so the
/// [CameraImage] buffer is safe to reuse once [process] returns.
///
/// Frames are fed to ML Kit via [InputImage.fromBitmap] (RGBA → native Bitmap),
/// NOT [InputImage.fromBytes]: the byte-array path in `vision-common:17.3.0`
/// throws an internal NullPointerException for otherwise-valid NV21 input, so
/// the bitmap path is the reliable route on this plugin version.
class FaceTracker {
  FaceTracker({this.minInterval = const Duration(milliseconds: 120)});

  /// Minimum time between detections (~8 fps by default — expression is slow).
  final Duration minInterval;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _busy = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  FaceFrame _latest = const FaceFrame.empty();
  FaceFrame get latest => _latest;

  // -- Diagnostics (surfaced on-screen while debugging face detection) --------
  /// Frames handed to ML Kit (conversion succeeded, detect was called).
  int attempts = 0;

  /// Detect calls that returned without throwing.
  int detections = 0;

  /// Detect calls that returned at least one face.
  int facesFound = 0;

  /// Last error thrown by the conversion or the detector, if any.
  String? lastError;

  /// Detects a face in [image]; on completion calls [onFrame] with the result.
  /// No-op if a detection is already running or the throttle window is open.
  ///
  /// [sensorOrientation] is the camera's mount angle, [isFront] whether it is a
  /// front-facing lens, and [deviceOrientationDegrees] the device's current UI
  /// rotation (0/90/180/270). Together they fix the ML Kit input rotation — see
  /// [rotationDegrees].
  Future<void> process(
    CameraImage image,
    int sensorOrientation,
    bool isFront,
    int deviceOrientationDegrees,
    void Function(FaceFrame) onFrame,
  ) async {
    if (_busy) return;
    final DateTime now = DateTime.now();
    if (now.difference(_last) < minInterval) return;
    _busy = true;
    _last = now;
    try {
      // Copy bytes synchronously (before the first await) so the camera buffer
      // is safe to reuse the moment this call returns. Kept inside the try so a
      // conversion failure can never leave [_busy] stuck true — which would
      // silently kill face detection for the rest of the session.
      final InputImage? input = _toInputImage(
          image, sensorOrientation, isFront, deviceOrientationDegrees);
      if (input == null) {
        lastError = 'null input image';
        onFrame(const FaceFrame.empty());
        return;
      }
      attempts++;
      final List<Face> faces = await _detector.processImage(input);
      detections++;
      if (faces.isNotEmpty) facesFound++;
      final FaceFrame frame = _toFaceFrame(faces);
      _latest = frame;
      onFrame(frame);
    } catch (e) {
      lastError = e.toString();
      debugPrint('FaceTracker: detect error: $e');
      // Still emit so the UI refreshes and shows the live diagnostics.
      onFrame(const FaceFrame.empty());
    } finally {
      _busy = false;
    }
  }

  /// A one-line snapshot of the detection pipeline for the on-screen HUD.
  String get debugLine {
    final String err =
        lastError == null ? '' : ' err:${lastError!.split('\n').first}';
    return 'at:$attempts dt:$detections fc:$facesFound$err';
  }

  /// The clockwise rotation (0/90/180/270) ML Kit must apply to a frame to make
  /// it upright, following the convention of the official `google_mlkit` camera
  /// example: the front lens adds the device rotation to the sensor mount, the
  /// back lens subtracts it. In this app's portrait lock (device rotation 0)
  /// both reduce to the sensor mount orientation.
  static int rotationDegrees(
      int sensorOrientation, bool isFront, int deviceOrientationDegrees) {
    final int sensor = ((sensorOrientation % 360) + 360) % 360;
    final int device = ((deviceOrientationDegrees % 360) + 360) % 360;
    return isFront
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation,
      bool isFront, int deviceOrientationDegrees) {
    final int degrees =
        rotationDegrees(sensorOrientation, isFront, deviceOrientationDegrees);
    final _RgbaImage rgba = _yuv420ToRgba(image);
    // Bitmap path — see the class doc for why we avoid InputImage.fromBytes.
    return InputImage.fromBitmap(
      bitmap: rgba.bytes,
      width: rgba.width,
      height: rgba.height,
      rotation: degrees,
    );
  }

  /// Converts a YUV_420_888 [CameraImage] into a tightly-packed RGBA buffer,
  /// downscaled by [step] (default 2 — expression detection needs far less than
  /// full sensor resolution, and this quarters the per-frame work). Uses BT.601
  /// fixed-point coefficients; reads are bounds-guarded against short/padded
  /// plane strides. Returns bytes in R,G,B,A order as the native bitmap handler
  /// expects.
  static _RgbaImage _yuv420ToRgba(CameraImage image, {int step = 2}) {
    final int w = image.width;
    final int h = image.height;
    final int outW = w ~/ step;
    final int outH = h ~/ step;
    final Uint8List out = Uint8List(outW * outH * 4);

    final Plane yP = image.planes[0];
    final Plane uP = image.planes[1];
    final Plane vP = image.planes[2];
    final Uint8List yB = yP.bytes;
    final Uint8List uB = uP.bytes;
    final Uint8List vB = vP.bytes;
    final int yRow = yP.bytesPerRow;
    final int uRow = uP.bytesPerRow;
    final int vRow = vP.bytesPerRow;
    final int yPix = yP.bytesPerPixel ?? 1;
    final int uPix = uP.bytesPerPixel ?? 2;
    final int vPix = vP.bytesPerPixel ?? 2;
    final int yLen = yB.length;
    final int uLen = uB.length;
    final int vLen = vB.length;

    int o = 0;
    for (int j = 0; j < outH; j++) {
      final int sy = j * step;
      final int yRowOff = sy * yRow;
      final int uRowOff = (sy >> 1) * uRow;
      final int vRowOff = (sy >> 1) * vRow;
      for (int i = 0; i < outW; i++) {
        final int sx = i * step;
        final int yi = yRowOff + sx * yPix;
        final int uvCol = sx >> 1;
        final int ui = uRowOff + uvCol * uPix;
        final int vi = vRowOff + uvCol * vPix;
        final int y = yi < yLen ? (yB[yi] & 0xff) : 0;
        final int u = ui < uLen ? (uB[ui] & 0xff) : 128;
        final int v = vi < vLen ? (vB[vi] & 0xff) : 128;
        final (int r, int g, int b) = yuvToRgb(y, u, v);
        out[o++] = r;
        out[o++] = g;
        out[o++] = b;
        out[o++] = 255;
      }
    }
    return _RgbaImage(out, outW, outH);
  }

  /// BT.601 YUV → RGB for a single pixel, with 0..255 inputs and clamped 0..255
  /// outputs. Fixed-point (coefficients scaled by 65536) and pure/testable.
  static (int, int, int) yuvToRgb(int y, int u, int v) {
    final int cu = u - 128;
    final int cv = v - 128;
    final int r = y + ((91881 * cv) >> 16);
    final int g = y - ((22554 * cu + 46802 * cv) >> 16);
    final int b = y + ((116130 * cu) >> 16);
    return (_clamp255(r), _clamp255(g), _clamp255(b));
  }

  static int _clamp255(int x) => x < 0 ? 0 : (x > 255 ? 255 : x);

  FaceFrame _toFaceFrame(List<Face> faces) {
    if (faces.isEmpty) return const FaceFrame.empty();
    final Face f = faces.first;
    final double smile = f.smilingProbability ?? 0.0;
    final double le = f.leftEyeOpenProbability ?? 1.0;
    final double re = f.rightEyeOpenProbability ?? 1.0;
    final double roll = (f.headEulerAngleZ ?? 0.0) / 45.0; // ~±45° -> ±1
    return FaceFrame(
      present: true,
      smile: smile.clamp(0.0, 1.0),
      eyeOpen: ((le + re) / 2.0).clamp(0.0, 1.0),
      mouthOpen: _mouthOpen(f),
      tilt: roll.clamp(-1.0, 1.0),
    );
  }

  /// Estimates mouth openness from the gap between the upper- and lower-lip
  /// contours, normalized by face height. Returns 0 when contours are absent.
  static double _mouthOpen(Face f) {
    final List<math.Point<int>>? upper =
        f.contours[FaceContourType.upperLipBottom]?.points;
    final List<math.Point<int>>? lower =
        f.contours[FaceContourType.lowerLipTop]?.points;
    if (upper == null || lower == null || upper.isEmpty || lower.isEmpty) {
      return 0.0;
    }
    double avgY(List<math.Point<int>> pts) {
      double sum = 0;
      for (final math.Point<int> p in pts) {
        sum += p.y;
      }
      return sum / pts.length;
    }

    final double gap = (avgY(lower) - avgY(upper)).abs();
    final double faceH = f.boundingBox.height;
    if (faceH <= 0) return 0.0;
    // A wide-open mouth spans roughly 18% of the face box height.
    return (gap / (faceH * 0.18)).clamp(0.0, 1.0);
  }

  Future<void> dispose() async {
    try {
      await _detector.close();
    } catch (_) {}
  }
}
