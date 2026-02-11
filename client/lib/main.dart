import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AntarcticomApp()));
}

class AntarcticomApp extends ConsumerWidget {
  const AntarcticomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Antarcticom',
      debugShowCheckedModeBanner: false,
      theme: AntarcticomTheme.dark,
      routerConfig: router,
    );
  }
}
