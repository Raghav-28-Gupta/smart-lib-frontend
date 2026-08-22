import 'package:flutter/material.dart';

class SmartLibTokens extends ThemeExtension<SmartLibTokens> {
  const SmartLibTokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.divider,
    required this.neutral,
    required this.accent,
    required this.accent2,
    required this.spacing,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
  });

  final Color bg;
  final Color surface;
  final Color text;
  final Color divider;
  final Map<int, Color> neutral;
  final Map<int, Color> accent;
  final Map<int, Color> accent2;
  final Map<int, double> spacing;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  static SmartLibTokens standard() {
    Color ink(double opacity) => const Color(0xFF2e2b25).withValues(alpha: opacity);
    return SmartLibTokens(
      bg: const Color(0xFFf5ead8),
      surface: const Color(0xFFebddc5),
      text: const Color(0xFF201e1d),
      divider: const Color(0xFF201e1d).withValues(alpha: 0.16),
      neutral: const {
        100: Color(0xFFf9f4ed), 200: Color(0xFFeee7db), 300: Color(0xFFdcd3c4),
        400: Color(0xFFc0b6a5), 500: Color(0xFFa19786), 600: Color(0xFF82796a),
        700: Color(0xFF645c50), 800: Color(0xFF474238), 900: Color(0xFF2e2b25),
      },
      accent: const {
        100: Color(0xFFfff2eb), 200: Color(0xFFffe1d0), 300: Color(0xFFffc6a5),
        400: Color(0xFFf6a06b), 500: Color(0xFFd67f48), 600: Color(0xFFb2622d),
        700: Color(0xFF8c491a), 800: Color(0xFF643312), 900: Color(0xFF402310),
      },
      accent2: const {
        100: Color(0xFFf0fae1), 200: Color(0xFFe1eecc), 300: Color(0xFFccdbb2),
        400: Color(0xFFaebf92), 500: Color(0xFF8fa073), 600: Color(0xFF728157),
        700: Color(0xFF56633f), 800: Color(0xFF3d472b), 900: Color(0xFF272e1b),
      },
      spacing: const {1: 4.4, 2: 8.8, 3: 13.2, 4: 17.6, 6: 26.4, 8: 35.2},
      radiusSm: 8, radiusMd: 16, radiusLg: 28,
      shadowSm: [BoxShadow(color: ink(0.14), offset: const Offset(0, 1), blurRadius: 2)],
      shadowMd: [BoxShadow(color: ink(0.16), offset: const Offset(0, 3), blurRadius: 10)],
      shadowLg: [BoxShadow(color: ink(0.22), offset: const Offset(0, 12), blurRadius: 32)],
    );
  }

  @override
  SmartLibTokens copyWith() => this;

  @override
  SmartLibTokens lerp(ThemeExtension<SmartLibTokens>? other, double t) => this;
}
