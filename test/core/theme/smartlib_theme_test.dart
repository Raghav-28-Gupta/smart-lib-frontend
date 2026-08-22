import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/core/theme/smartlib_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Tests run offline — without this, GoogleFonts tries to fetch over HTTP
  // on every call and prints a non-fatal but noisy error per font.
  GoogleFonts.config.allowRuntimeFetching = false;

  test('token ramps expose the design system\'s exact hex values', () {
    final tokens = SmartLibTokens.standard();
    expect(tokens.bg, const Color(0xFFf5ead8));
    expect(tokens.text, const Color(0xFF201e1d));
    expect(tokens.accent[700], const Color(0xFF8c491a));
    expect(tokens.accent2[800], const Color(0xFF3d472b));
    expect(tokens.neutral[500], const Color(0xFFa19786));
    expect(tokens.radiusMd, 16.0);
  });

  test('buttons render fully pill-shaped per the design override', () {
    final theme = buildSmartLibTheme();
    final shape = theme.filledButtonTheme.style?.shape?.resolve({}) as RoundedRectangleBorder?;
    expect(shape?.borderRadius, const BorderRadius.all(Radius.circular(999)));
  });

  test('chips and segmented buttons render fully pill-shaped per the design override', () {
    final theme = buildSmartLibTheme();
    final chipShape = theme.chipTheme.shape as RoundedRectangleBorder?;
    expect(chipShape?.borderRadius, const BorderRadius.all(Radius.circular(999)));
    final segShape = theme.segmentedButtonTheme.style?.shape?.resolve({}) as RoundedRectangleBorder?;
    expect(segShape?.borderRadius, const BorderRadius.all(Radius.circular(999)));
  });

  test('coverColors resolves each palette to its bg/fg token pair', () {
    final tokens = SmartLibTokens.standard();
    final accent = coverColors(CoverPalette.accent, tokens);
    expect(accent.bg, tokens.accent[200]);
    expect(accent.fg, tokens.accent[800]);
    final neutral = coverColors(CoverPalette.neutral, tokens);
    expect(neutral.bg, tokens.neutral[300]);
    expect(neutral.fg, tokens.neutral[800]);
  });
}
