import 'package:flutter/material.dart';

import '../models/music.dart';
import '../theme.dart';

/// A multi-touch piano keyboard. White keys fill the width; black keys are
/// overlaid at the correct positions. Notes highlighted via [activeNotes] are
/// drawn pressed (used both for touch feedback and gesture playback display).
class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({
    super.key,
    required this.notes,
    required this.activeNotes,
    this.onNoteOn,
    this.onNoteOff,
    this.interactive = true,
  });

  final List<Note> notes;
  final Set<Note> activeNotes;
  final ValueChanged<Note>? onNoteOn;
  final ValueChanged<Note>? onNoteOff;

  /// When false the keyboard is display-only (no touch handling).
  final bool interactive;

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  /// Which note each active pointer is currently pressing.
  final Map<int, Note> _pointerNotes = <int, Note>{};

  List<Note> get _whites => whiteKeysOf(widget.notes);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final List<Note> whites = _whites;
        if (whites.isEmpty) return const SizedBox.shrink();
        final double whiteW = w / whites.length;

        final Widget keyboard = Stack(
          children: <Widget>[
            _buildWhiteKeys(whites, whiteW, h),
            ..._buildBlackKeys(whites, whiteW, h),
          ],
        );

        if (!widget.interactive) return keyboard;

        return Listener(
          onPointerDown: (PointerDownEvent e) =>
              _handlePointer(e.pointer, e.localPosition, whites, whiteW, h),
          onPointerMove: (PointerMoveEvent e) =>
              _handlePointer(e.pointer, e.localPosition, whites, whiteW, h),
          onPointerUp: (PointerUpEvent e) => _releasePointer(e.pointer),
          onPointerCancel: (PointerCancelEvent e) => _releasePointer(e.pointer),
          child: keyboard,
        );
      },
    );
  }

  Widget _buildWhiteKeys(List<Note> whites, double whiteW, double h) {
    return Row(
      children: <Widget>[
        for (final Note note in whites)
          _KeyFace(
            width: whiteW,
            height: h,
            note: note,
            pressed: widget.activeNotes.contains(note),
            isBlack: false,
          ),
      ],
    );
  }

  List<Widget> _buildBlackKeys(List<Note> whites, double whiteW, double h) {
    final double blackW = whiteW * 0.62;
    final double blackH = h * 0.62;
    final List<Widget> result = <Widget>[];
    for (int i = 0; i < whites.length - 1; i++) {
      final Note white = whites[i];
      // A black key sits between this white key and the next one iff the
      // semitone above this white key is itself a black key.
      final Note candidate = Note(white.midi + 1);
      if (!candidate.isBlack) continue;
      final double centerX = (i + 1) * whiteW;
      result.add(Positioned(
        left: centerX - blackW / 2,
        top: 0,
        width: blackW,
        height: blackH,
        child: _KeyFace(
          width: blackW,
          height: blackH,
          note: candidate,
          pressed: widget.activeNotes.contains(candidate),
          isBlack: true,
        ),
      ));
    }
    return result;
  }

  Note? _noteAt(Offset pos, List<Note> whites, double whiteW, double h) {
    // Black keys take priority in their (upper) region.
    final double blackW = whiteW * 0.62;
    final double blackH = h * 0.62;
    if (pos.dy <= blackH) {
      for (int i = 0; i < whites.length - 1; i++) {
        final Note candidate = Note(whites[i].midi + 1);
        if (!candidate.isBlack) continue;
        final double centerX = (i + 1) * whiteW;
        if ((pos.dx - centerX).abs() <= blackW / 2) return candidate;
      }
    }
    final int index = (pos.dx / whiteW).floor().clamp(0, whites.length - 1);
    return whites[index];
  }

  void _handlePointer(
      int pointer, Offset pos, List<Note> whites, double whiteW, double h) {
    final Note? note = _noteAt(pos, whites, whiteW, h);
    if (note == null) return;
    final Note? previous = _pointerNotes[pointer];
    if (previous == note) return;
    if (previous != null) widget.onNoteOff?.call(previous);
    _pointerNotes[pointer] = note;
    widget.onNoteOn?.call(note);
  }

  void _releasePointer(int pointer) {
    final Note? note = _pointerNotes.remove(pointer);
    if (note != null) widget.onNoteOff?.call(note);
  }
}

class _KeyFace extends StatelessWidget {
  const _KeyFace({
    required this.width,
    required this.height,
    required this.note,
    required this.pressed,
    required this.isBlack,
  });

  final double width;
  final double height;
  final Note note;
  final bool pressed;
  final bool isBlack;

  @override
  Widget build(BuildContext context) {
    final Color base = isBlack ? const Color(0xFF15171C) : const Color(0xFFF3F4F6);
    final Color pressedColor =
        isBlack ? AppTheme.secondary : AppTheme.primary;
    final Color color = pressed ? pressedColor : base;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black.withValues(alpha: 0.55), width: 0.5),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isBlack ? 4 : 6),
        ),
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 6),
      child: (!isBlack && note.pitchClass == 0)
          ? Text(
              note.name,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
