import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings_provider.dart';

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
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFFE082),
                      const Color(0xFFFFCA28),
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Use a list of birds with diff speeds later? For now just one flock or single bird.

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 15))
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
        // Linear movement across screen
        final x = (_controller.value * 1.2) - 0.1; // -0.1 to 1.1
        final y = 0.2 + math.sin(_controller.value * math.pi * 2) * 0.05;

        // Don't render if off screen significantly
        if (x < -0.1 || x > 1.1) return const SizedBox();

        return Positioned(
          left: MediaQuery.of(context).size.width * x,
          top: MediaQuery.of(context).size.height * y,
          child: const Icon(Icons.flight, color: Colors.black12, size: 24),
        );
      },
    );
  }
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
        if (settings.showShootingStars)
          const Positioned.fill(child: _ShootingStarWidget()),

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

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
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
          // Fly from right to left
          final x = 1.2 - (_controller.value * 1.4);
          if (x < -0.2 || x > 1.2) return const SizedBox();

          return Positioned(
            left: MediaQuery.of(context).size.width * x,
            top: MediaQuery.of(context).size.height * 0.15 +
                math.sin(_controller.value * 10) * 20,
            child: Opacity(
                opacity: 0.6,
                child: Icon(Icons.flutter_dash, color: Colors.black, size: 32)),
          );
        });
  }
}

class _ShootingStarWidget extends StatefulWidget {
  const _ShootingStarWidget();
  @override
  State<_ShootingStarWidget> createState() => _ShootingStarWidgetState();
}

class _ShootingStarWidgetState extends State<_ShootingStarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  // Initialize off-screen to prevent flash
  double _startX = -1.0;
  double _startY = -1.0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _scheduleNextStar();
  }

  void _scheduleNextStar() {
    if (!mounted) return;
    final delay = math.Random().nextInt(10) + 5; // 5-15 seconds delay
    Future.delayed(Duration(seconds: delay), () {
      if (!mounted) return;
      // Set position just before starting animation
      setState(() {
        _startX = math.Random().nextDouble();
        _startY = math.Random().nextDouble() * 0.5;
      });
      _controller.forward(from: 0).then((_) => _scheduleNextStar());
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
          // Double check to ensure we don't render if off-screen or not animating
          if (_controller.value == 0 || _controller.value == 1 || _startX < 0)
            return const SizedBox();

          final progress = _controller.value;
          // Move casually down-left
          final currentX = _startX - (progress * 0.3);
          final currentY = _startY + (progress * 0.3);

          return Positioned(
            left: MediaQuery.of(context).size.width * currentX,
            top: MediaQuery.of(context).size.height * currentY,
            child: Opacity(
              opacity: 1.0 - progress, // Fade out
              child: Container(
                width: 100 * (1.0 - progress),
                height: 2,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.white, Colors.transparent]),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.white, blurRadius: 4, spreadRadius: 1)
                    ]),
                transform: Matrix4.rotationZ(0.785), // 45 degrees
              ),
            ),
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
      final bladeCount = 100;
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
