import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/api_service.dart';

/// Login screen with premium dark UI — wired to real auth API.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = ref.watch(themeProvider);
    final currentUrl = ref.watch(authServerUrlProvider);

    // Show error snackbar when auth error changes
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Main login form
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
              child: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: theme.bgSecondary,
                      borderRadius: BorderRadius.circular(theme.radiusLg),
                      border: Border.all(
                        color: theme.accentPrimary
                            .withValues(alpha: _glowAnimation.value * 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.accentPrimary
                              .withValues(alpha: _glowAnimation.value * 0.1),
                          blurRadius: 40,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo / Brand
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          theme.accentGradient.createShader(bounds),
                      child: const Text(
                        'ANTARCTICOM',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: AntarcticomTheme.spacingSm),
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AntarcticomTheme.spacingXl),

                    // Username field
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        hintText: 'Username',
                        prefixIcon: Icon(Icons.person_outline,
                            color: theme.textMuted, size: 20),
                      ),
                      style: TextStyle(color: theme.textPrimary),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AntarcticomTheme.spacingMd),

                    // Password field
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline,
                            color: theme.textMuted, size: 20),
                      ),
                      style: TextStyle(color: theme.textPrimary),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    const SizedBox(height: AntarcticomTheme.spacingLg),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: theme.accentGradient,
                          borderRadius: BorderRadius.circular(theme.radiusMd),
                        ),
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Log In'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AntarcticomTheme.spacingMd),

                    // Register link
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: RichText(
                        text: TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: theme.textMuted),
                          children: [
                            TextSpan(
                              text: 'Register',
                              style: TextStyle(
                                color: theme.accentSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Server selector — bottom-right
          Positioned(
            right: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentUrl == kDefaultAuthHubUrl ? 'Official' : 'Custom',
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Auth Server: $currentUrl',
                  child: Material(
                    color: theme.bgTertiary,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showServerDialog(context, theme),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.dns_outlined,
                          color: theme.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showServerDialog(BuildContext context, AppThemeData theme) {
    final currentUrl = ref.read(authServerUrlProvider);
    final controller = TextEditingController(text: currentUrl);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.bgSecondary,
          title:
              Text('Auth Server', style: TextStyle(color: theme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the URL of the auth server you want to connect to.',
                style: TextStyle(color: theme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: TextStyle(color: theme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'http://example.com:8443',
                  hintStyle: TextStyle(color: theme.textMuted),
                  filled: true,
                  fillColor: theme.bgDeepest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  controller.text = kDefaultAuthHubUrl;
                },
                child: Text(
                  'Reset to official server',
                  style: TextStyle(
                    color: theme.accentSecondary,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Cancel', style: TextStyle(color: theme.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isNotEmpty) {
                  ref.read(authServerUrlProvider.notifier).state = url;
                  await saveAuthServerUrl(url);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child:
                  Text('Connect', style: TextStyle(color: theme.accentPrimary)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter username and password'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final success =
        await ref.read(authProvider.notifier).login(username, password);
    if (success && mounted) {
      context.go('/channels/@me');
    }
  }
}
