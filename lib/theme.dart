import 'package:flutter/material.dart';

/// A dark, neon-tinged theme suited to a synth/instrument app.
///
/// Deliberately conservative: only widely-available [ThemeData] fields are set
/// so the app compiles across a broad range of Flutter stable versions.
class AppTheme {
  static const Color bg = Color(0xFF0E1015);
  static const Color surface = Color(0xFF171A21);
  static const Color primary = Color(0xFF40C4FF);
  static const Color secondary = Color(0xFFE040FB);

  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
