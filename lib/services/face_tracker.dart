import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_data.dart';

/// Runs ML Kit face detection on camera frames handed to it by
/// [HandTrackingService] (so it shares the one allowed camera image stream
/// rather than opening its own). Detection is async and self-throttled; the
/// heavy byte copy happens synchronously before the first await, so the
/// [CameraImage] buffer is safe to reuse once [process] returns.
///
/// Feeds ML Kit the standard NV21 [InputImage.fromBytes] path. The plugin is
/// pinned to the last Java-based release (`google_mlkit_commons: 0.11.x`); the
/// 0.12.0 Kotlin rewrite of its native InputImageConverter regressed and threw
/// an internal NullPointerException for every frame on both the byte-array and
/// bitmap paths.
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
      if (e is PlatformException) {
        // Capture everything the native error carries — the message names the
        // exception, and details/stacktrace (when present) name the class that
        // threw, which is what we need to pinpoint the ML Kit failure.
        lastError = 'code=${e.code} | msg=${e.message} | '
            'details=${e.details} | stack=${e.stacktrace}';
      } else {
        lastError = e.toString();
      }
      debugPrint('FaceTracker: detect error: $e');
      // Still emit so the UI refreshes and shows the live diagnostics.
      onFrame(const FaceFrame.empty());
    } finally {
      _busy = false;
    }
  }

  /// A snapshot of the detection pipeline for the on-screen HUD, including the
  /// full last error (multi-line) so the failing native call is visible.
  String get debugLine {
    final String head = 'at:$attempts dt:$detections fc:$facesFound';
    if (lastError == null) return head;
    // Collapse to single spaces and cap length so the HUD stays readable.
    final String err = lastError!.replaceAll(RegExp(r'\s+'), ' ');
    final String capped = err.length > 600 ? err.substring(0, 600) : err;
    return '$head\nerr: $capped';
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
    final InputImageRotation rotation = InputImageRotationValue.fromRawValue(
            rotationDegrees(
                sensorOrientation, isFront, deviceOrientationDegrees)) ??
        InputImageRotation.rotation0deg;
    final Uint8List nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        // The converted buffer is tightly packed at one byte per Y pixel.
        bytesPerRow: image.width,
      ),
    );
  }

  /// Repacks a YUV_420_888 [CameraImage] into a tightly-packed NV21 buffer
  /// (full-res Y plane followed by interleaved V,U at quarter resolution),
  /// which is the format ML Kit accepts on Android. Reads are bounds-guarded
  /// against short/padded plane strides.
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List out = Uint8List(width * height + (width * height) ~/ 2);

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    int o = 0;
    final int yRowStride = yPlane.bytesPerRow;
    final int yLen = yPlane.bytes.length;
    for (int row = 0; row < height; row++) {
      final int start = row * yRowStride;
      final int copy = math.min(width, yLen - start);
      if (copy <= 0) break;
      out.setRange(o, o + copy, yPlane.bytes, start);
      o += width; // keep NV21 row alignment even if the source row was short
    }

    // Interleaved chroma. NV21 order is V then U; a missing sample falls back to
    // neutral chroma (128).
    o = width * height;
    final int uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;
    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 2;
    final int vPixelStride = vPlane.bytesPerPixel ?? 2;
    final int uLen = uPlane.bytes.length;
    final int vLen = vPlane.bytes.length;
    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        final int vi = row * vRowStride + col * vPixelStride;
        final int ui = row * uRowStride + col * uPixelStride;
        out[o++] = vi < vLen ? vPlane.bytes[vi] : 128;
        out[o++] = ui < uLen ? uPlane.bytes[ui] : 128;
      }
    }
    return out;
  }

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
