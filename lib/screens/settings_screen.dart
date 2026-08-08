import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/update_service.dart';
import '../state/settings_controller.dart';
import '../widgets/synth_controls.dart';
import '../widgets/ui_kit.dart';
import '../widgets/update_dialog.dart';

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
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SectionHeader('Gesture mode'),
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
          if (s.gestureMode == GestureMode.handpan)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  const SizedBox(
                      width: 110,
                      child: Text('Handpan tuning',
                          style: TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: s.handpanTuning,
                    items: <DropdownMenuItem<String>>[
                      for (final String name in kHandpanTunings.keys)
                        DropdownMenuItem<String>(
                            value: name, child: Text(name)),
                    ],
                    onChanged: (String? v) {
                      if (v != null) c.setHandpanTuning(v);
                    },
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SectionHeader('Keyboard range'),
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
          const Divider(height: 8),
          const _AboutSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// App version + manual "check for updates" (the app also checks silently on
/// launch). Restores the control that used to live on the old landing screen.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  final UpdateService _updates = UpdateService();
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // Version is cosmetic; ignore failures.
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final UpdateInfo? update = await _updates.checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);

    if (update != null) {
      await UpdateDialog.show(context, update: update, service: _updates);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SectionHeader('About'),
        ),
        ListTile(
          title: const Text('Check for updates'),
          subtitle:
              Text(_version.isEmpty ? 'AR Synth' : 'Version $_version'),
          trailing: _checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          onTap: _checking ? null : _check,
        ),
      ],
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
