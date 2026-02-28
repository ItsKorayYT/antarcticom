import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'settings_provider.dart';

enum AppUiTheme { defaultDark, liquidGlass }

class AppThemeData {
  final Color bgDeepest;
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color bgHover;

  final Color accentPrimary;
  final Color accentSecondary;
  final Color accentGradientStart;
  final Color accentGradientEnd;

  final Color online;
  final Color idle;
  final Color dnd;
  final Color offline;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color voiceSpeaking;
  final Color voiceRing;

  final Color danger;
  final Color dividerColor;

  final LinearGradient accentGradient;
  final LinearGradient subtleGradient;

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;

  final ThemeData materialTheme;

  const AppThemeData({
    required this.bgDeepest,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.bgHover,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.accentGradientStart,
    required this.accentGradientEnd,
    required this.online,
    required this.idle,
    required this.dnd,
    required this.offline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.voiceSpeaking,
    required this.voiceRing,
    required this.danger,
    required this.dividerColor,
    required this.accentGradient,
    required this.subtleGradient,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.materialTheme,
  });

  static AppThemeData get defaultTheme {
    return _buildTheme(
      bgDeepest: const Color(0xFF0A0A0F),
      bgPrimary: const Color(0xFF0F1117),
      bgSecondary: const Color(0xFF151822),
      bgTertiary: const Color(0xFF1B1F2E),
      bgHover: const Color(0xFF222738),
      dividerColor: const Color(0xFF1E2235),
      radiusSm: 6.0,
      radiusMd: 8.0,
      radiusLg: 12.0,
      radiusXl: 16.0,
    );
  }

  static AppThemeData getGlassTheme({bool isLight = false}) {
    return _buildTheme(
      bgDeepest: isLight ? const Color(0x11000000) : const Color(0x660A0A0F),
      bgPrimary: isLight ? const Color(0x77FFFFFF) : const Color(0x770F1117),
      bgSecondary: isLight ? const Color(0x55FFFFFF) : const Color(0x44151822),
      bgTertiary: isLight ? const Color(0x66FFFFFF) : const Color(0x551B1F2E),
      bgHover: isLight ? const Color(0x22000000) : const Color(0x66222738),
      dividerColor: isLight ? const Color(0x1A000000) : const Color(0x33FFFFFF),
      textPrimary: isLight ? const Color(0xFF111111) : const Color(0xFFEEEFF2),
      textSecondary:
          isLight ? const Color(0xFF444444) : const Color(0xFF8B8FA3),
      textMuted: isLight ? const Color(0xFF777777) : const Color(0xFF5A5E73),
      radiusSm: 12.0,
      radiusMd: 24.0,
      radiusLg: 32.0,
      radiusXl: 48.0,
    );
  }

  static AppThemeData _buildTheme({
    required Color bgDeepest,
    required Color bgPrimary,
    required Color bgSecondary,
    required Color bgTertiary,
    required Color bgHover,
    required Color dividerColor,
    Color textPrimary = const Color(0xFFEEEFF2),
    Color textSecondary = const Color(0xFF8B8FA3),
    Color textMuted = const Color(0xFF5A5E73),
    required double radiusSm,
    required double radiusMd,
    required double radiusLg,
    required double radiusXl,
  }) {
    const accentPrimary = Color(0xFF6C5CE7);
    const accentSecondary = Color(0xFF00D2FF);
    const danger = Color(0xFFFF1744);

    return AppThemeData(
      bgDeepest: bgDeepest,
      bgPrimary: bgPrimary,
      bgSecondary: bgSecondary,
      bgTertiary: bgTertiary,
      bgHover: bgHover,
      accentPrimary: accentPrimary,
      accentSecondary: accentSecondary,
      accentGradientStart: accentPrimary,
      accentGradientEnd: accentSecondary,
      online: const Color(0xFF00E676),
      idle: const Color(0xFFFFAB00),
      dnd: danger,
      offline: const Color(0xFF546E7A),
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      voiceSpeaking: const Color(0xFF00E676),
      voiceRing: accentPrimary,
      danger: danger,
      dividerColor: dividerColor,
      radiusSm: radiusSm,
      radiusMd: radiusMd,
      radiusLg: radiusLg,
      radiusXl: radiusXl,
      accentGradient: const LinearGradient(
        colors: [accentPrimary, accentSecondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      subtleGradient: LinearGradient(
        colors: [bgTertiary, bgSecondary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      materialTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgPrimary,
        canvasColor: bgSecondary,
        cardColor: bgTertiary,
        colorScheme: ColorScheme.dark(
          primary: accentPrimary,
          secondary: accentSecondary,
          surface: bgSecondary,
          error: danger,
          onPrimary: textPrimary,
          onSecondary: textPrimary,
          onSurface: textPrimary,
          onError: textPrimary,
        ),
        textTheme: GoogleFonts.interTextTheme(
          TextTheme(
            headlineLarge: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            headlineMedium: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: -0.3,
            ),
            headlineSmall: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: textPrimary,
              height: 1.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: textSecondary,
              height: 1.5,
            ),
            bodySmall: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: textMuted,
            ),
            labelLarge: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: 0.2,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            labelMedium: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgDeepest,
          hintStyle: TextStyle(color: textMuted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AntarcticomTheme.spacingMd,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: accentPrimary, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentPrimary,
            foregroundColor: textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: AntarcticomTheme.spacingLg,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        iconTheme: IconThemeData(
          color: textSecondary,
          size: 20,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(textMuted.withValues(alpha: 0.3)),
          radius: const Radius.circular(AntarcticomTheme.radiusFull),
          thickness: WidgetStateProperty.all(4),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: bgTertiary,
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: TextStyle(
            color: textPrimary,
            fontSize: 12,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: dividerColor,
          thickness: 1,
          space: 0,
        ),
      ),
    );
  }
}

final themeProvider = Provider<AppThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  if (settings.uiTheme == AppUiTheme.liquidGlass) {
    bool isLightBg = settings.backgroundTheme == AppBackgroundTheme.liquidLight;
    return AppThemeData.getGlassTheme(isLight: isLightBg);
  }
  return AppThemeData.defaultTheme;
});

class AntarcticomTheme {
  AntarcticomTheme._();

  // ─── Border Radius ─────────────────────────────────────────────────────
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  // ─── Spacing ────────────────────────────────────────────────────────────
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // ─── Animations ─────────────────────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 120);
  static const Duration animNormal = Duration(milliseconds: 200);
  static const Duration animSlow = Duration(milliseconds: 350);
  static const Curve animCurve = Curves.easeOutCubic;
}

class VoiceIndicatorColors {
  static const List<Color> speakingGradient = [
    Color(0xFF00E676),
    Color(0xFF00C853),
    Color(0xFF69F0AE),
  ];

  static const List<Color> idleGradient = [
    Color(0xFF37474F),
    Color(0xFF455A64),
  ];
}
