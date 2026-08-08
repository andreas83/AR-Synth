import 'package:flutter/material.dart';

/// The AR Synth design system: a dark, neon-tinged "instrument in the dark"
/// look built on Material 3. Centralises the palette, a signature accent
/// gradient, spacing/radius tokens, and component theming so every surface
/// shares one language.
class AppTheme {
  // -- Ground & surfaces ------------------------------------------------------
  /// App background — a near-black blue so neon accents glow against it.
  static const Color bg = Color(0xFF0A0C11);
  static const Color bgElevated = Color(0xFF11141B);

  /// Card / sheet surface and its raised variant.
  static const Color surface = Color(0xFF161A22);
  static const Color surfaceHigh = Color(0xFF1E2430);

  /// Hairline borders drawn on glass panels and cards.
  static const Color outline = Color(0x14FFFFFF); // white @ 8%

  // -- Brand accents ----------------------------------------------------------
  static const Color primary = Color(0xFF3AC9FF); // cyan
  static const Color secondary = Color(0xFFC15CFF); // violet
  static const Color success = Color(0xFF5CE6A8);
  static const Color warning = Color(0xFFFFB74D);

  // -- Text -------------------------------------------------------------------
  static const Color textHi = Color(0xFFF4F6FB);
  static const Color textMed = Color(0xB3FFFFFF); // white @ 70%
  static const Color textLow = Color(0x80FFFFFF); // white @ 50%

  // -- Tokens -----------------------------------------------------------------
  static const double radius = 16;
  static const double radiusLg = 22;
  static const double radiusPill = 999;

  /// Signature accent gradient (cyan → violet), used for the wordmark, the
  /// primary action, and active-state glows.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF37E1FF), Color(0xFF8B5CF6), Color(0xFFE15CFF)],
  );

  /// A soft glow shadow tinted by [color] — used behind active elements.
  static List<BoxShadow> glow(Color color, {double blur = 18, double a = 0.45}) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: a),
        blurRadius: blur,
        spreadRadius: -2,
      ),
    ];
  }

  static ThemeData get dark {
    const ColorScheme scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Color(0xFF042430),
      secondary: secondary,
      onSecondary: Color(0xFF230A33),
      surface: surface,
      onSurface: textHi,
      outline: Color(0x24FFFFFF),
    );

    const TextTheme text = _textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textHi,
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(color: textMed, size: 22),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: outline),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: primary.withValues(alpha: 0.18),
        side: const BorderSide(color: outline),
        labelStyle: text.labelLarge,
        secondaryLabelStyle: text.labelLarge,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: primary,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        trackShape: const RoundedRectSliderTrackShape(),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF8B93A7)),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected)
                ? primary
                : Colors.white.withValues(alpha: 0.10)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
              s.contains(WidgetState.selected)
                  ? primary.withValues(alpha: 0.20)
                  : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? primary : textMed),
          side: WidgetStateProperty.all(const BorderSide(color: outline)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius))),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: text.labelLarge,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: outline),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius)),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: textMed,
        textColor: textHi,
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textMed),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: textHi),
    titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: textHi),
    titleMedium: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700, color: textHi),
    bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: textMed),
    bodySmall: TextStyle(fontSize: 12, height: 1.3, color: textLow),
    labelLarge: TextStyle(
        fontSize: 13.5, fontWeight: FontWeight.w600, color: textHi),
    labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: textLow),
  );
}
