import 'package:flutter/material.dart';
import '../../core/settings_provider.dart';
import 'starfield_widget.dart';
import 'animated_themes.dart';
import 'liquid_glass_background.dart';

class BackgroundManager extends StatelessWidget {
  final AppBackgroundTheme theme;
  final double opacity;
  final double blobOpacity;
  final Color? customColor;

  const BackgroundManager({
    super.key,
    required this.theme,
    this.opacity = 0.5,
    this.blobOpacity = 0.7,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget background;
    switch (theme) {
      case AppBackgroundTheme.stars:
        background = StarfieldWidget(opacity: opacity);
        break;
      case AppBackgroundTheme.sun:
        background = const SunThemeWidget();
        break;
      case AppBackgroundTheme.moon:
        background = const MoonThemeWidget();
        break;
      case AppBackgroundTheme.field:
        background = const FieldThemeWidget();
        break;
      case AppBackgroundTheme.liquidDark:
        background = LiquidGlassBackgroundWidget(blobOpacity: blobOpacity);
        break;
      case AppBackgroundTheme.liquidCustom:
        background = LiquidGlassBackgroundWidget(
            customColor: customColor, blobOpacity: blobOpacity);
        break;
    }

    // Apply overlay for "brightness/opacity" control from settings
    if (opacity < 1.0) {
      return Stack(
        children: [
          Positioned.fill(child: background),
          Positioned.fill(
              child: Container(
                  color: Colors.black.withValues(alpha: 1.0 - opacity))),
        ],
      );
    }

    return background;
  }
}
