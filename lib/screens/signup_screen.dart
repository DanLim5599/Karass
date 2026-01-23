import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/karass_logo.dart';

enum AuthMode { createAccount, login }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Start with create account screen (not choice)
  AuthMode _mode = AuthMode.createAccount;

  void _setMode(AuthMode mode) {
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const KarassLogo(size: 80),
                const SizedBox(height: 16),
                const KarassLogoText(fontSize: 20),
                const SizedBox(height: 40),
                _buildWelcomeBanner(),
                const SizedBox(height: 32),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withOpacity(AppTheme.disabledOpacity),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(AppTheme.faintOpacity),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to Karass',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Create an account to get started',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case AuthMode.createAccount:
        return _CreateAccountView(
          key: const ValueKey('create'),
          onSwitchToLogin: () => _setMode(AuthMode.login),
        );
      case AuthMode.login:
        return _LoginView(
          key: const ValueKey('login'),
          onSwitchToCreate: () => _setMode(AuthMode.createAccount),
        );
    }
  }
}

// Create Account screen (main screen)
class _CreateAccountView extends StatefulWidget {
  final VoidCallback onSwitchToLogin;

  const _CreateAccountView({
    super.key,
    required this.onSwitchToLogin,
  });

  @override
  State<_CreateAccountView> createState() => _CreateAccountViewState();
}

class _CreateAccountViewState extends State<_CreateAccountView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _twitterController = TextEditingController();

  bool _isLoading = false;
  bool _isTwitterLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _twitterController.dispose();
    super.dispose();
  }

  Future<void> _handleTwitterSignIn() async {
    setState(() {
      _isTwitterLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await context.read<AppProvider>().loginWithTwitter();

      if (!result.success && mounted) {
        setState(() => _errorMessage = result.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isTwitterLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await context.read<AppProvider>().createAccount(
            email: _emailController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            twitterHandle: _twitterController.text.trim().isEmpty
                ? null
                : _twitterController.text.trim(),
          );

      if (!result.success && mounted) {
        setState(() => _errorMessage = result.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(AppTheme.highOpacity),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(AppTheme.subtleOpacity),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join the Karass network',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withOpacity(AppTheme.highOpacity),
              ),
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(AppTheme.faintOpacity),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(AppTheme.disabledOpacity)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Twitter Sign In Button (at top)
            OutlinedButton.icon(
              onPressed: _isTwitterLoading ? null : _handleTwitterSignIn,
              icon: _isTwitterLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Text(
                      'X',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              label: Text(
                _isTwitterLoading ? 'Connecting...' : 'Sign up with X',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Or sign up with email',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity),
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Email', Icons.email_outlined),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                if (!value.contains('@')) return 'Invalid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Username
            TextFormField(
              controller: _usernameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Username', Icons.person_outline),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                if (value.length < 3) return 'Min 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                if (value.length < 6) return 'Min 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm Password
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Confirm Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              validator: (value) {
                if (value != _passwordController.text) return 'Passwords don\'t match';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Twitter (optional)
            TextFormField(
              controller: _twitterController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('X handle (optional)', Icons.alternate_email),
            ),
            const SizedBox(height: 24),

            // Submit
            OutlinedButton(
              onPressed: _isLoading ? null : _submit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Text(
                      'Create Account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
            ),
            const SizedBox(height: 24),

            // Login link at bottom
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.highOpacity),
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: widget.onSwitchToLogin,
                  child: const Text(
                    'Log in',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity)),
      prefixIcon: Icon(icon, color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.secondary),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.secondary),
      ),
      filled: true,
      fillColor: AppTheme.background.withOpacity(AppTheme.mutedOpacity),
    );
  }
}

// Login screen
class _LoginView extends StatefulWidget {
  final VoidCallback onSwitchToCreate;

  const _LoginView({
    super.key,
    required this.onSwitchToCreate,
  });

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailOrUsernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isTwitterLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailOrUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleTwitterSignIn() async {
    setState(() {
      _isTwitterLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await context.read<AppProvider>().loginWithTwitter();

      if (!result.success && mounted) {
        setState(() => _errorMessage = result.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isTwitterLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await context.read<AppProvider>().login(
            emailOrUsername: _emailOrUsernameController.text.trim(),
            password: _passwordController.text,
          );

      if (!result.success && mounted) {
        setState(() => _errorMessage = result.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(AppTheme.highOpacity),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(AppTheme.subtleOpacity),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome Back',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log in to your account',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withOpacity(AppTheme.highOpacity),
              ),
            ),
            const SizedBox(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(AppTheme.faintOpacity),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.error.withOpacity(AppTheme.disabledOpacity)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Twitter Sign In Button
            OutlinedButton.icon(
              onPressed: _isTwitterLoading ? null : _handleTwitterSignIn,
              icon: _isTwitterLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Text(
                      'X',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              label: Text(
                _isTwitterLoading ? 'Connecting...' : 'Log in with X',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Or log in with email',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity),
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Email or Username
            TextFormField(
              controller: _emailOrUsernameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Email or Username', Icons.person_outline),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Required';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Submit
            OutlinedButton(
              onPressed: _isLoading ? null : _submit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Text(
                      'Log In',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
            ),
            const SizedBox(height: 24),

            // Create account link at bottom
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Don\'t have an account? ',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.highOpacity),
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: widget.onSwitchToCreate,
                  child: const Text(
                    'Sign up',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity)),
      prefixIcon: Icon(icon, color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.secondary),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.secondary),
      ),
      filled: true,
      fillColor: AppTheme.background.withOpacity(AppTheme.mutedOpacity),
    );
  }
}
