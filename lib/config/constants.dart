/// App-specific constants and configurations
/// For theming, see theme.dart
/// For particle animation, see particle_config.dart

import 'package:flutter/material.dart';
import 'theme.dart';
import 'particle_config.dart';

// Re-export theme for backward compatibility
export 'theme.dart';
export 'particle_config.dart';

class AppColors {
  // Deprecated: Use AppTheme instead
  // Keeping for backward compatibility
  static const primary = AppTheme.primary;
  static const secondary = AppTheme.secondary;
  static const background = AppTheme.background;
  static const surface = AppTheme.surface;
  static const particleWhite = Color(0xFFFFFFFF);
  static const particlePink = Color(0xFFFF6B9D);
  static const particlePurple = Color(0xFF6B4EE6);
  static const textPrimary = AppTheme.textPrimary;
  static const textSecondary = AppTheme.textSecondary;
  static const mutedOpacity = AppTheme.mutedOpacity;
}

class BluetoothConfig {
  // Custom UUID for Karass beacon identification
  // Change this UUID to make your app unique
  static const String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUuid = "12345678-1234-1234-1234-123456789abd";

  // Scan settings
  static const Duration scanDuration = Duration(seconds: 10);
  static const Duration scanInterval = Duration(seconds: 5);
}

class AnimationConfig {
  // Splash screen duration
  static const Duration splashDuration = Duration(milliseconds: 2500);

  // Deprecated: Use ParticleConfig instead
  static const int particleCount = ParticleConfig.count;
  static const double minParticleSize = ParticleConfig.minSize;
  static const double maxParticleSize = ParticleConfig.maxSize;
  static const double minParticleSpeed = ParticleConfig.minSpeed;
  static const double maxParticleSpeed = ParticleConfig.maxSpeed;
  static const Duration particleFadeDuration = Duration(seconds: 4);
}

class StorageKeys {
  static const String isUnlocked = 'karass_is_unlocked';
  static const String hasCompletedSignUp = 'karass_has_completed_signup';
  static const String userEmail = 'karass_user_email';
  static const String username = 'karass_username';
  static const String twitterHandle = 'karass_twitter_handle';
  static const String isPendingApproval = 'karass_pending_approval';
  static const String passwordHash = 'karass_password_hash';
  static const String userId = 'karass_user_id';
  static const String isAdmin = 'karass_is_admin';
}

class ApiConfig {
  // Backend API URL - change this for production
  // 10.0.2.2 is the Android emulator's localhost alias
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  // Note: Admin operations now use JWT-based authentication
  // The user's JWT token contains isAdmin claim which the backend verifies
}
