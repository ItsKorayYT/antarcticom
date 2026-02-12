import 'package:flutter/material.dart';

class RainbowBuilder extends StatefulWidget {
  final bool enabled;
  final Widget Function(BuildContext context, Color color) builder;
  final Widget? child;

  const RainbowBuilder({
    super.key,
    required this.enabled,
    required this.builder,
    this.child,
  });

  @override
  State<RainbowBuilder> createState() => _RainbowBuilderState();
}

class _RainbowBuilderState extends State<RainbowBuilder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Faster cycle for localized effect
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      // If disabled, pass a default (or null) color.
      // However, usually the parent keeps the static color.
      // We'll pass the *current theme* primary color just in case,
      // but usually the builder might ignore it if !enabled.
      // Let's pass the theme color.
      return widget.builder(context, Theme.of(context).primaryColor);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final hue = _controller.value * 360;
        final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
        return widget.builder(context, color);
      },
      child: widget.child,
    );
  }
}
