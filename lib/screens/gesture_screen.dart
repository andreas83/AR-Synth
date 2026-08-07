import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/hand_data.dart';
import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/gesture_mapper.dart';
import '../services/hand_tracking_service.dart';
import '../state/piano_controller.dart';
import '../state/settings_controller.dart';
import '../theme.dart';
import '../utils/finger_geometry.dart';
import '../widgets/hand_overlay.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/synth_controls.dart';

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
    with WidgetsBindingObserver {
  final HandTrackingService _service = HandTrackingService();
  final GestureMapper _mapper = GestureMapper();
  StreamSubscription<HandFrame>? _sub;

  HandFrame _frame = const HandFrame.empty();
  GestureOutput _output = GestureOutput.empty;
  GestureMode? _lastMode;
  bool _starting = true;

  PianoController? _piano;
  SettingsController? _settingsController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = _service.frames.listen(_onFrame);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _piano = context.read<PianoController>();
    _settingsController = context.read<SettingsController>();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
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
    }
    final GestureOutput output = _mapper.map(frame, settings);
    _piano?.applyGesture(output);
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
    _sub?.cancel();
    _service.dispose();
    _piano?.clearGesture();
    super.dispose();
  }

  void _openSynthSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        backgroundColor: Colors.black.withValues(alpha: 0.25),
        title: const Text('Gesture'),
        actions: <Widget>[
          // Quick gesture-mode switch.
          PopupMenuButton<GestureMode>(
            icon: const Icon(Icons.back_hand),
            tooltip: 'Gesture mode: ${s.gestureMode.label}',
            initialValue: s.gestureMode,
            onSelected: settings.setGestureMode,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<GestureMode>>[
              for (final GestureMode mode in GestureMode.values)
                PopupMenuItem<GestureMode>(
                  value: mode,
                  child: Text(mode.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Synth controls',
            onPressed: _openSynthSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSynthSheet,
        icon: const Icon(Icons.graphic_eq),
        label: const Text('Synth'),
      ),
      body: _buildBody(s),
    );
  }

  /// Quarter-turns needed to display the raw (landscape) sensor frame upright
  /// while the app is locked to portrait. Derived from the camera's sensor
  /// mount orientation. If the preview ends up upside-down on a given device,
  /// this is the single knob to adjust (add 2).
  int _previewQuarterTurns() {
    final int sensor = _service.sensorOrientation;
    final int degrees =
        _service.isFrontCamera ? (360 - sensor) % 360 : sensor % 360;
    return (degrees ~/ 90) % 4;
  }

  Widget _buildBody(SynthSettings s) {
    final TrackingStatus status = _service.status;
    final CameraController? controller = _service.controller;

    if (_starting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status != TrackingStatus.running ||
        controller == null ||
        !controller.value.isInitialized) {
      return _buildUnavailable(status);
    }

    return Stack(
      children: <Widget>[
        // Camera preview + hand overlay. The raw sensor frame is landscape, so
        // in a portrait-locked app it would appear sideways. We rotate the
        // preview and the overlay TOGETHER (they share the same normalized
        // sensor space, so they stay aligned) to display upright. The outer
        // AspectRatio gives a portrait box; RotatedBox swaps the child
        // constraints back to the sensor's landscape aspect, so nothing is
        // stretched.
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: RotatedBox(
                  quarterTurns: _previewQuarterTurns(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      controller.buildPreview(),
                      CustomPaint(
                        painter: HandOverlayPainter(
                            frame: _frame, output: _output),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Status chips.
        Positioned(
          top: kToolbarHeight + 28,
          left: 12,
          right: 12,
          child: _StatusBar(frame: _frame, output: _output, settings: s),
        ),
        // Keyboard highlight strip (non-interactive display of what's playing).
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 96,
              child: PianoKeyboard(
                notes: buildKeyboard(
                    startOctave: s.startOctave, octaves: s.octaves),
                activeNotes: context.watch<PianoController>().activeNotes,
                interactive: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailable(TrackingStatus status) {
    final (IconData icon, String message) = switch (status) {
      TrackingStatus.denied => (
          Icons.no_photography,
          'Camera permission is required for gesture mode. '
              'Grant it in system settings, then retry.'
        ),
      TrackingStatus.unsupported => (
          Icons.phonelink_erase,
          'Hand tracking is only available on Android.'
        ),
      _ => (
          Icons.error_outline,
          _service.error ?? 'Could not start the camera.'
        ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: Colors.white38),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(
      {required this.frame, required this.output, required this.settings});

  final HandFrame frame;
  final GestureOutput output;
  final SynthSettings settings;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = <String>[
      settings.gestureMode.label,
      '${frame.hands.length} hand${frame.hands.length == 1 ? '' : 's'}',
    ];
    if (settings.gestureMode == GestureMode.discretePoses) {
      final Iterable<String> poses = output.poses
          .where((HandPose p) => p != HandPose.none)
          .map((HandPose p) => p.label);
      if (poses.isNotEmpty) chips.add(poses.join(' · '));
    }
    if (output.thereminVolume != null) {
      chips.add('vol ${(output.thereminVolume! * 100).round()}%');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String c in chips)
          Chip(
            label: Text(c),
            visualDensity: VisualDensity.compact,
            backgroundColor: AppTheme.surface.withValues(alpha: 0.8),
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
          ),
      ],
    );
  }
}
