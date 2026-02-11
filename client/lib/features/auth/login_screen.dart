import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Login screen with premium dark UI.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
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
    return Scaffold(
      backgroundColor: AntarcticomTheme.bgDeepest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: AntarcticomTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(AntarcticomTheme.radiusLg),
                  border: Border.all(
                    color: AntarcticomTheme.accentPrimary
                        .withValues(alpha: _glowAnimation.value * 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AntarcticomTheme.accentPrimary
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
                      AntarcticomTheme.accentGradient.createShader(bounds),
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
                  decoration: const InputDecoration(
                    hintText: 'Username',
                    prefixIcon: Icon(Icons.person_outline,
                        color: AntarcticomTheme.textMuted, size: 20),
                  ),
                  style: const TextStyle(color: AntarcticomTheme.textPrimary),
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: AntarcticomTheme.textMuted, size: 20),
                  ),
                  style: const TextStyle(color: AntarcticomTheme.textPrimary),
                ),
                const SizedBox(height: AntarcticomTheme.spacingLg),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AntarcticomTheme.accentGradient,
                      borderRadius:
                          BorderRadius.circular(AntarcticomTheme.radiusMd),
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: _isLoading
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
                  onPressed: () {
                    // Navigate to register
                  },
                  child: RichText(
                    text: const TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(color: AntarcticomTheme.textMuted),
                      children: [
                        TextSpan(
                          text: 'Register',
                          style: TextStyle(
                            color: AntarcticomTheme.accentSecondary,
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

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    // TODO: implement actual login via API
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }
}
