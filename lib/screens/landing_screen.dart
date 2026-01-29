import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/iridescent_orb_background.dart';
import '../widgets/karass_logo.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: IridescentOrbBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top section with Karass logo
              const SizedBox(height: 60),
              const KarassLogo(size: 100),
              const SizedBox(height: 16),
              const KarassLogoText(fontSize: 24),

              // Spacer to push buttons below midpoint
              Expanded(
                child: Container(),
              ),

              // Buttons section (starts below midpoint)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    // Request an Invitation button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          context.read<AppProvider>().goToOnboarding1();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: const BorderSide(color: AppTheme.primary, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Request an Invitation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          context.read<AppProvider>().goToLogin();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom spacing
              SizedBox(height: screenHeight * 0.15),
            ],
          ),
        ),
      ),
    );
  }
}
