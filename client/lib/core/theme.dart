import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Antarcticom Design System — Dark-first, premium, futuristic.
class AntarcticomTheme {
  AntarcticomTheme._();

  // ─── Color Palette ──────────────────────────────────────────────────────

  /// Background colors (layered depth)
  static const Color bgDeepest = Color(0xFF0A0A0F); // Deepest background
  static const Color bgPrimary = Color(0xFF0F1117); // Main background
  static const Color bgSecondary = Color(0xFF151822); // Sidebar / panels
  static const Color bgTertiary =
      Color(0xFF1B1F2E); // Cards / elevated surfaces
  static const Color bgHover = Color(0xFF222738); // Hover state

  /// Accent colors
  static const Color accentPrimary = Color(0xFF6C5CE7); // Primary violet
  static const Color accentSecondary = Color(0xFF00D2FF); // Cyan highlight
  static const Color accentGradientStart = Color(0xFF6C5CE7);
  static const Color accentGradientEnd = Color(0xFF00D2FF);

  /// Status colors
  static const Color online = Color(0xFF00E676);
  static const Color idle = Color(0xFFFFAB00);
  static const Color dnd = Color(0xFFFF1744);
  static const Color offline = Color(0xFF546E7A);

  /// Text colors
  static const Color textPrimary = Color(0xFFEEEFF2);
  static const Color textSecondary = Color(0xFF8B8FA3);
  static const Color textMuted = Color(0xFF5A5E73);

  /// Voice indicator colors
  static const Color voiceSpeaking = Color(0xFF00E676);
  static const Color voiceRing = Color(0xFF6C5CE7);

  /// Danger / destructive
  static const Color danger = Color(0xFFFF1744);

  // ─── Gradients ──────────────────────────────────────────────────────────

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentGradientStart, accentGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient subtleGradient = LinearGradient(
    colors: [Color(0xFF1B1F2E), Color(0xFF151822)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

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

  // ─── ThemeData ──────────────────────────────────────────────────────────

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgPrimary,
        canvasColor: bgSecondary,
        cardColor: bgTertiary,

        // Color scheme
        colorScheme: const ColorScheme.dark(
          primary: accentPrimary,
          secondary: accentSecondary,
          surface: bgSecondary,
          error: danger,
          onPrimary: textPrimary,
          onSecondary: textPrimary,
          onSurface: textPrimary,
          onError: textPrimary,
        ),

        // Typography
        textTheme: GoogleFonts.interTextTheme(
          TextTheme(
            // Headlines
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
            headlineMedium: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: -0.3,
            ),
            headlineSmall: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),

            // Body
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
            bodyMedium: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: textSecondary,
              height: 1.5,
            ),
            bodySmall: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: textMuted,
            ),

            // Labels (buttons, chips)
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
            labelMedium: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ),

        // Input decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgDeepest,
          hintStyle: const TextStyle(color: textMuted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: spacingMd,
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

        // Elevated button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentPrimary,
            foregroundColor: textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: spacingLg,
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

        // Icon theme
        iconTheme: const IconThemeData(
          color: textSecondary,
          size: 20,
        ),

        // Scrollbar
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(textMuted.withValues(alpha: 0.3)),
          radius: const Radius.circular(radiusFull),
          thickness: WidgetStateProperty.all(4),
        ),

        // Tooltip
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: bgTertiary,
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(
            color: textPrimary,
            fontSize: 12,
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1E2235),
          thickness: 1,
          space: 0,
        ),
      );
}

/// Voice speaking indicator gradient animation mixin.
/// Apply this to widgets that show voice activity.
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
