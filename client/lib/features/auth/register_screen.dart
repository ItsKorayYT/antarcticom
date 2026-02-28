import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

/// Registration screen — wired to real auth API.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = ref.watch(themeProvider);

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
      backgroundColor: theme.bgDeepest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: theme.bgSecondary,
              borderRadius: BorderRadius.circular(AntarcticomTheme.radiusLg),
              border: Border.all(
                color: theme.accentPrimary.withValues(alpha: 0.1),
              ),
            ),
            padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand
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
                  'Create your account',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AntarcticomTheme.spacingXl),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    hintText: 'Username',
                    prefixIcon: Icon(Icons.alternate_email,
                        color: theme.textMuted, size: 20),
                  ),
                  style: TextStyle(color: theme.textPrimary),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Display name
                TextField(
                  controller: _displayNameController,
                  decoration: InputDecoration(
                    hintText: 'Display Name (optional)',
                    prefixIcon: Icon(Icons.badge_outlined,
                        color: theme.textMuted, size: 20),
                  ),
                  style: TextStyle(color: theme.textPrimary),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: theme.textMuted, size: 20),
                  ),
                  style: TextStyle(color: theme.textPrimary),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Confirm password
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: theme.textMuted, size: 20),
                  ),
                  style: TextStyle(color: theme.textPrimary),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleRegister(),
                ),
                const SizedBox(height: AntarcticomTheme.spacingLg),

                // Register button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: theme.accentGradient,
                      borderRadius:
                          BorderRadius.circular(AntarcticomTheme.radiusMd),
                    ),
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleRegister,
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
                          : const Text('Create Account'),
                    ),
                  ),
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Login link
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: RichText(
                    text: TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: theme.textMuted),
                      children: [
                        TextSpan(
                          text: 'Log in',
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
    );
  }

  Future<void> _handleRegister() async {
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 8 characters'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final success = await ref.read(authProvider.notifier).register(
          username,
          password,
          displayName: displayName.isNotEmpty ? displayName : null,
        );
    if (success && mounted) {
      context.go('/channels/@me');
    }
  }
}
