import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/settings_provider.dart';

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_acrylic/flutter_acrylic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force native/FFI Dart plugins to register explicitly on non-web platforms.
  // This circumvents a bug in Flutter's Windows toolchain where FFI
  // method channels throw MissingPluginException
  if (!kIsWeb) {
    ui.DartPluginRegistrant.ensureInitialized();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await Window.initialize();
  }

  runApp(const ProviderScope(child: AntarcticomApp()));
}

class AntarcticomApp extends ConsumerStatefulWidget {
  const AntarcticomApp({super.key});

  @override
  ConsumerState<AntarcticomApp> createState() => _AntarcticomAppState();
}

class _AntarcticomAppState extends ConsumerState<AntarcticomApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyWindowEffect(ref.read(settingsProvider).uiTheme);
    });
  }

  void _applyWindowEffect(AppUiTheme themeVal) {
    if (kIsWeb || !Platform.isWindows) return;
    if (themeVal == AppUiTheme.liquidGlass) {
      Window.setEffect(
          effect: WindowEffect.transparent, color: Colors.transparent);
    } else {
      Window.setEffect(effect: WindowEffect.disabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.uiTheme), (previous, next) {
      if (previous != next) {
        _applyWindowEffect(next);
      }
    });

    final router = ref.watch(routerProvider);
    final theme = ref.watch(themeProvider); // Watch the theme provider
    final settings = ref.watch(
        settingsProvider); // Keep settings for accent color if needed elsewhere

    // Check for updates once when the app starts.
    // This is a common pattern for ConsumerWidget if you need to perform
    // an action once after the widget is built.
    // Ensure this is only called once, e.g., using a flag or a listener.
    // For simplicity, we'll assume it's okay to call it here,
    // but a ref.listen or a dedicated service might be more robust.
    // The original code had a delay, which is harder to replicate cleanly here
    // without a StatefulWidget. For now, removing the update check as per the
    // implied change in the instruction's snippet.
    // If update check is critical, it should be moved to a service or a
    // dedicated stateful widget higher up, or ref.listen.

    return MaterialApp.router(
      title: 'Antarcticom',
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme.copyWith(
        primaryColor: settings.accentColor,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: settings.accentColor,
          selectionColor: settings.accentColor.withValues(alpha: 0.4),
          selectionHandleColor: settings.accentColor,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: theme.materialTheme,
      themeMode: ThemeMode.dark,
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
