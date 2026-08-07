/// Normalized hand-tracking data structures, decoupled from the underlying
/// `hand_landmarker` plugin types so the rest of the app depends only on this.
library;

/// A single 3D landmark in normalized image space.
///
/// [x] and [y] are 0..1 relative to the (already display-oriented) image;
/// [z] is relative depth (smaller == closer to the camera).
class HandLandmark {
  const HandLandmark(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// One detected hand: 21 [landmarks] plus best-guess handedness.
class Hand {
  const Hand({required this.landmarks, this.isRight = true});

  /// Exactly 21 landmarks in MediaPipe order (see index constants below).
  final List<HandLandmark> landmarks;

  /// Whether the model labelled this the right hand (mirrored front cameras
  /// make this approximate — treat as a hint, not ground truth).
  final bool isRight;

  HandLandmark operator [](int index) => landmarks[index];

  bool get isValid => landmarks.length == 21;
}

/// A frame of hand tracking results.
class HandFrame {
  const HandFrame({
    required this.hands,
    required this.imageWidth,
    required this.imageHeight,
  });

  const HandFrame.empty()
      : hands = const <Hand>[],
        imageWidth = 0,
        imageHeight = 0;

  final List<Hand> hands;
  final int imageWidth;
  final int imageHeight;

  bool get hasHands => hands.isNotEmpty;
}

// -- MediaPipe hand landmark indices -----------------------------------------

const int kWrist = 0;

const int kThumbCmc = 1;
const int kThumbMcp = 2;
const int kThumbIp = 3;
const int kThumbTip = 4;

const int kIndexMcp = 5;
const int kIndexPip = 6;
const int kIndexDip = 7;
const int kIndexTip = 8;

const int kMiddleMcp = 9;
const int kMiddlePip = 10;
const int kMiddleDip = 11;
const int kMiddleTip = 12;

const int kRingMcp = 13;
const int kRingPip = 14;
const int kRingDip = 15;
const int kRingTip = 16;

const int kPinkyMcp = 17;
const int kPinkyPip = 18;
const int kPinkyDip = 19;
const int kPinkyTip = 20;

/// Tip landmark index for each of the five fingers (thumb .. pinky).
const List<int> kFingerTips = <int>[
  kThumbTip,
  kIndexTip,
  kMiddleTip,
  kRingTip,
  kPinkyTip,
];

/// PIP (or thumb IP) landmark index for each finger, aligned with [kFingerTips].
const List<int> kFingerPips = <int>[
  kThumbIp,
  kIndexPip,
  kMiddlePip,
  kRingPip,
  kPinkyPip,
];

/// MCP landmark index for each finger, aligned with [kFingerTips].
const List<int> kFingerMcps = <int>[
  kThumbMcp,
  kIndexMcp,
  kMiddleMcp,
  kRingMcp,
  kPinkyMcp,
];

/// Bone connections used to draw the hand skeleton overlay.
const List<List<int>> kHandConnections = <List<int>>[
  // Thumb
  <int>[0, 1], <int>[1, 2], <int>[2, 3], <int>[3, 4],
  // Index
  <int>[0, 5], <int>[5, 6], <int>[6, 7], <int>[7, 8],
  // Middle
  <int>[9, 10], <int>[10, 11], <int>[11, 12],
  // Ring
  <int>[13, 14], <int>[14, 15], <int>[15, 16],
  // Pinky
  <int>[0, 17], <int>[17, 18], <int>[18, 19], <int>[19, 20],
  // Palm
  <int>[5, 9], <int>[9, 13], <int>[13, 17],
];
