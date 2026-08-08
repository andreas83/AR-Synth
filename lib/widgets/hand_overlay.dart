import 'package:flutter/material.dart';

import '../models/hand_data.dart';
import '../services/gesture_mapper.dart';
import '../theme.dart';
import '../utils/constants.dart';
import '../utils/overlay_transform.dart';

/// Draws the hand skeleton, fingertip cursors and gesture guide lines on top of
/// the camera preview. Landmark/cursor coordinates arrive in `hand_landmarker`'s
/// raw sensor space and are mapped into preview-aligned display space via
/// [displayPoint] (see [sensorOrientation] / [frontCamera]).
class HandOverlayPainter extends CustomPainter {
  HandOverlayPainter({
    required this.frame,
    required this.output,
    required this.sensorOrientation,
    required this.frontCamera,
  });

  final HandFrame frame;
  final GestureOutput output;

  /// Camera sensor mount orientation (0/90/180/270), used to un-rotate landmarks.
  final int sensorOrientation;

  /// Whether the active camera is front-facing (preview is mirrored).
  final bool frontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    _drawHandpan(canvas, size);
    _drawSkeletons(canvas, size);
    _drawGuideLines(canvas, size);
    _drawCursors(canvas, size);
  }

  /// Draws the handpan tone fields (handpan mode) behind the hand skeleton. Each
  /// field brightens while a fingertip is resting on it; the Ding is larger and
  /// tinted with the secondary accent.
  void _drawHandpan(Canvas canvas, Size size) {
    if (output.fields.isEmpty) return;
    final double r = size.shortestSide * 0.11;
    for (final HandpanField f in output.fields) {
      final Offset c = _n(f.x, f.y, size);
      final bool touched = output.heldNotes.contains(f.note);
      final Color accent = f.isDing ? AppTheme.secondary : AppTheme.primary;
      final double radius = f.isDing ? r * 1.18 : r;
      canvas.drawCircle(
        c,
        radius,
        Paint()..color = accent.withValues(alpha: touched ? 0.5 : 0.14),
      );
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = touched ? 3 : 1.5
          ..color = accent.withValues(alpha: touched ? 0.95 : 0.5),
      );
      _label(canvas, f.note.name, c + const Offset(-9, -8),
          Colors.white.withValues(alpha: 0.92));
    }
  }

  /// Landmark -> preview-aligned pixel offset.
  Offset _p(HandLandmark lm, Size size) => _n(lm.x, lm.y, size);

  void _drawSkeletons(Canvas canvas, Size size) {
    final Paint bone = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final Paint joint = Paint()..color = Colors.white.withValues(alpha: 0.9);

    for (final Hand hand in frame.hands) {
      if (!hand.isValid) continue;
      for (final List<int> c in kHandConnections) {
        canvas.drawLine(_p(hand[c[0]], size), _p(hand[c[1]], size), bone);
      }
      for (final HandLandmark lm in hand.landmarks) {
        canvas.drawCircle(_p(lm, size), 3, joint);
      }
    }
  }

  void _drawGuideLines(Canvas canvas, Size size) {
    // Air-piano press line. It's a horizontal threshold in raw landmark space;
    // map both ends through the same transform so it stays aligned with the
    // (rotated/mirrored) skeleton instead of cutting across it.
    final double? pressY = output.pressLineY;
    if (pressY != null) {
      final Paint line = Paint()
        ..color = AppTheme.primary.withValues(alpha: 0.8)
        ..strokeWidth = 2;
      final Offset a = _n(0, pressY, size);
      final Offset b = _n(1, pressY, size);
      canvas.drawLine(a, b, line);
      _label(canvas, 'press below', a + const Offset(8, 4),
          AppTheme.primary.withValues(alpha: 0.9));
    }
  }

  /// Normalized (0..1) point -> preview-aligned pixel offset.
  Offset _n(double x, double y, Size size) {
    final Offset d = displayPoint(x, y, sensorOrientation, frontCamera);
    return Offset(d.dx * size.width, d.dy * size.height);
  }

  void _drawCursors(Canvas canvas, Size size) {
    for (final FingerCursor c in output.cursors) {
      final Color color = kFingerColors[c.colorIndex.clamp(0, 4)];
      final Offset p = _n(c.x, c.y, size);
      final double r = c.pressing ? 18 : 12;
      canvas.drawCircle(
        p,
        r,
        Paint()..color = color.withValues(alpha: c.pressing ? 0.9 : 0.5),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      if (c.note != null) {
        _label(canvas, c.note!.name, p + const Offset(14, -8), Colors.white);
      }
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant HandOverlayPainter old) => true;
}
