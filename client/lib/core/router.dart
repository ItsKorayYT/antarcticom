import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/home/home_screen.dart';
import '../features/chat/channel_screen.dart';
import 'auth_provider.dart';

/// App router provider — manages all navigation with auth-based redirects.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuth = auth.isAuthenticated;
      final isLoading = auth.isLoading;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      // Still loading session — don't redirect
      if (isLoading) return null;

      // Not authenticated and not on auth page → go to login
      if (!isAuth && !isAuthRoute) return '/login';

      // Authenticated but on auth page → go to home
      if (isAuth && isAuthRoute) return '/channels/@me';

      return null;
    },
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
            path: '/channels/@me',
            name: 'home',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Center(
                child: Text(
                  'Welcome to Antarcticom!\nCreate or select a server to get started.',
                  style: TextStyle(fontSize: 16, color: Color(0xFF8E9297)),
                  textAlign: TextAlign.center,
                ),
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/channels/:serverId/:channelId',
            name: 'channel',
            pageBuilder: (context, state) {
              final serverId = state.pathParameters['serverId']!;
              final channelId = state.pathParameters['channelId']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: ChannelScreen(
                  serverId: serverId,
                  channelId: channelId,
                ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              );
            },
          ),
          GoRoute(
            path: '/friends',
            name: 'friends',
            builder: (context, state) =>
                const Center(child: Text('Friends — Coming soon')),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
