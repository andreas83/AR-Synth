import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';
import '../state/settings_controller.dart';
import '../widgets/synth_controls.dart';

/// Full settings page: gesture mode + keyboard range on top of the shared
/// synth controls.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController c = context.watch<SettingsController>();
    final SynthSettings s = c.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Gesture mode',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          RadioGroup<GestureMode>(
            groupValue: s.gestureMode,
            onChanged: (GestureMode? v) {
              if (v != null) c.setGestureMode(v);
            },
            child: Column(
              children: <Widget>[
                for (final GestureMode mode in GestureMode.values)
                  RadioListTile<GestureMode>(
                    value: mode,
                    title: Text(mode.label),
                    subtitle: Text(mode.description),
                    activeColor: Theme.of(context).colorScheme.secondary,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: <Widget>[
                const SizedBox(
                    width: 110,
                    child: Text('Sensitivity', style: TextStyle(fontSize: 13))),
                Expanded(
                  child: Slider(
                    value: s.gestureSensitivity,
                    onChanged: c.setGestureSensitivity,
                  ),
                ),
              ],
            ),
          ),
          if (s.gestureMode == GestureMode.theremin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  const SizedBox(
                      width: 110,
                      child: Text('Theremin scale',
                          style: TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: s.thereminScale,
                    items: <DropdownMenuItem<String>>[
                      for (final String name in kScales.keys)
                        DropdownMenuItem<String>(
                            value: name, child: Text(name)),
                    ],
                    onChanged: (String? v) {
                      if (v != null) c.setThereminScale(v);
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Keyboard range',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.9))),
          ),
          ListTile(
            title: const Text('Start octave'),
            trailing: _Stepper(
              value: s.startOctave,
              onMinus: () => c.setStartOctave(s.startOctave - 1),
              onPlus: () => c.setStartOctave(s.startOctave + 1),
            ),
          ),
          ListTile(
            title: const Text('Octaves shown'),
            trailing: _Stepper(
              value: s.octaves,
              onMinus: () => c.setOctaves(s.octaves - 1),
              onPlus: () => c.setOctaves(s.octaves + 1),
            ),
          ),
          const Divider(height: 8),
          // Reuse the shared synth panel for engine/waveform/adsr/effects.
          const SynthControls(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.value, required this.onMinus, required this.onPlus});

  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove)),
        Text('$value', style: const TextStyle(fontSize: 16)),
        IconButton(onPressed: onPlus, icon: const Icon(Icons.add)),
      ],
    );
  }
}
