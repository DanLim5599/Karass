import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'models/app_state.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/waiting_for_beacon_screen.dart';
import 'screens/home_screen.dart';

class KarassApp extends StatelessWidget {
  const KarassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..init(),
      child: MaterialApp(
        title: 'Karass',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: AppTheme.background,
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            secondary: AppTheme.secondary,
            surface: AppTheme.surface,
          ),
          fontFamily: 'SF Pro Display',
        ),
        home: const AppNavigator(),
      ),
    );
  }
}

class AppNavigator extends StatelessWidget {
  const AppNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();

    // Show loading while initializing
    if (!appProvider.isInitialized) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primary,
          ),
        ),
      );
    }

    // Navigate based on app stage
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: _buildScreen(appProvider.stage),
    );
  }

  Widget _buildScreen(AppStage stage) {
    switch (stage) {
      case AppStage.splash:
        return const SplashScreen(key: ValueKey('splash'));
      case AppStage.signUp:
        return const SignUpScreen(key: ValueKey('signup'));
      case AppStage.waitingForBeacon:
        return const WaitingForBeaconScreen(key: ValueKey('waiting'));
      case AppStage.unlocked:
        return const HomeScreen(key: ValueKey('home'));
    }
  }
}