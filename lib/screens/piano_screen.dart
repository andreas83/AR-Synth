import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';
import '../state/piano_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/synth_controls.dart';

/// On-screen touch keyboard plus the synth control panel. Works on every
/// platform (no camera required).
class PianoScreen extends StatefulWidget {
  const PianoScreen({super.key});

  @override
  State<PianoScreen> createState() => _PianoScreenState();
}

class _PianoScreenState extends State<PianoScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    context.read<PianoController>().releaseAllTouch();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final SynthSettings s = settings.settings;
    final PianoController piano = context.watch<PianoController>();
    final List<Note> keyboard =
        buildKeyboard(startOctave: s.startOctave, octaves: s.octaves);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Touch Piano'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'All notes off',
            onPressed: piano.releaseAllTouch,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const Expanded(
            child: SingleChildScrollView(child: SynthControls()),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: SizedBox(
                height: 220,
                child: PianoKeyboard(
                  notes: keyboard,
                  activeNotes: piano.activeNotes,
                  onNoteOn: piano.pressNote,
                  onNoteOff: piano.releaseNote,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
