import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings_provider.dart';
import 'shooting_star_widget.dart';

class StarfieldWidget extends ConsumerStatefulWidget {
  final double density;
  final double opacity;

  const StarfieldWidget({
    super.key,
    this.density = 0.5,
    this.opacity = 1.0,
  });

  @override
  ConsumerState<StarfieldWidget> createState() => _StarfieldWidgetState();
}

class _StarfieldWidgetState extends ConsumerState<StarfieldWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<_Star> _stars;
  final Random _random = Random();
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    _initStars();

    _ticker = createTicker((Duration elapsed) {
      final double currentTime = elapsed.inMilliseconds / 1000.0;
      final double dt = _lastTime == 0 ? 0 : currentTime - _lastTime;
      _lastTime = currentTime;

      _updateStars(dt);
    });

    _ticker.start();
  }

  void _initStars() {
    _stars = List.generate((200 * widget.density).toInt(), (index) {
      return _Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 2 + 0.5,
        baseOpacity: _random.nextDouble(),
        speed: _random.nextDouble() * 0.05 + 0.02,
      );
    });
  }

  void _updateStars(double dt) {
    if (!mounted) return;
    setState(() {
      for (var star in _stars) {
        // Move upwards
        star.y -= star.speed * dt;
        if (star.y < 0) {
          star.y += 1.0;
          star.x =
              _random.nextDouble(); // Randomize x on reset to avoid patterns
        }
      }
    });
  }

  @override
  void didUpdateWidget(StarfieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.density != oldWidget.density) {
      _initStars();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _StarPainter(_stars, widget.opacity),
          size: Size.infinite,
        ),
        if (settings.showShootingStars) const ShootingStarWidget(),
      ],
    );
  }
}

class _Star {
  double x;
  double y;
  final double size;
  final double baseOpacity;
  final double speed;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.baseOpacity,
    required this.speed,
  });
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final double globalOpacity;

  _StarPainter(this.stars, this.globalOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var star in stars) {
      // Scale opacity by global setting
      final opacity = (star.baseOpacity * 0.8 * globalOpacity).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size,
        paint,
      );
    }

    final gradientPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.bottomRight,
        radius: 1.5,
        colors: [
          const Color(0xFF1A1A2E).withValues(alpha: 0.0),
          const Color(0xFF0F0F1A).withValues(alpha: 0.5 * globalOpacity),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), gradientPaint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => true;
}
