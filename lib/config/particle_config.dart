import 'package:flutter/material.dart';

/// Particle configuration - Minimalist subtle dots
class ParticleConfig {
  // Fewer particles for minimal look
  static const int count = 15;

  // Small, subtle particles
  static const double minSize = 2.0;
  static const double maxSize = 4.0;

  // Slow, gentle movement
  static const double minSpeed = 0.2;
  static const double maxSpeed = 0.5;

  // Slow fade for subtlety
  static const double fadeInSpeed = 0.003;
  static const double fadeOutSpeed = 0.002;

  // Subtle gray tones
  static const List<Color> colors = [
    Color(0xFFCCCCCC),
    Color(0xFFDDDDDD),
    Color(0xFFBBBBBB),
  ];

  // Minimal glow
  static const double glowRadius = 1.2;
  static const double glowOpacity = 0.15;
  static const double coreRadius = 0.5;

  static const double boundaryPadding = 20.0;
}
