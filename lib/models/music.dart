import 'dart:math' as math;

/// Note names for the 12 chromatic pitch classes (sharps).
const List<String> kPitchClassNames = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Pitch classes that are rendered as black keys.
const Set<int> kBlackPitchClasses = <int>{1, 3, 6, 8, 10};

/// A single musical note identified by its MIDI number.
///
/// MIDI 69 == A4 == 440 Hz, which anchors the equal-temperament formula.
class Note {
  const Note(this.midi);

  /// MIDI note number (0-127). 60 == C4 (middle C).
  final int midi;

  /// Pitch class 0..11 (0 == C).
  int get pitchClass => midi % 12;

  /// Octave number using scientific pitch notation (C4 == middle C).
  int get octave => (midi ~/ 12) - 1;

  /// Whether this note is a black (accidental) key.
  bool get isBlack => kBlackPitchClasses.contains(pitchClass);

  /// Human readable name, e.g. "C#4".
  String get name => '${kPitchClassNames[pitchClass]}$octave';

  /// Fundamental frequency in Hz using 12-tone equal temperament (A4 = 440 Hz).
  double get frequency => 440.0 * math.pow(2, (midi - 69) / 12.0).toDouble();

  Note transpose(int semitones) => Note(midi + semitones);

  @override
  bool operator ==(Object other) => other is Note && other.midi == midi;

  @override
  int get hashCode => midi.hashCode;

  @override
  String toString() => 'Note($name, midi=$midi, ${frequency.toStringAsFixed(1)}Hz)';
}

/// Builds an ordered list of [Note]s spanning [octaves] starting at
/// [startOctave], beginning on C. Used to lay out the on-screen keyboard.
List<Note> buildKeyboard({int startOctave = 4, int octaves = 2}) {
  final int startMidi = (startOctave + 1) * 12; // C of the start octave.
  return List<Note>.generate(
    octaves * 12,
    (int i) => Note(startMidi + i),
    growable: false,
  );
}

/// The white keys within [notes], preserving order.
List<Note> whiteKeysOf(List<Note> notes) =>
    notes.where((Note n) => !n.isBlack).toList(growable: false);

/// Common diatonic scales expressed as semitone offsets from the tonic.
/// Used by the theremin gesture mode to quantize continuous pitch.
const Map<String, List<int>> kScales = <String, List<int>>{
  'Chromatic': <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  'Major': <int>[0, 2, 4, 5, 7, 9, 11],
  'Minor': <int>[0, 2, 3, 5, 7, 8, 10],
  'Pentatonic': <int>[0, 2, 4, 7, 9],
  'Blues': <int>[0, 3, 5, 6, 7, 10],
};

/// Handpan (a.k.a. "hang") tunings as semitone offsets from the central Ding
/// (index 0 is always the Ding). A handpan is a melodic steel percussion
/// instrument: a deep central note surrounded by a ring of tone fields tuned to
/// a scale. These are common commercial layouts; the concrete pitches are set
/// by the chosen key + start octave, so e.g. "D Kurd" is the interval structure,
/// transposed to whatever key the user picks.
const Map<String, List<int>> kHandpanTunings = <String, List<int>>{
  // Ding + 8 fields. The classic first handpan; a warm natural-minor sound.
  'Kurd 9': <int>[0, 7, 8, 10, 12, 14, 15, 17, 19],
  // Ding + 8 fields. Bright, wistful minor-with-a-major-6th feel.
  'Celtic Minor 9': <int>[0, 7, 10, 12, 14, 15, 17, 19, 22],
  // Ding + 8 fields. A Phrygian-dominant scale with an exotic augmented 2nd.
  'Hijaz 9': <int>[0, 7, 8, 11, 12, 14, 15, 17, 19],
  // Ding + 7 fields. An open, consonant major-pentatonic layout.
  'Pentatonic 8': <int>[0, 7, 9, 12, 14, 16, 19, 21],
  // Ding + 7 fields. Kurd's smaller sibling.
  'Amara 8': <int>[0, 7, 8, 10, 12, 14, 15, 17],
};

/// Snaps [midi] down to the nearest note that belongs to [scale] rooted at
/// [rootPitchClass]. Falls back to [midi] when the scale is empty.
int quantizeToScale(int midi, List<int> scale, {int rootPitchClass = 0}) {
  if (scale.isEmpty) return midi;
  for (int delta = 0; delta < 12; delta++) {
    final int candidate = midi - delta;
    final int rel = ((candidate - rootPitchClass) % 12 + 12) % 12;
    if (scale.contains(rel)) return candidate;
  }
  return midi;
}
