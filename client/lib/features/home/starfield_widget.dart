import 'dart:math';
import 'package:flutter/material.dart';

class StarfieldWidget extends StatefulWidget {
  final double density;

  const StarfieldWidget({super.key, this.density = 0.5});

  @override
  State<StarfieldWidget> createState() => _StarfieldWidgetState();
}

class _StarfieldWidgetState extends State<StarfieldWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _stars = List.generate((200 * widget.density).toInt(), (index) {
      return _Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 2 + 0.5,
        opacity: _random.nextDouble(),
        speed: _random.nextDouble() * 0.05 + 0.01,
      );
    });
  }

  @override
  void didUpdateWidget(StarfieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.density != oldWidget.density) {
      setState(() {
        _stars = List.generate((200 * widget.density).toInt(), (index) {
          return _Star(
            x: _random.nextDouble(),
            y: _random.nextDouble(),
            size: _random.nextDouble() * 2 + 0.5,
            opacity: _random.nextDouble(),
            speed: _random.nextDouble() * 0.05 + 0.01,
          );
        });
      });
    }
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
          painter: _StarPainter(_stars, _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Star {
  double x;
  double y;
  final double size;
  final double opacity;
  final double speed;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
  });
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final double animationValue;

  _StarPainter(this.stars, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var star in stars) {
      // Move stars slowly upwards
      double y = (star.y - animationValue * star.speed) % 1.0;
      if (y < 0) y += 1.0;

      paint.color = Colors.white.withOpacity(star.opacity * 0.8);
      canvas.drawCircle(
        Offset(star.x * size.width, y * size.height),
        star.size,
        paint,
      );
    }

    // Draw a subtle gradient overlay to simulate depth/nebula
    final gradientPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.bottomRight,
        radius: 1.5,
        colors: [
          const Color(0xFF1A1A2E).withOpacity(0.0),
          const Color(0xFF0F0F1A).withOpacity(0.5),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), gradientPaint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}
