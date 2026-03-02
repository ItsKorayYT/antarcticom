import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiquidGlassBackgroundWidget extends StatefulWidget {
  final Color? customColor;
  final double blobOpacity;

  const LiquidGlassBackgroundWidget({
    super.key,
    this.customColor,
    this.blobOpacity = 0.7,
  });

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
            _controller.value,
            widget.customColor,
            widget.blobOpacity,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double progress;
  final Color? customColor;
  final double blobOpacity;

  _LiquidPainter(this.progress, this.customColor, this.blobOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    // Pure transparency for Dark Liquid — No custom color = no blobs, no base tint.
    if (customColor == null) {
      return;
    }

    if (blobOpacity <= 0.01) {
      return;
    }

    // Base background for Custom Tint
    final hsl = HSLColor.fromColor(customColor!);
    final baseBg = hsl
        .withLightness((hsl.lightness * 0.2).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: 0.15 * blobOpacity);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = baseBg,
    );

    // Orbit parameters based on synced time
    final now = DateTime.now().millisecondsSinceEpoch;
    final syncedProgress = (now % 25000) / 25000.0;
    final t = syncedProgress * 2 * math.pi;

    void drawBlob(
      Color color,
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

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: blobOpacity),
            color.withValues(alpha: 0.5 * blobOpacity),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius));

      canvas.drawCircle(Offset(x, y), radius, paint);
    }

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

    // Blob 1
    drawBlob(c1, size.width * 0.3, size.height * 0.4, size.width * 0.6, 0.0,
        1.0, size.width * 0.2, size.height * 0.2);

    // Blob 2
    drawBlob(c2, size.width * 0.7, size.height * 0.6, size.width * 0.5, 2.0,
        0.5, size.width * 0.15, size.height * 0.25);

    // Blob 3
    drawBlob(c3, size.width * 0.5, size.height * 0.2, size.width * 0.4, 4.0,
        3.0, size.width * 0.25, size.height * 0.15);

    // Blob 4
    drawBlob(c4, size.width * 0.8, size.height * 0.8, size.width * 0.45, 1.5,
        4.5, size.width * 0.2, size.height * 0.2);
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.blobOpacity != blobOpacity ||
        oldDelegate.customColor != customColor;
  }
}
