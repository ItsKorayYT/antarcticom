import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings_provider.dart';
import 'shooting_star_widget.dart';

// ─── Sun Theme ───────────────────────────────────────────────────────────────

class SunThemeWidget extends ConsumerStatefulWidget {
  const SunThemeWidget({super.key});

  @override
  ConsumerState<SunThemeWidget> createState() => _SunThemeWidgetState();
}

class _SunThemeWidgetState extends ConsumerState<SunThemeWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final sunLeft = MediaQuery.of(context).size.width * settings.sunX - 60;
    final sunTop = MediaQuery.of(context).size.height * settings.sunY - 60;

    return Stack(
      children: [
        // Beautiful Sky Gradient
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF2980B9), // Deep Blue
                    Color(0xFF6DD5FA), // Light Blue
                    Color(0xFFFFFFFF), // White/Haze
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.7, 1.0],
                ),
              ),
            );
          },
        ),
        // The Sun
        Positioned(
          top: sunTop,
          left: sunLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFFE082),
                      Color(0xFFFFCA28),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFCA28).withValues(alpha: 0.6),
                      blurRadius: 80,
                      spreadRadius: 20 + (_controller.value * 10),
                    ),
                    BoxShadow(
                      color: const Color(0xFFFFE082).withValues(alpha: 0.4),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Fluffy Clouds
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _BetterCloudPainter(offset: _controller.value),
              );
            },
          ),
        ),
        // Birds
        if (settings.showBirds)
          const Positioned.fill(child: _BirdAnimationWidget()),
      ],
    );
  }
}

class _BetterCloudPainter extends CustomPainter {
  final double offset;
  _BetterCloudPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    // Use a Path to combine shapes and avoid alpha overlap
    final path = Path();

    // Layer 1: Background clouds
    _addCloudToPath(
        path, size.width * 0.1 + (offset * 20), size.height * 0.15, 0.6);
    _addCloudToPath(
        path, size.width * 0.6 - (offset * 15), size.height * 0.1, 0.5);

    // Layer 2: Foreground clouds
    _addCloudToPath(
        path, size.width * 0.8 + (offset * 40), size.height * 0.25, 1.0);
    _addCloudToPath(
        path, size.width * 0.3 - (offset * 30), size.height * 0.3, 0.8);

    // Extra large bottom cloud
    _addCloudToPath(
        path, size.width * 0.5 + (offset * 10), size.height * 0.8, 2.0);

    canvas.drawPath(path, paint);
  }

  void _addCloudToPath(Path path, double cx, double cy, double scale) {
    final r = 30.0 * scale;
    path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    path.addOval(Rect.fromCircle(
        center: Offset(cx - r * 1.2, cy + r * 0.2), radius: r * 0.8));
    path.addOval(Rect.fromCircle(
        center: Offset(cx + r * 1.2, cy + r * 0.2), radius: r * 0.8));
    path.addOval(Rect.fromCircle(
        center: Offset(cx - r * 0.6, cy - r * 0.6), radius: r * 0.9));
    path.addOval(Rect.fromCircle(
        center: Offset(cx + r * 0.6, cy - r * 0.6), radius: r * 0.9));
  }

  @override
  bool shouldRepaint(_BetterCloudPainter oldDelegate) =>
      oldDelegate.offset != offset;
}

class _BirdAnimationWidget extends StatefulWidget {
  const _BirdAnimationWidget();
  @override
  State<_BirdAnimationWidget> createState() => _BirdAnimationWidgetState();
}

class _BirdAnimationWidgetState extends State<_BirdAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Bird> _birds = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat();

    // Spawn a flock
    for (int i = 0; i < 3; i++) {
      _birds.add(_Bird(
        yOffset: _rng.nextDouble() * 0.2 + (i * 0.05),
        speed: 0.8 + _rng.nextDouble() * 0.4,
        delay: i * 0.5,
        size: 10 + _rng.nextDouble() * 10,
      ));
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
        return Stack(
          children: _birds.map((bird) {
            // Calculate individual position
            double t = (_controller.value * bird.speed + bird.delay) % 1.0;

            // Linear movement right to left or left to right?
            // Let's go Left -> Right for sun theme usually.
            // Code had: final x = (_controller.value * 1.2) - 0.1;

            final x = (t * 1.4) - 0.2; // -0.2 to 1.2
            final y = bird.yOffset + math.sin(t * math.pi * 2) * 0.05;

            if (x < -0.2 || x > 1.2) return const SizedBox();

            return Positioned(
              left: MediaQuery.of(context).size.width * x,
              top: MediaQuery.of(context).size.height * y,
              child: CustomPaint(
                painter: _BirdPainter(
                  flightProgress: t * 20, // Flapping speed
                  color: Colors.black.withValues(alpha: 0.8),
                ),
                size: Size(bird.size * 1.5, bird.size * 0.75),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _Bird {
  final double yOffset;
  final double speed;
  final double delay;
  final double size;
  _Bird(
      {required this.yOffset,
      required this.speed,
      required this.delay,
      required this.size});
}

class _BirdPainter extends CustomPainter {
  final double flightProgress;
  final Color color;

  _BirdPainter({required this.flightProgress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Flapping wing calculation
    final wingY = math.sin(flightProgress) * h * 0.5;

    path.moveTo(0, h / 2 - wingY); // Left wing tip
    path.quadraticBezierTo(
        w * 0.25, h / 2, w * 0.5, h / 2 + h * 0.2); // Body center
    path.quadraticBezierTo(w * 0.75, h / 2, w, h / 2 - wingY); // Right wing tip

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BirdPainter old) => true;
}

// ─── Moon Theme ─────────────────────────────────────────────────────────────

class MoonThemeWidget extends ConsumerStatefulWidget {
  const MoonThemeWidget({super.key});

  @override
  ConsumerState<MoonThemeWidget> createState() => _MoonThemeWidgetState();
}

class _MoonThemeWidgetState extends ConsumerState<MoonThemeWidget> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // Calculate position based on relative coordinates
    final moonLeft = MediaQuery.of(context).size.width * settings.moonX -
        40; // Center offset
    final moonTop = MediaQuery.of(context).size.height * settings.moonY - 40;
    return Stack(
      children: [
        // Night Gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        // Simple Twinkling Stars (lighter version of Starfield)
        const Positioned.fill(child: _SimpleTwinklingStars()),

        // Shooting Stars (re-used for night)
        if (settings.showShootingStars) const ShootingStarWidget(),

        // The Moon
        Positioned(
          top: moonTop,
          left: moonLeft,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF6F1D5), // Moon color
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF6F1D5).withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
        ),

        // Owl/Crow
        if (settings.showOwls)
          const Positioned.fill(child: _OwlAnimationWidget()),
      ],
    );
  }
}

class _SimpleTwinklingStars extends StatefulWidget {
  const _SimpleTwinklingStars();
  @override
  State<_SimpleTwinklingStars> createState() => _SimpleTwinklingStarsState();
}

class _SimpleTwinklingStarsState extends State<_SimpleTwinklingStars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_StarData> _stars = [];
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat();

    // Generate static star positions
    for (int i = 0; i < 50; i++) {
      _stars.add(_StarData(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: _rng.nextDouble() * 2 + 1,
        phase: _rng.nextDouble() * 2 * math.pi,
      ));
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
          painter: _TwinklePainter(_stars, _controller.value),
        );
      },
    );
  }
}

