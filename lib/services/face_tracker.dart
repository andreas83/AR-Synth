import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_data.dart';

/// Runs ML Kit face detection on camera frames handed to it by
/// [HandTrackingService] (so it shares the one allowed camera image stream
/// rather than opening its own). Detection is async and self-throttled; the
/// heavy byte copy happens synchronously before the first await, so the
/// [CameraImage] buffer is safe to reuse once [process] returns.
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

  /// Detects a face in [image]; on completion calls [onFrame] with the result.
  /// No-op if a detection is already running or the throttle window is open.
  Future<void> process(
    CameraImage image,
    int sensorOrientation,
    void Function(FaceFrame) onFrame,
  ) async {
    if (_busy) return;
    final DateTime now = DateTime.now();
    if (now.difference(_last) < minInterval) return;
    _busy = true;
    _last = now;
    // Copy bytes synchronously (before any await) so the camera buffer is safe.
    final InputImage? input = _toInputImage(image, sensorOrientation);
    try {
      if (input == null) return;
      final List<Face> faces = await _detector.processImage(input);
      final FaceFrame frame = _toFaceFrame(faces);
      _latest = frame;
      onFrame(frame);
    } catch (e) {
      debugPrint('FaceTracker: detect error: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation) {
    final InputImageRotation rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
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
  /// which is the only format ML Kit accepts on Android.
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List out = Uint8List(width * height + (width * height) ~/ 2);

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    int o = 0;
    // Y plane, row by row (honoring the source row stride / padding).
    for (int row = 0; row < height; row++) {
      final int start = row * yPlane.bytesPerRow;
      out.setRange(o, o + width, yPlane.bytes, start);
      o += width;
    }

    // Interleaved chroma. NV21 order is V then U.
    final int uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;
    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 2;
    final int vPixelStride = vPlane.bytesPerPixel ?? 2;
    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        out[o++] = vPlane.bytes[row * vRowStride + col * vPixelStride];
        out[o++] = uPlane.bytes[row * uRowStride + col * uPixelStride];
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
