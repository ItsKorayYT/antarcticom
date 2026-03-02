import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings_provider.dart';
import 'home/background_manager.dart';

/// Wraps a child widget with the user's selected background theme.
/// Reads settings via Riverpod and renders [BackgroundManager] behind [child].
class BackgroundWrapper extends ConsumerWidget {
  final Widget child;

  const BackgroundWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: BackgroundManager(
            theme: settings.backgroundTheme,
            opacity: settings.backgroundOpacity,
            blobOpacity: settings.blobOpacity,
            customColor:
                settings.backgroundTheme == AppBackgroundTheme.liquidCustom
                    ? settings.liquidCustomColor
                    : null,
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
