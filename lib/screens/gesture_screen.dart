import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/face_data.dart';
import '../models/hand_data.dart';
import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/gesture_mapper.dart';
import '../services/hand_tracking_service.dart';
import '../services/update_service.dart';
import '../state/piano_controller.dart';
import '../state/settings_controller.dart';
import '../theme.dart';
import '../utils/finger_geometry.dart';
import '../utils/overlay_transform.dart';
import '../widgets/hand_overlay.dart';
import '../widgets/note_ripple_painter.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/synth_controls.dart';
import '../widgets/ui_kit.dart';
import '../widgets/update_dialog.dart';
import 'settings_screen.dart';

/// Camera hand-gesture instrument. Streams frames through the hand tracker,
/// maps them to notes via [GestureMapper], and plays them through the
/// [PianoController]. Synth controls live in a bottom sheet on this screen.
/// Android only.
class GestureScreen extends StatefulWidget {
  const GestureScreen({super.key});

  @override
  State<GestureScreen> createState() => _GestureScreenState();
}

class _GestureScreenState extends State<GestureScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final HandTrackingService _service = HandTrackingService();
  final GestureMapper _mapper = GestureMapper();
  final UpdateService _updates = UpdateService();
  StreamSubscription<HandFrame>? _sub;
  StreamSubscription<FaceFrame>? _faceSub;
  Timer? _debugRefresh;

  HandFrame _frame = const HandFrame.empty();
  GestureOutput _output = GestureOutput.empty;
  FaceFrame _face = const FaceFrame.empty();
  GestureMode? _lastMode;
  bool _starting = true;
  bool _paused = false;

  PianoController? _piano;
  SettingsController? _settingsController;

  // Reactive visualizer: a Ticker advances a millisecond clock that drives the
  // ripple layer's repaint independently of the ~15 fps hand frames.
  late final Ticker _ticker;
  final ValueNotifier<int> _clockMs = ValueNotifier<int>(0);
  final List<NoteRipple> _ripples = <NoteRipple>[];
  Set<Note> _prevHeld = <Note>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
    _sub = _service.frames.listen(_onFrame);
    _faceSub = _service.faces.listen(_onFace);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
      // Check for an app update silently on launch (this is now the entry
      // screen); only interrupt the user if there is actually a newer build.
      _checkForUpdate();
    });
    // Keep the face-detection HUD live even when no frames are arriving (so a
    // "detection never runs" state is visible, not just a stale render).
    _debugRefresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      final UpdateInfo? update = await _updates.checkForUpdate();
      if (!mounted || update == null) return;
      // Free the camera while the (large) APK downloads/installs — no reason to
      // burn battery on the preview behind a modal the user is reading.
      await _pauseCamera();
      if (!mounted) return;
      final bool? installed =
          await UpdateDialog.show(context, update: update, service: _updates);
      // If the installer didn't launch, the user stays in the app — resume play.
      if (mounted && installed != true) await _start();
    } catch (_) {
      // Update checks are best-effort; never block play on them.
      if (mounted && _paused) await _start();
    }
  }

  /// Opens Settings with the camera stopped (you're configuring, not playing),
  /// then resumes tracking on return. Also means the manual update check that
  /// lives in Settings runs with the camera already off.
  Future<void> _openSettings() async {
    await _pauseCamera();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (mounted) await _start();
  }

  /// Stops the camera + hand/face tracking and releases the wakelock, showing a
  /// lightweight "paused" state. Resumed via [_start].
  Future<void> _pauseCamera() async {
    WakelockPlus.disable();
    await _service.stop();
    if (mounted) setState(() => _paused = true);
  }

  Future<void> _flipCamera() async {
    if (!_service.hasMultipleCameras) return;
    setState(() => _starting = true);
    await _service.switchCamera();
    if (mounted) setState(() => _starting = false);
  }

  void _onFace(FaceFrame face) {
    if (!mounted) return;
    final SynthSettings settings =
        _settingsController?.settings ?? const SynthSettings();
    if (settings.gestureMode == GestureMode.face) {
      // Face mode: the face plays the synth.
      final GestureOutput output = _mapper.mapFace(face, settings);
      _piano?.applyGesture(output);
      if (settings.visualizerEnabled) _spawnRipples(output, sensorSpace: false);
      setState(() {
        _face = face;
        _output = output;
        _frame = const HandFrame.empty(); // no hand skeleton in face mode
      });
    } else {
      // Other modes: the face just modulates a parameter.
      _piano?.applyFaceModulation(face);
      setState(() => _face = face);
    }
  }

  void _onTick(Duration elapsed) {
    final int ms = elapsed.inMilliseconds;
    _ripples.removeWhere((NoteRipple r) => r.isDead(ms));
    _clockMs.value = ms;
  }

  /// Spawns ripples for freshly-held notes. [sensorSpace] is true when the
  /// cursor positions come from hand landmarks (raw sensor space, so they need
  /// [displayPoint]); face-mode cursors are already synthetic display positions.
  void _spawnRipples(GestureOutput output, {bool sensorSpace = true}) {
    final Set<Note> now = output.heldNotes;
    final Set<Note> fresh = now.difference(_prevHeld);
    _prevHeld = <Note>{...now};
    if (fresh.isEmpty) return;
    final int ms = _clockMs.value;
    for (final Note n in fresh) {
      final FingerCursor? cursor = _cursorForNote(output, n);
      double x = cursor?.x ?? 0.5;
      double y = cursor?.y ?? 0.5;
      if (sensorSpace) {
        // Map raw landmark space into preview display space so ripples land
        // under the finger like the overlay does.
        final Offset p = displayPoint(
            x, y, _service.sensorOrientation, _service.isFrontCamera);
        x = p.dx;
        y = p.dy;
      }
      _ripples.add(NoteRipple(
        x: x,
        y: y,
        pitchClass: n.pitchClass,
        bornMs: ms,
      ));
    }
    if (_ripples.length > 60) {
      _ripples.removeRange(0, _ripples.length - 60);
    }
  }

  FingerCursor? _cursorForNote(GestureOutput output, Note note) {
    for (final FingerCursor c in output.cursors) {
      if (c.note == note) return c;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _piano = context.read<PianoController>();
    _settingsController = context.read<SettingsController>();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _paused = false;
    });
    final bool ok = await _service.start();
    // Keep the screen awake while the camera instrument is running.
    if (ok) {
      WakelockPlus.enable();
    }
    if (mounted) setState(() => _starting = false);
  }

  void _onFrame(HandFrame frame) {
    if (!mounted) return;
    final SynthSettings settings =
        _settingsController?.settings ?? const SynthSettings();
    if (settings.gestureMode != _lastMode) {
      _lastMode = settings.gestureMode;
      _mapper.reset();
      _piano?.clearGesture(); // stop any notes lingering from the previous mode
    }
    // Face detection runs when face-modulation is on OR we're in Face play mode.
    _service.faceEnabled =
        settings.faceControlEnabled || settings.gestureMode == GestureMode.face;

    // In Face mode the notes come from the face stream (see _onFace); ignore
    // hand frames for playing so the two sources don't fight.
    if (settings.gestureMode == GestureMode.face) return;

    final GestureOutput output = _mapper.map(frame, settings);
    _piano?.applyGesture(output);
    if (settings.visualizerEnabled) {
      _spawnRipples(output);
    } else {
      _prevHeld = <Note>{...output.heldNotes};
    }
    setState(() {
      _frame = frame;
      _output = output;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      WakelockPlus.disable();
      _service.stop();
      _piano?.clearGesture();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _ticker.dispose();
    _clockMs.dispose();
    _sub?.cancel();
    _faceSub?.cancel();
    _debugRefresh?.cancel();
    _service.dispose();
    _updates.dispose();
    _piano?.clearGesture();
    super.dispose();
  }

  void _openSynthSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (BuildContext context, ScrollController scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SheetHandle(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
                    child: Text('Synth',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textHi)),
                  ),
                  SynthControls(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final SynthSettings s = settings.settings;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        titleSpacing: 16,
        title: const BrandMark(fontSize: 18),
        flexibleSpace: const IgnorePointer(child: _TopScrim()),
        actions: <Widget>[
          _GestureModeButton(
              current: s.gestureMode, onSelected: settings.setGestureMode),
          if (_service.hasMultipleCameras)
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: _service.usingFrontCamera
                  ? 'Switch to back camera'
                  : 'Switch to front camera',
              onPressed: _starting ? null : _flipCamera,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(s),
    );
  }

  Widget _buildBody(SynthSettings s) {
    final TrackingStatus status = _service.status;
    final CameraController? controller = _service.controller;

    if (_paused) {
      return const _MessageView(
        icon: Icons.pause_rounded,
        title: 'Camera paused',
        message: 'Paused to save battery. Resume when you come back.',
      );
    }
    if (_starting) {
      return const _LoadingView();
    }
    if (status != TrackingStatus.running ||
        controller == null ||
        !controller.value.isInitialized) {
      return _buildUnavailable(status);
    }

    // Preview aspect ratio from the sensor frame (landscape) shown upright.
    final Size previewSize = controller.value.previewSize ?? const Size(4, 3);
    final double previewAspect = previewSize.height / previewSize.width;

    return Stack(
      children: <Widget>[
        // Camera preview + hand overlay.
        //
        // hand_landmarker reports landmarks in the *raw sensor* frame, so the
        // overlay painter (and ripple spawn positions) rotate/mirror them into
        // the preview's display space via displayPoint(). The CameraPreview is
        // auto-oriented by the camera plugin; the app is locked to portrait, so
        // both share one upright, display-oriented space and stay aligned
        // without any manual RotatedBox.
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    controller.buildPreview(),
                    CustomPaint(
                      painter: HandOverlayPainter(
                        frame: _frame,
                        output: _output,
                        sensorOrientation: _service.sensorOrientation,
                        frontCamera: _service.isFrontCamera,
                      ),
                    ),
                    if (s.visualizerEnabled)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: NoteRipplePainter(
                            ripples: _ripples,
                            clockMs: _clockMs,
                          ),
                        ),
                      ),
                    // Subtle vignette so overlays read as a "viewport".
                    const IgnorePointer(child: _Vignette()),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Status chips.
        Positioned(
          top: kToolbarHeight + 24,
          left: 12,
          right: 12,
          child: _StatusBar(
              frame: _frame, output: _output, face: _face, settings: s),
        ),
        // Face-detection diagnostics HUD (shown while face features are on).
        if (s.faceControlEnabled || s.gestureMode == GestureMode.face)
          Positioned(
            top: kToolbarHeight + 66,
            left: 12,
            child: GlassPanel(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              radius: 8,
              opacity: 0.5,
              child: Text(
                _service.faceDebugLine,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppTheme.textLow),
              ),
            ),
          ),
        // Bottom controls: the Synth action sits just above the keyboard strip
        // (non-interactive display of what's currently playing).
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, right: 2),
                  child: GradientButton(
                    onPressed: _openSynthSheet,
                    icon: Icons.graphic_eq,
                    label: 'Synth',
                  ),
                ),
                GlassPanel(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  radius: AppTheme.radius,
                  opacity: 0.5,
                  child: SizedBox(
                    height: 88,
                    child: PianoKeyboard(
                      notes: buildKeyboard(
                          startOctave: s.startOctave, octaves: s.octaves),
                      activeNotes:
                          context.watch<PianoController>().activeNotes,
                      interactive: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailable(TrackingStatus status) {
    final (IconData icon, String title, String message) = switch (status) {
      TrackingStatus.denied => (
          Icons.no_photography_outlined,
          'Camera access needed',
          'Gesture mode needs the camera. Grant permission in system '
              'settings, then retry.'
        ),
      TrackingStatus.unsupported => (
          Icons.phonelink_erase_outlined,
          'Android only',
          'Hand and face tracking are only available on Android.'
        ),
      _ => (
          Icons.error_outline,
          'Could not start the camera',
          _service.error ?? 'Something went wrong starting the camera.'
        ),
    };
    return _MessageView(
      icon: icon,
      title: title,
      message: message,
      action: status == TrackingStatus.unsupported
          ? null
          : GradientButton(
              onPressed: _start,
              icon: Icons.refresh_rounded,
              label: 'Retry',
            ),
    );
  }
}

/// The grab handle at the top of the synth bottom sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Top gradient scrim so the app-bar title/icons stay legible over the camera.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Radial darkening at the frame edges for a premium "viewport" feel.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.15,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
          stops: const <double>[0.62, 1.0],
        ),
      ),
    );
  }
}