class _StarData {
  final double x, y, size, phase;
  _StarData(
      {required this.x,
      required this.y,
      required this.size,
      required this.phase});
}

class _TwinklePainter extends CustomPainter {
  final List<_StarData> stars;
  final double progress;

  _TwinklePainter(this.stars, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    for (var star in stars) {
      // Twinkle effect: sin wave based on time + random phase
      final opacity =
          (math.sin(progress * 2 * math.pi + star.phase) + 1) / 2 * 0.7 + 0.3;
      paint.color = Colors.white.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TwinklePainter old) => true;
}

class _OwlAnimationWidget extends StatefulWidget {
  const _OwlAnimationWidget();
  @override
  State<_OwlAnimationWidget> createState() => _OwlAnimationWidgetState();
}

class _OwlAnimationWidgetState extends State<_OwlAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isVisible = false;
  double _randomY = 0.2;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 15));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isVisible = false);
        _scheduleOwl();
      }
    });

    // Start with a delay
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleOwl());
  }

  void _scheduleOwl() {
    if (!mounted) return;
    final rng = math.Random();
    // Owl appears more frequently: 5-20 seconds delay
    final delay = rng.nextInt(15) + 5;

    Future.delayed(Duration(seconds: delay), () {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
        _randomY =
            0.1 + rng.nextDouble() * 0.4; // Random Y position (10% to 50%)
      });
      _controller.forward(from: 0.0);
    });
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
          if (!_isVisible) return const SizedBox();

          // Fly from right to left (linear)
          final x = 1.2 - (_controller.value * 1.4);

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: MediaQuery.of(context).size.width * x,
                // Use randomized Y
                top: MediaQuery.of(context).size.height * _randomY +
                    math.sin(_controller.value * 10) * 10,
                child: Transform.scale(
                  scaleX: -1, // Face left
                  child: CustomPaint(
                    painter: _BirdPainter(
                      flightProgress: _controller.value * 20,
                      // Owl is Grey (Night Bird)
                      color: Colors.grey.withValues(alpha: 0.9),
                    ),
                    size: const Size(60, 40), // Larger than normal birds
                  ),
                ),
              ),
            ],
          );
        });
  }
}

// ─── Field Theme ────────────────────────────────────────────────────────────

class FieldThemeWidget extends StatefulWidget {
  const FieldThemeWidget({super.key});

  @override
  State<FieldThemeWidget> createState() => _FieldThemeWidgetState();
}

class _FieldThemeWidgetState extends State<FieldThemeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Sunny/Blue Sky
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF2980B9),
                Color(0xFF6DD5FA),
                Color(0xFFFFFFFF),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.7, 1.0],
            ),
          ),
        ),
        // Grass Layer
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 200,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _GrassPainter(sway: _controller.value),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GrassPainter extends CustomPainter {
  final double sway;
  _GrassPainter({required this.sway});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw multiple layers of grass
    final rng = math.Random(12345); // Fixed seed for consistent placement

    for (int layer = 0; layer < 3; layer++) {
      // Darker in back, lighter in front
      paint.color = Color.lerp(
              const Color(0xFF134E5E), const Color(0xFF71B280), layer / 2.0)!
          .withValues(alpha: 0.8);

      final layerOffset = layer * 40.0;
      const bladeCount = 100;
      final widthPerBlade = size.width / bladeCount;

      final path = Path();
      path.moveTo(0, size.height);

      for (int i = 0; i <= bladeCount; i++) {
        final x = i * widthPerBlade;
        final h = 50.0 + rng.nextDouble() * 100.0 + (layer * 20);
        // Sway logic: front layers sway more
        final s = (math.sin(sway * math.pi + i) * 10) * (layer + 1) * 0.5;

        // Add parallax/offset based on layer
        final xPos = x + layerOffset + s;

        path.lineTo(xPos, size.height - h);
        path.lineTo(xPos + widthPerBlade, size.height);
      }
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GrassPainter old) => old.sway != sway;
}
