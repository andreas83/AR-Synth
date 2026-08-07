import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/synth_settings.dart';
import '../services/audio_engine.dart';
import '../state/settings_controller.dart';

/// Compact synth control panel: engine, waveform, octave, ADSR and effects.
/// Reads/writes through [SettingsController] so changes are live + persisted.
class SynthControls extends StatelessWidget {
  const SynthControls({super.key, this.showEngineToggle = true});

  final bool showEngineToggle;

  @override
  Widget build(BuildContext context) {
    final SettingsController c = context.watch<SettingsController>();
    final SynthSettings s = c.settings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showEngineToggle) ...<Widget>[
            _label('Sound engine'),
            SegmentedButton<SoundEngine>(
              segments: const <ButtonSegment<SoundEngine>>[
                ButtonSegment<SoundEngine>(
                    value: SoundEngine.synth,
                    label: Text('Synth'),
                    icon: Icon(Icons.graphic_eq)),
                ButtonSegment<SoundEngine>(
                    value: SoundEngine.sample,
                    label: Text('Piano'),
                    icon: Icon(Icons.piano)),
              ],
              selected: <SoundEngine>{s.engine},
              onSelectionChanged: (Set<SoundEngine> v) =>
                  c.setEngine(v.first),
            ),
            if (s.engine == SoundEngine.sample &&
                !context.read<AudioEngine>().hasSamples)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No piano samples bundled — using the synth as a fallback. '
                  'Run scripts/fetch_samples.sh to add them.',
                  style: TextStyle(fontSize: 12, color: Colors.orangeAccent),
                ),
              ),
            const SizedBox(height: 16),
          ],
          if (s.engine == SoundEngine.synth) ...<Widget>[
            _label('Waveform'),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final SynthWave w in SynthWave.values)
                  ChoiceChip(
                    label: Text(w.label),
                    selected: s.wave == w,
                    onSelected: (_) => c.setWave(w),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _label('Octave shift: ${s.octaveShift > 0 ? '+' : ''}${s.octaveShift}'),
          Row(
            children: <Widget>[
              IconButton.filledTonal(
                onPressed: () => c.setOctaveShift(s.octaveShift - 1),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => c.setOctaveShift(s.octaveShift + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _slider('Master volume', s.masterVolume, (double v) => c.setMasterVolume(v)),
          const Divider(height: 32),
          _label('Envelope (ADSR)'),
          _slider('Attack', s.adsr.attack, (double v) => c.setAdsr(s.adsr.copyWith(attack: v)),
              max: 2.0),
          _slider('Decay', s.adsr.decay, (double v) => c.setAdsr(s.adsr.copyWith(decay: v)),
              max: 2.0),
          _slider('Sustain', s.adsr.sustain, (double v) => c.setAdsr(s.adsr.copyWith(sustain: v))),
          _slider('Release', s.adsr.release, (double v) => c.setAdsr(s.adsr.copyWith(release: v)),
              max: 3.0),
          const Divider(height: 32),
          _label('Effects'),
          _slider('Reverb', s.reverb, (double v) => c.setReverb(v)),
          _slider('Echo', s.echo, (double v) => c.setEcho(v)),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _slider(String label, double value, ValueChanged<double> onChanged,
      {double min = 0.0, double max = 1.0}) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      ],
    );
  }
}
