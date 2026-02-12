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
        indicatorColor: settings.accentColor,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: settings.accentColor,
          selectionColor: settings.accentColor.withOpacity(0.4),
          selectionHandleColor: settings.accentColor,
        ),
      ),
      routerConfig: router,
    );
  }
}
