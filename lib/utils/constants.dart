import 'package:flutter/widgets.dart';

/// Shared spacing / sizing constants.
class AppSizes {
  static const double pagePadding = 16.0;
  static const double cardRadius = 16.0;
  static const double keyboardHeight = 220.0;
}

/// Persisted-settings storage key.
const String kSettingsPrefsKey = 'ar_synth.settings.v1';

/// GitHub repository that hosts the releases the in-app updater checks.
const String kGithubOwner = 'andreas83';
const String kGithubRepo = 'AR-Synth';

/// Colors reused across the fingertip overlay / keyboard highlights.
/// Index-aligned with the five fingers (thumb .. pinky).
const List<Color> kFingerColors = <Color>[
  Color(0xFFFF5252), // thumb  - red
  Color(0xFFFFB300), // index  - amber
  Color(0xFF69F0AE), // middle - green
  Color(0xFF40C4FF), // ring   - blue
  Color(0xFFE040FB), // pinky  - purple
];
