import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/settings_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AntarcticomApp()));
}

class AntarcticomApp extends ConsumerWidget {
  const AntarcticomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'Antarcticom',
      debugShowCheckedModeBanner: false,
      theme: AntarcticomTheme.dark.copyWith(
        primaryColor: settings.accentColor,
        colorScheme: AntarcticomTheme.dark.colorScheme.copyWith(
          primary: settings.accentColor,
          secondary: settings.accentColor,
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: settings.accentColor,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: settings.accentColor,
          selectionColor: settings.accentColor.withValues(alpha: 0.4),
          selectionHandleColor: settings.accentColor,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.windows: FadePageTransitionsBuilder(),
          },
        ),
      ),
      routerConfig: router,
    );
  }
}

class RainbowWrapper extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const RainbowWrapper({super.key, required this.enabled, required this.child});

  static Color? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_RainbowInherited>()
        ?.color;
  }

  @override
  State<RainbowWrapper> createState() => _RainbowWrapperState();
}

class _RainbowWrapperState extends State<RainbowWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
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
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final hue = _controller.value * 360;
        final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
        return _RainbowInherited(color: color, child: widget.child);
      },
    );
  }
}

class _RainbowInherited extends InheritedWidget {
  final Color color;

  const _RainbowInherited({required this.color, required super.child});

  @override
  bool updateShouldNotify(_RainbowInherited oldWidget) {
    return color != oldWidget.color;
  }
}

class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}
