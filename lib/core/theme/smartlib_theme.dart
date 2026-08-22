import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'smartlib_tokens.dart';

enum CoverPalette { accent, accent2, neutral }

({Color bg, Color fg}) coverColors(CoverPalette p, SmartLibTokens t) {
  switch (p) {
    case CoverPalette.accent:
      return (bg: t.accent[200]!, fg: t.accent[800]!);
    case CoverPalette.accent2:
      return (bg: t.accent2[200]!, fg: t.accent2[800]!);
    case CoverPalette.neutral:
      return (bg: t.neutral[300]!, fg: t.neutral[800]!);
  }
}

ThemeData buildSmartLibTheme() {
  final tokens = SmartLibTokens.standard();
  final headingFont = GoogleFonts.caprasimoTextTheme();
  final bodyFont = GoogleFonts.figtreeTextTheme();
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: tokens.bg,
    colorScheme: ColorScheme.light(
      primary: tokens.accent[700]!,
      onPrimary: tokens.bg,
      secondary: tokens.accent2[700]!,
      surface: tokens.surface,
      onSurface: tokens.text,
    ),
    textTheme: bodyFont.copyWith(
      headlineLarge: headingFont.headlineLarge,
      headlineMedium: headingFont.headlineMedium,
      headlineSmall: headingFont.headlineSmall,
      titleLarge: headingFont.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent[700],
        foregroundColor: tokens.bg,
        shape: pill,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing[3]! * 1.2, vertical: tokens.spacing[2]!),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: pill, side: BorderSide(color: tokens.divider)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: tokens.divider)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusLg * 1.15)),
      elevation: 0,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide(color: tokens.divider)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: pill),
    ),
    extensions: [tokens],
  );
}
