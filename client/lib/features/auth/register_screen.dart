import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Registration screen.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

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
    return Scaffold(
      backgroundColor: AntarcticomTheme.bgDeepest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AntarcticomTheme.bgSecondary,
              borderRadius: BorderRadius.circular(AntarcticomTheme.radiusLg),
              border: Border.all(
                color: AntarcticomTheme.accentPrimary.withValues(alpha: 0.1),
              ),
            ),
            padding: const EdgeInsets.all(AntarcticomTheme.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand
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
                  'Create your account',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AntarcticomTheme.spacingXl),

                // Username
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    hintText: 'Username',
                    prefixIcon: Icon(Icons.alternate_email,
                        color: AntarcticomTheme.textMuted, size: 20),
                  ),
                  style: const TextStyle(color: AntarcticomTheme.textPrimary),
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Display name
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    hintText: 'Display Name',
                    prefixIcon: Icon(Icons.badge_outlined,
                        color: AntarcticomTheme.textMuted, size: 20),
                  ),
                  style: const TextStyle(color: AntarcticomTheme.textPrimary),
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Password
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
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Confirm password
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: AntarcticomTheme.textMuted, size: 20),
                  ),
                  style: const TextStyle(color: AntarcticomTheme.textPrimary),
                ),
                const SizedBox(height: AntarcticomTheme.spacingLg),

                // Register button
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
                      onPressed: _isLoading ? null : _handleRegister,
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
                          : const Text('Create Account'),
                    ),
                  ),
                ),
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Login link
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: RichText(
                    text: const TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: AntarcticomTheme.textMuted),
                      children: [
                        TextSpan(
                          text: 'Log in',
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

  Future<void> _handleRegister() async {
    setState(() => _isLoading = true);
    // TODO: implement registration via API
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
  }
}
