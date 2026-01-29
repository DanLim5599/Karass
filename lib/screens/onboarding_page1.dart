import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/iridescent_orb_background.dart';
import '../widgets/karass_logo.dart';

class OnboardingPage1 extends StatelessWidget {
  const OnboardingPage1({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IridescentOrbBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top section with Karass logo
              const SizedBox(height: 60),
              const KarassLogo(size: 80),
              const SizedBox(height: 16),
              const KarassLogoText(fontSize: 20),

              // Filler content area (placeholder for future Figma designs)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Onboarding content will go here',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

              // Next button at bottom
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<AppProvider>().goToOnboarding2();
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
                      'Next',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
