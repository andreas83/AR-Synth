import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ar_synth/models/music.dart';
import 'package:ar_synth/theme.dart';
import 'package:ar_synth/widgets/piano_keyboard.dart';
import 'package:ar_synth/widgets/ui_kit.dart';

/// Render smoke tests: the polished widgets must paint under the app theme
/// (in a tight app-bar-sized box for the wordmark) without throwing.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('UI kit widgets render without exceptions', (WidgetTester t) async {
    await t.pumpWidget(host(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(width: 140, child: BrandMark(fontSize: 18)),
          const SectionHeader('Envelope (ADSR)'),
          const StatusPill(
              icon: Icons.face_retouching_natural,
              label: 'face 82%',
              accent: AppTheme.success),
          GradientButton(
              onPressed: () {}, icon: Icons.graphic_eq, label: 'Synth'),
        ],
      ),
    ));
    await t.pump();
    expect(noPendingException(), isTrue);
    expect(find.text('Synth'), findsOneWidget);
  });

  testWidgets('Piano keyboard renders pressed + unpressed keys',
      (WidgetTester t) async {
    final List<Note> notes = buildKeyboard(startOctave: 4, octaves: 2);
    await t.pumpWidget(host(
      SizedBox(
        width: 360,
        height: 90,
        child: PianoKeyboard(
          notes: notes,
          activeNotes: <Note>{notes.first, notes[3]},
          interactive: false,
        ),
      ),
    ));
    await t.pump();
    expect(noPendingException(), isTrue);
  });
}

/// True when no widget-build/paint exception has been recorded.
bool noPendingException() =>
    TestWidgetsFlutterBinding.instance.takeException() == null;
