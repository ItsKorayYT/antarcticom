import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings_provider.dart';

class ShootingStarWidget extends ConsumerStatefulWidget {
  const ShootingStarWidget({super.key});

  @override
  ConsumerState<ShootingStarWidget> createState() => _ShootingStarWidgetState();
}

class _ShootingStarWidgetState extends ConsumerState<ShootingStarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ActiveStar> _stars = [];
  final math.Random _rng = math.Random();
  DateTime _lastSpawnTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Infinite loop controller to drive the animation frames
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // Long duration, we just use value
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spawnStar(double freq) {
    // Determine spawn parameters
    // Spawn ONLY top or right edge
    double startX, startY;
    if (_rng.nextBool()) {
      // Top Edge
      startX = _rng.nextDouble();
      startY = -0.1;
    } else {
      // Right Edge
      startX = 1.1;
      startY = _rng.nextDouble() * 0.6;
    }

    // Randomized properties
    // Bigger size as requested: 3.0 to 7.0
    final size = 3.0 + _rng.nextDouble() * 4.0;
    // Speed factor: 0.5 to 1.5
    final speed = 0.5 + _rng.nextDouble() * 1.0;
    // Duration: 1.5s to 3.0s (inversely prop to speed)
    final durationMs = (1500 + _rng.nextInt(1500)) ~/ speed;
    final angle = (math.pi / 4) + (_rng.nextDouble() * 0.2 - 0.1);

    _stars.add(_ActiveStar(
      startX: startX,
      startY: startY,
      size: size,
      angle: angle,
      speed: speed,
      startTime: DateTime.now(),
      duration: Duration(milliseconds: durationMs),
    ));
    _lastSpawnTime = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final freq = settings.shootingStarFrequency; // 0.0 to 1.0

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final now = DateTime.now();

        // 1. Clean up dead stars
        _stars.removeWhere((star) {
          return now.difference(star.startTime) > star.duration;
        });

        // 2. Spawn new stars
        // Calculate interval based on frequency
        // Freq 1.0 -> 100ms interval (Meteor Shower!)
        // Freq 0.5 -> 2s interval
        // Freq 0.0 -> 15s interval
        int intervalMs;
        if (freq >= 0.9) {
          intervalMs = 100; // Very frequent
        } else if (freq >= 0.7) {
          intervalMs = 500;
        } else if (freq >= 0.4) {
          intervalMs = 2000;
        } else if (freq >= 0.1) {
          intervalMs = 5000;
        } else {
          intervalMs = 20000;
        }

        // Add some randomness to interval
        if (now.difference(_lastSpawnTime).inMilliseconds >
            intervalMs + _rng.nextInt(500)) {
          _spawnStar(freq);
        }

        return CustomPaint(
          painter: _MultiStarPainter(
            stars: _stars,
            now: now,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ActiveStar {
  final double startX;
  final double startY;
  final double size;
  final double angle;
  final double speed;
  final DateTime startTime;
  final Duration duration;

  _ActiveStar({
    required this.startX,
    required this.startY,
    required this.size,
    required this.angle,
    required this.speed,
    required this.startTime,
    required this.duration,
  });
}

class _MultiStarPainter extends CustomPainter {
  final List<_ActiveStar> stars;
  final DateTime now;

  _MultiStarPainter({required this.stars, required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final w = size.width;
    final h = size.height;

    for (var star in stars) {
      final elapsed = now.difference(star.startTime).inMilliseconds;
      final progress = elapsed / star.duration.inMilliseconds;

      if (progress < 0.0 || progress > 1.0) continue;

      // Calculate position
      final moveDistance = 0.5 * star.speed; // screen percentage
      final currentX =
          (star.startX - (progress * moveDistance * math.cos(star.angle))) * w;
      final currentY =
          (star.startY + (progress * moveDistance * math.sin(star.angle))) * h;

      // Opacity fade in last 20%
      final opacity = progress > 0.8 ? (1.0 - ((progress - 0.8) / 0.2)) : 1.0;

      if (opacity <= 0) continue;

      canvas.save();
      canvas.translate(currentX, currentY);

      // Tail
      // Length multiplier 250
      final tailLen = 250.0 * (1.0 - progress);
      final dx = math.cos(star.angle);
      final dy = math.sin(star.angle);

      final tailX = tailLen * dx;
      final tailY = -tailLen * dy;

      final Rect rect = Rect.fromPoints(Offset.zero, Offset(tailX, tailY));
      paint.shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: opacity),
          Colors.white.withValues(alpha: 0.0)
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);

      paint.strokeWidth = star.size;
      paint.strokeCap = StrokeCap.round;

      canvas.drawLine(Offset.zero, Offset(tailX, tailY), paint);

      // Head
      paint.shader = null;
      paint.color = Colors.white.withValues(alpha: opacity);

      // Core
      canvas.drawCircle(Offset.zero, star.size / 2, paint);

      // Glow
      paint.color = Colors.white.withValues(alpha: 0.3 * opacity);
      canvas.drawCircle(Offset.zero, star.size * 2, paint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MultiStarPainter old) => true;
}