/// A branded, animated "waking the camera" placeholder.
class _LoadingView extends StatefulWidget {
  const _LoadingView();

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_c),
            child: const BrandMark(fontSize: 26),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Waking the camera…',
              style: TextStyle(color: AppTheme.textLow, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A centered icon + title + message state, with an optional action.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceHigh,
                border: Border.all(color: AppTheme.outline),
              ),
              child: Icon(icon, size: 38, color: AppTheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textHi)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.4, color: AppTheme.textLow)),
            if (action != null) ...<Widget>[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The gesture-mode switcher shown in the app bar as a labelled glass pill.
class _GestureModeButton extends StatelessWidget {
  const _GestureModeButton({required this.current, required this.onSelected});

  final GestureMode current;
  final ValueChanged<GestureMode> onSelected;

  static IconData _iconFor(GestureMode m) => switch (m) {
        GestureMode.airPiano => Icons.piano,
        GestureMode.discretePoses => Icons.back_hand,
        GestureMode.theremin => Icons.waves,
        GestureMode.face => Icons.face_retouching_natural,
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GestureMode>(
      tooltip: 'Gesture mode',
      initialValue: current,
      onSelected: onSelected,
      color: AppTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppTheme.outline),
      ),
      position: PopupMenuPosition.under,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<GestureMode>>[
        for (final GestureMode mode in GestureMode.values)
          PopupMenuItem<GestureMode>(
            value: mode,
            child: Row(
              children: <Widget>[
                Icon(_iconFor(mode),
                    size: 18,
                    color: mode == current
                        ? AppTheme.primary
                        : AppTheme.textMed),
                const SizedBox(width: 12),
                Text(mode.label,
                    style: TextStyle(
                        color: mode == current
                            ? AppTheme.textHi
                            : AppTheme.textMed,
                        fontWeight: mode == current
                            ? FontWeight.w700
                            : FontWeight.w500)),
              ],
            ),
          ),
      ],
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        radius: AppTheme.radiusPill,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_iconFor(current), size: 16, color: AppTheme.primary),
            const SizedBox(width: 7),
            Text(current.label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textHi)),
            const Icon(Icons.expand_more, size: 16, color: AppTheme.textLow),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.frame,
      required this.output,
      required this.face,
      required this.settings});

  final HandFrame frame;
  final GestureOutput output;
  final FaceFrame face;
  final SynthSettings settings;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pills = <Widget>[];

    if (settings.gestureMode != GestureMode.face) {
      final int n = frame.hands.length;
      pills.add(StatusPill(
        icon: Icons.back_hand_outlined,
        label: '$n hand${n == 1 ? '' : 's'}',
        accent: n > 0 ? AppTheme.primary : null,
      ));
    }

    if (settings.gestureMode == GestureMode.discretePoses) {
      final Iterable<String> poses = output.poses
          .where((HandPose p) => p != HandPose.none)
          .map((HandPose p) => p.label);
      if (poses.isNotEmpty) {
        pills.add(StatusPill(
            icon: Icons.gesture, label: poses.join(' · '), accent: AppTheme.secondary));
      }
    }

    if (output.thereminVolume != null) {
      pills.add(StatusPill(
        icon: Icons.volume_up_outlined,
        label: 'vol ${(output.thereminVolume! * 100).round()}%',
        accent: AppTheme.primary,
      ));
    }

    if (settings.faceControlEnabled ||
        settings.gestureMode == GestureMode.face) {
      if (face.present) {
        final FaceSignal sig = settings.gestureMode == GestureMode.face
            ? FaceSignal.mouthOpen
            : settings.faceSignal;
        final double v = face.signal(sig) ?? 0.0;
        pills.add(StatusPill(
          icon: Icons.face_retouching_natural,
          label: 'face ${(v * 100).round()}%',
          accent: AppTheme.success,
        ));
      } else {
        pills.add(const StatusPill(
          icon: Icons.face_retouching_off,
          label: 'no face',
          accent: AppTheme.warning,
        ));
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }
}
