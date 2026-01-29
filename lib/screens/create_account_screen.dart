import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/iridescent_orb_background.dart';
import '../widgets/karass_logo.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _twitterController = TextEditingController();

  bool _isLoading = false;
  bool _isTwitterLoading = false;
  bool _isGitHubLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  bool get _isAnyAuthLoading => _isLoading || _isTwitterLoading || _isGitHubLoading;

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
    if (_isAnyAuthLoading) return;

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

  Future<void> _handleGitHubSignIn() async {
    if (_isAnyAuthLoading) return;

    setState(() {
      _isGitHubLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await context.read<AppProvider>().loginWithGitHub();
      if (!result.success && mounted) {
        setState(() => _errorMessage = result.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isGitHubLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_isAnyAuthLoading) return;
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
    return Scaffold(
      body: IridescentOrbBackground(
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
                _buildForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
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

            // Twitter Sign In Button
            OutlinedButton.icon(
              onPressed: _isAnyAuthLoading ? null : _handleTwitterSignIn,
              icon: _isTwitterLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Text(
                      'X',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
              label: Text(
                _isTwitterLoading ? 'Connecting...' : 'Log in with X',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),

            // GitHub Sign In Button
            OutlinedButton.icon(
              onPressed: _isAnyAuthLoading ? null : _handleGitHubSignIn,
              icon: _isGitHubLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                      ),
                    )
                  : const Icon(Icons.code, size: 20),
              label: Text(
                _isGitHubLoading ? 'Connecting...' : 'Log in with GitHub',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Divider(color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity)),
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
                  child: Divider(color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity)),
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
              onPressed: _isAnyAuthLoading ? null : _submit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isLoading
                  ? const SizedBox(
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

            // Login link
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
                  onTap: () => context.read<AppProvider>().goToLogin(),
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
