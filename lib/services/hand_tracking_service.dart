import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart' as hlm;
import 'package:permission_handler/permission_handler.dart';

import '../models/hand_data.dart';

/// Lifecycle / readiness of the camera + hand tracker.
enum TrackingStatus { idle, starting, running, denied, error, unsupported }

/// Owns the [CameraController] and the MediaPipe [hlm.HandLandmarkerPlugin],
/// runs detection on camera frames, and publishes results as normalized
/// [HandFrame]s that the rest of the app can consume without knowing about the
/// plugin's own types.
///
/// Android-only: the underlying plugin bridges to native MediaPipe on Android.
/// On other platforms [start] reports [TrackingStatus.unsupported].
///
/// `hand_landmarker`'s `detect()` is a synchronous native call, so we throttle
/// how often it runs (and guard against re-entrancy) to keep the UI smooth.
class HandTrackingService {
  HandTrackingService({this.minFrameInterval = const Duration(milliseconds: 66)});

  /// Minimum time between detections (default ~15 fps).
  final Duration minFrameInterval;

  CameraController? _controller;
  hlm.HandLandmarkerPlugin? _plugin;

  final StreamController<HandFrame> _frames =
      StreamController<HandFrame>.broadcast();

  TrackingStatus _status = TrackingStatus.idle;
  String? _error;
  bool _mirror = false;

  int _sensorOrientation = 0;
  bool _processing = false;
  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);

  /// Normalized hand frames (empty list of hands until the first detection).
  Stream<HandFrame> get frames => _frames.stream;

  /// The live controller, for building a [CameraPreview]. Null until running.
  CameraController? get controller => _controller;

  TrackingStatus get status => _status;
  String? get error => _error;

  /// Whether coordinates are mirrored to match a front-camera selfie preview.
  bool get mirrored => _mirror;

  bool get isRunning => _status == TrackingStatus.running;

  /// Requests permission, opens the front camera and starts detection.
  /// Returns true when tracking is running.
  Future<bool> start({int numHands = 2}) async {
    if (_status == TrackingStatus.running) return true;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _status = TrackingStatus.unsupported;
      _error = 'Hand tracking is only supported on Android.';
      return false;
    }

    _status = TrackingStatus.starting;
    _error = null;

    // 1. Camera permission.
    final PermissionStatus perm = await Permission.camera.request();
    if (!perm.isGranted) {
      _status = TrackingStatus.denied;
      _error = 'Camera permission was not granted.';
      return false;
    }

    try {
      // 2. Pick the front camera (fall back to the first available).
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        _status = TrackingStatus.error;
        _error = 'No cameras available on this device.';
        return false;
      }
      final CameraDescription camera = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _mirror = camera.lensDirection == CameraLensDirection.front;
      _sensorOrientation = camera.sensorOrientation;

      // 3. Controller with a YUV_420 stream (required by the native tracker).
      final CameraController controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;

      // 4. MediaPipe plugin. GPU delegate for speed, CPU fallback on failure.
      _plugin = _createPlugin(numHands);

      // 5. Run detection on the camera stream (throttled + re-entrancy guarded).
      await controller.startImageStream(_processImage);

      _status = TrackingStatus.running;
      return true;
    } catch (e) {
      _status = TrackingStatus.error;
      _error = 'Failed to start hand tracking: $e';
      debugPrint(_error);
      await _teardown();
      return false;
    }
  }

  void _processImage(CameraImage image) {
    if (_processing) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastProcess) < minFrameInterval) return;
    final hlm.HandLandmarkerPlugin? plugin = _plugin;
    if (plugin == null) return;

    _processing = true;
    _lastProcess = now;
    try {
      final List<hlm.Hand> raw = plugin.detect(image, _sensorOrientation);
      _emit(raw, image.width, image.height);
    } catch (e) {
      debugPrint('HandTracking: detect error: $e');
    } finally {
      _processing = false;
    }
  }

  hlm.HandLandmarkerPlugin _createPlugin(int numHands) {
    try {
      return hlm.HandLandmarkerPlugin.create(
        numHands: numHands,
        minHandDetectionConfidence: 0.6,
        delegate: hlm.HandLandmarkerDelegate.gpu,
      );
    } catch (_) {
      // Some devices lack a usable GPU delegate; retry on CPU.
      return hlm.HandLandmarkerPlugin.create(
        numHands: numHands,
        minHandDetectionConfidence: 0.6,
        delegate: hlm.HandLandmarkerDelegate.cpu,
      );
    }
  }

  void _emit(List<hlm.Hand> raw, int imageWidth, int imageHeight) {
    if (_frames.isClosed) return;
    final List<Hand> hands = <Hand>[];
    for (final hlm.Hand h in raw) {
      final List<hlm.Landmark> lms = h.landmarks;
      if (lms.length != 21) continue;
      final List<HandLandmark> converted = <HandLandmark>[
        for (final hlm.Landmark p in lms)
          HandLandmark(_mirror ? 1.0 - p.x : p.x, p.y, p.z),
      ];
      hands.add(Hand(landmarks: converted, isRight: _guessRight(converted)));
    }
    _frames.add(HandFrame(
      hands: hands,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    ));
  }

  /// Rough handedness hint from geometry (the plugin doesn't expose it):
  /// in display space, a right hand tends to have the thumb left of the pinky.
  bool _guessRight(List<HandLandmark> lm) => lm[kThumbTip].x < lm[kPinkyTip].x;

  Future<void> stop() async {
    await _teardown();
    _status = TrackingStatus.idle;
  }

  Future<void> _teardown() async {
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        await _controller?.stopImageStream();
      }
    } catch (_) {}
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    try {
      _plugin?.dispose();
    } catch (_) {}
    _plugin = null;
    _processing = false;
  }

  Future<void> dispose() async {
    await _teardown();
    await _frames.close();
  }
}
