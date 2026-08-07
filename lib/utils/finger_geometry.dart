import 'dart:math' as math;

import '../models/hand_data.dart';

/// Geometric helpers that turn raw landmarks into meaningful finger state.
/// All work in the normalized 0..1 landmark space.
class FingerGeometry {
  const FingerGeometry._();

  static double _dist(HandLandmark a, HandLandmark b) {
    final double dx = a.x - b.x;
    final double dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Characteristic hand size (wrist → middle-finger MCP), used to normalize
  /// thresholds so they hold at any distance from the camera.
  static double handScale(Hand hand) {
    final double s = _dist(hand[kWrist], hand[kMiddleMcp]);
    return s < 1e-4 ? 1e-4 : s;
  }

  /// Whether a finger (0=thumb .. 4=pinky) is extended.
  ///
  /// For the four fingers this compares tip vs PIP distance from the wrist.
  /// The thumb is handled separately via lateral spread from the index MCP.
  static bool isFingerExtended(Hand hand, int finger) {
    if (finger == 0) return isThumbExtended(hand);
    final HandLandmark wrist = hand[kWrist];
    final HandLandmark tip = hand[kFingerTips[finger]];
    final HandLandmark pip = hand[kFingerPips[finger]];
    // Extended when the tip reaches noticeably farther from the wrist than the
    // PIP joint does.
    return _dist(tip, wrist) > _dist(pip, wrist) * 1.05;
  }

  static bool isThumbExtended(Hand hand) {
    final double spread = _dist(hand[kThumbTip], hand[kIndexMcp]);
    return spread > handScale(hand) * 0.7;
  }

  /// Count of extended fingers (0..5).
  static int extendedFingerCount(Hand hand) {
    int count = 0;
    for (int f = 0; f < 5; f++) {
      if (isFingerExtended(hand, f)) count++;
    }
    return count;
  }

  /// Per-finger extension flags [thumb, index, middle, ring, pinky].
  static List<bool> extendedFingers(Hand hand) =>
      List<bool>.generate(5, (int f) => isFingerExtended(hand, f));

  /// Normalized curl for a finger: 0 == fully straight, ~1 == fully curled.
  /// Measured as how much shorter the tip→wrist span is than tip along the
  /// fully-extended chain.
  static double curl(Hand hand, int finger) {
    final HandLandmark wrist = hand[kWrist];
    final HandLandmark mcp = hand[kFingerMcps[finger]];
    final HandLandmark tip = hand[kFingerTips[finger]];
    final double straight = _dist(mcp, wrist) + _dist(tip, mcp);
    if (straight < 1e-4) return 0;
    final double actual = _dist(tip, wrist);
    final double ratio = 1.0 - (actual / straight);
    return ratio.clamp(0.0, 1.0);
  }

  /// Distance between thumb tip and index tip, normalized by hand size.
  /// Small values indicate a pinch.
  static double pinchDistance(Hand hand) =>
      _dist(hand[kThumbTip], hand[kIndexTip]) / handScale(hand);

  static bool isPinching(Hand hand, {double threshold = 0.35}) =>
      pinchDistance(hand) < threshold;

  /// A single fingertip position (normalized) for a given finger.
  static HandLandmark tip(Hand hand, int finger) => hand[kFingerTips[finger]];
}

/// A recognised static hand pose for the discrete-gesture mode.
enum HandPose { none, fist, point, peace, openHand, thumbsUp }

extension HandPoseLabel on HandPose {
  String get label => switch (this) {
        HandPose.none => 'None',
        HandPose.fist => 'Fist',
        HandPose.point => 'Point',
        HandPose.peace => 'Peace',
        HandPose.openHand => 'Open Hand',
        HandPose.thumbsUp => 'Thumbs Up',
      };
}

/// Classifies a hand into one of the [HandPose]s using finger extension flags.
HandPose classifyPose(Hand hand) {
  if (!hand.isValid) return HandPose.none;
  final List<bool> ext = FingerGeometry.extendedFingers(hand);
  final bool thumb = ext[0];
  final bool index = ext[1];
  final bool middle = ext[2];
  final bool ring = ext[3];
  final bool pinky = ext[4];
  final int count = ext.where((bool e) => e).length;

  if (count == 0) return HandPose.fist;
  if (count >= 4) return HandPose.openHand;
  if (thumb && !index && !middle && !ring && !pinky) return HandPose.thumbsUp;
  if (index && !middle && !ring && !pinky) return HandPose.point;
  if (index && middle && !ring && !pinky) return HandPose.peace;
  return HandPose.none;
}
