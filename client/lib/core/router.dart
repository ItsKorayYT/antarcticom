import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/home/home_screen.dart';

/// App router provider — manages all navigation.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      // ─── Auth Routes ────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // ─── Main App Shell ─────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/channels/:serverId/:channelId',
            name: 'channel',
            builder: (context, state) {
              final serverId = state.pathParameters['serverId']!;
              final channelId = state.pathParameters['channelId']!;
              return ChannelPlaceholder(
                serverId: serverId,
                channelId: channelId,
              );
            },
          ),
          GoRoute(
            path: '/friends',
            name: 'friends',
            builder: (context, state) =>
                const Center(child: Text('Friends — Coming soon')),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) =>
                const Center(child: Text('Settings — Coming soon')),
          ),
        ],
      ),
    ],
  );
});

/// Placeholder widget for channel view (will be replaced by full implementation).
class ChannelPlaceholder extends StatelessWidget {
  final String serverId;
  final String channelId;

  const ChannelPlaceholder({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Channel: $channelId\nServer: $serverId',
        textAlign: TextAlign.center,
      ),
    );
  }
}
