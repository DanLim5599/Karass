import 'package:flutter/material.dart';

/// App theme configuration - Minimalist White Theme
class AppTheme {
  // Primary brand colors - subtle and minimal
  static const Color primary = Color(0xFF1A1A1A);
  static const Color secondary = Color(0xFF666666);

  // Background colors - clean white
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF5F5F5);
  static const Color surfaceVariant = Color(0xFFEEEEEE);

  // Text colors - dark on light
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF999999);

  // Accent colors
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color error = Color(0xFFD32F2F);

  // Border colors
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFF0F0F0);

  // Opacity levels - use these instead of hardcoded values
  static const double activeOpacity = 1.0;
  static const double highOpacity = 0.8;
  static const double mediumOpacity = 0.6;
  static const double mutedOpacity = 0.5;
  static const double disabledOpacity = 0.3;
  static const double subtleOpacity = 0.2;
  static const double faintOpacity = 0.1;
  static const double hintOpacity = 0.05;

  // Border radius - minimal
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;

  // Spacing
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  // Font sizes
  static const double fontSizeSmall = 12.0;
  static const double fontSizeMedium = 14.0;
  static const double fontSizeLarge = 16.0;
  static const double fontSizeXLarge = 20.0;
  static const double fontSizeTitle = 24.0;

  // Gradients - subtle white gradients
  static LinearGradient get backgroundGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, surface],
  );

  static LinearGradient get mutedBackgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      background.withOpacity(0.95),
      surface.withOpacity(0.95),
    ],
  );

  // Box decoration presets
  static BoxDecoration cardDecoration({bool muted = false}) => BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(borderRadiusMedium),
    border: Border.all(
      color: border,
      width: 1,
    ),
  );

  // Button styles
  static ButtonStyle get primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(
      horizontal: spacingLarge,
      vertical: spacingMedium,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusSmall),
    ),
  );

  // Text styles
  static TextStyle get headingStyle => const TextStyle(
    fontSize: fontSizeTitle,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  static TextStyle get bodyStyle => const TextStyle(
    fontSize: fontSizeMedium,
    color: textSecondary,
  );

  static TextStyle get captionStyle => const TextStyle(
    fontSize: fontSizeSmall,
    color: textMuted,
  );
}
