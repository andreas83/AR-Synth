import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A short-lived expanding ring spawned when a note starts, colored by its
/// pitch class. Positions are normalized (0..1) in display space.
class NoteRipple {
  NoteRipple({
    required this.x,
    required this.y,
    required this.pitchClass,
    required this.bornMs,
    this.lifeMs = 900,
  });

  final double x;
  final double y;
  final int pitchClass;
  final int bornMs;
  final int lifeMs;

  double progress(int nowMs) =>
      ((nowMs - bornMs) / lifeMs).clamp(0.0, 1.0).toDouble();

  bool isDead(int nowMs) => nowMs - bornMs >= lifeMs;
}

/// Paints the [ripples], animating against [clockMs] (a monotonically
/// increasing millisecond counter driven by a Ticker). Kept on its own
/// RepaintBoundary so the camera preview doesn't repaint at 60 fps.
class NoteRipplePainter extends CustomPainter {
  NoteRipplePainter({required this.ripples, required this.clockMs})
      : super(repaint: clockMs);

  final List<NoteRipple> ripples;
  final ValueNotifier<int> clockMs;

  /// Maps a pitch class (0..11) to a saturated hue around the color wheel.
  static Color colorForPitch(int pitchClass) => HSVColor.fromAHSV(
        1.0,
        ((pitchClass % 12) / 12.0) * 360.0,
        0.65,
        1.0,
      ).toColor();

  @override
  void paint(Canvas canvas, Size size) {
    final int now = clockMs.value;
    for (final NoteRipple r in ripples) {
      final double t = r.progress(now);
      if (t >= 1.0) continue;
      final double ease = 1.0 - math.pow(1.0 - t, 3).toDouble();
      final Offset c = Offset(r.x * size.width, r.y * size.height);
      final double radius = 12 + ease * 70;
      final double alpha = 1.0 - t;
      final Color col = colorForPitch(r.pitchClass);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 + 3.0 * (1.0 - t)
          ..color = col.withValues(alpha: alpha * 0.9),
      );
      canvas.drawCircle(
        c,
        radius * 0.5,
        Paint()..color = col.withValues(alpha: alpha * 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant NoteRipplePainter old) => true;
}
