import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiquidGlassBackgroundWidget extends StatefulWidget {
  final bool isLightMode;
  final Color? customColor;

  const LiquidGlassBackgroundWidget(
      {super.key, this.isLightMode = false, this.customColor});

  @override
  State<LiquidGlassBackgroundWidget> createState() =>
      _LiquidGlassBackgroundWidgetState();
}

class _LiquidGlassBackgroundWidgetState
    extends State<LiquidGlassBackgroundWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 25))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LiquidPainter(
              _controller.value, widget.isLightMode, widget.customColor),
          size: Size.infinite,
        );
      },
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double progress;
  final bool isLightMode;
  final Color? customColor;

  _LiquidPainter(this.progress, this.isLightMode, this.customColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (customColor == null) {
      // User requested pure transparency for BOTH Light and Dark liquid - no blobs, no base tint.
      // The AppThemeData.glassTheme overlays will provide the frosted glass effect natively.
      return;
    }

    // Base background
    Color baseBg;
    if (customColor != null) {
      final hsl = HSLColor.fromColor(customColor!);
      baseBg = hsl
          .withLightness((hsl.lightness * 0.2).clamp(0.0, 1.0))
          .toColor()
          .withValues(alpha: 0.15);
    } else {
      baseBg = isLightMode
          ? const Color(0xFFE5E7EB).withValues(alpha: 0.15)
          : const Color(0xFF0F0F1A).withValues(alpha: 0.15);
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = baseBg,
    );

    // Orbit parameters
    final t = progress * 2 * math.pi;

    void drawBlob(
      Color darkColor,
      Color lightColor,
      double centerX,
      double centerY,
      double radius,
      double phaseX,
      double phaseY,
      double ampX,
      double ampY,
    ) {
      final x = centerX + math.sin(t + phaseX) * ampX;
      final y = centerY + math.cos(t + phaseY) * ampY;

      final color = isLightMode ? lightColor : darkColor;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.5),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));

      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    Color color1Dark, color1Light;
    Color color2Dark, color2Light;
    Color color3Dark, color3Light;
    Color color4Dark, color4Light;

    if (customColor != null) {
      final hsl = HSLColor.fromColor(customColor!);

      // Generate 4 dynamic analog/monochromatic colors based on custom tint
      final c1 = hsl.toColor();
      final c2 = hsl
          .withHue((hsl.hue + 20) % 360)
          .withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0))
          .toColor();
      final c3 = hsl
          .withHue((hsl.hue - 20) % 360)
          .withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0))
          .toColor();
      final c4 = hsl.withHue((hsl.hue + 45) % 360).toColor();

      // For custom tint, we just use the generated colors directly regardless of "light/dark" mode
      color1Dark = c1;
      color1Light = c1;
      color2Dark = c2;
      color2Light = c2;
      color3Dark = c3;
      color3Light = c3;
      color4Dark = c4;
      color4Light = c4;
    } else {
      color1Dark = const Color(0xFF6C5CE7);
      color1Light = const Color(0xFF9D8DF1);
      color2Dark = const Color(0xFF00D2FF);
      color2Light = const Color(0xFF4ACEEB);
      color3Dark = const Color(0xFFFF1744);
      color3Light = const Color(0xFFFF708D);
      color4Dark = const Color(0xFF3F51B5);
      color4Light = const Color(0xFFEAB8CD);
    }

    // Blob 1
    drawBlob(color1Dark, color1Light, size.width * 0.3, size.height * 0.4,
        size.width * 0.6, 0.0, 1.0, size.width * 0.2, size.height * 0.2);

    // Blob 2
    drawBlob(color2Dark, color2Light, size.width * 0.7, size.height * 0.6,
        size.width * 0.5, 2.0, 0.5, size.width * 0.15, size.height * 0.25);

    // Blob 3
    drawBlob(color3Dark, color3Light, size.width * 0.5, size.height * 0.2,
        size.width * 0.4, 4.0, 3.0, size.width * 0.25, size.height * 0.15);

    // Blob 4
    drawBlob(color4Dark, color4Light, size.width * 0.8, size.height * 0.8,
        size.width * 0.45, 1.5, 4.5, size.width * 0.2, size.height * 0.2);
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
