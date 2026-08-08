import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/music.dart';
import '../models/synth_settings.dart';
import '../services/audio_engine.dart';
import '../state/settings_controller.dart';
import '../theme.dart';
import 'ui_kit.dart';

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

          const Divider(height: 32),
          _label('Low-pass filter'),
          _switchRow('Enable filter', s.filterEnabled, c.setFilterEnabled),
          if (s.filterEnabled) ...<Widget>[
            _slider('Cutoff', s.filterCutoff, c.setFilterCutoff),
            _slider('Resonance', s.filterResonance, c.setFilterResonance),
          ],
          _switchRow('LFO sweep', s.lfoEnabled, c.setLfoEnabled),
          if (s.lfoEnabled) ...<Widget>[
            _slider('LFO rate', s.lfoRateHz, c.setLfoRateHz,
                min: 0.1, max: 12.0),
            _slider('LFO depth', s.lfoDepth, c.setLfoDepth),
          ],
          _switchRow('Pinch → cutoff (free hand)', s.pinchModEnabled,
              c.setPinchModEnabled),

          const Divider(height: 32),
          _label('Performance'),
          _switchRow('Velocity (tap speed)', s.velocityEnabled,
              c.setVelocityEnabled),
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<String>(
                  'Scale',
                  s.scaleName,
                  kScales.keys.toList(growable: false),
                  (String v) => v,
                  c.setScaleName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  'Key',
                  s.keyRoot,
                  List<int>.generate(12, (int i) => i),
                  (int v) => kPitchClassNames[v],
                  c.setKeyRoot,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Scale + key apply to Air Piano lanes; key also transposes the '
            'handpan.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),

          const Divider(height: 32),
          _label('Arpeggiator'),
          _switchRow('Enable arpeggiator', s.arpEnabled, c.setArpEnabled),
          if (s.arpEnabled) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _dropdown<ArpPattern>(
                    'Pattern',
                    s.arpPattern,
                    ArpPattern.values,
                    (ArpPattern v) => v.label,
                    c.setArpPattern,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dropdown<ArpRate>(
                    'Rate',
                    s.arpRate,
                    ArpRate.values,
                    (ArpRate v) => v.label,
                    c.setArpRate,
                  ),
                ),
              ],
            ),
            _slider('Tempo (BPM)', s.bpm, c.setBpm, min: 40, max: 240),
            _slider('Gate', s.arpGate, c.setArpGate, min: 0.05, max: 0.95),
          ],

          const Divider(height: 32),
          _label('Face control (experimental)'),
          _switchRow('Enable face modulation', s.faceControlEnabled,
              c.setFaceControlEnabled),
          if (s.faceControlEnabled) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _dropdown<FaceSignal>(
                    'Expression',
                    s.faceSignal,
                    FaceSignal.values,
                    (FaceSignal v) => v.label,
                    c.setFaceSignal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dropdown<FaceTarget>(
                    'Controls',
                    s.faceTarget,
                    FaceTarget.values,
                    (FaceTarget v) => v.label,
                    c.setFaceTarget,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Uses the front camera; open your mouth / smile / tilt your head '
              'to sweep the chosen parameter.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],

          const Divider(height: 32),
          _label('Visuals'),
          _switchRow('Note-ripple visualizer', s.visualizerEnabled,
              c.setVisualizerEnabled),
        ],
      ),
    );
  }

  Widget _label(String text) => SectionHeader(text);

  Widget _slider(String label, double value, ValueChanged<double> onChanged,
      {double min = 0.0, double max = 1.0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.textMed)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          Container(
            width: 48,
            alignment: Alignment.centerRight,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                color: AppTheme.textHi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: AppTheme.textHi)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> items,
    String Function(T) labelOf,
    ValueChanged<T> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 4),
        DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: <DropdownMenuItem<T>>[
            for (final T item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(labelOf(item)),
              ),
          ],
          onChanged: (T? v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
