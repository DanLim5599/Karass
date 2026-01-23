import 'dart:math';
import 'package:flutter/material.dart';
import '../config/particle_config.dart';
import '../config/theme.dart';

/// A single particle in the animation system
class Particle {
  double x;
  double y;
  double size;
  double speedX;
  double speedY;
  double opacity;
  double fadeSpeed;
  Color color;
  bool fadingIn;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
    required this.fadeSpeed,
    required this.color,
    this.fadingIn = true,
  });
}

/// Particle system that manages creation, update, and rendering
/// Configure via ParticleConfig in config/particle_config.dart
class ParticleSystem {
  final List<Particle> particles = [];
  final Random _random = Random();
  final int particleCount;
  final bool muted;

  late double _width;
  late double _height;

  // Reusable paint objects for performance
  final Paint _glowPaint = Paint();
  final Paint _corePaint = Paint();

  ParticleSystem({
    this.particleCount = ParticleConfig.count,
    this.muted = false,
  });

  void init(double width, double height) {
    _width = width;
    _height = height;
    particles.clear();

    for (int i = 0; i < particleCount; i++) {
      particles.add(_createParticle(randomPosition: true));
    }
  }

  Particle _createParticle({bool randomPosition = false}) {
    return Particle(
      x: randomPosition ? _random.nextDouble() * _width : _random.nextDouble() * _width,
      y: randomPosition ? _random.nextDouble() * _height : _height + ParticleConfig.boundaryPadding,
      size: ParticleConfig.minSize +
          _random.nextDouble() * (ParticleConfig.maxSize - ParticleConfig.minSize),
      speedX: (_random.nextDouble() - 0.5) * ParticleConfig.maxSpeed,
      speedY: -(ParticleConfig.minSpeed +
          _random.nextDouble() * (ParticleConfig.maxSpeed - ParticleConfig.minSpeed)),
      opacity: randomPosition ? _random.nextDouble() : 0.0,
      fadeSpeed: ParticleConfig.fadeInSpeed + _random.nextDouble() * ParticleConfig.fadeInSpeed,
      color: ParticleConfig.colors[_random.nextInt(ParticleConfig.colors.length)],
      fadingIn: !randomPosition,
    );
  }

  void update() {
    final boundary = ParticleConfig.boundaryPadding;

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];

      // Update position
      p.x += p.speedX;
      p.y += p.speedY;

      // Update opacity (fade in then fade out)
      if (p.fadingIn) {
        p.opacity += p.fadeSpeed;
        if (p.opacity >= 1.0) {
          p.opacity = 1.0;
          p.fadingIn = false;
        }
      } else {
        p.opacity -= ParticleConfig.fadeOutSpeed;
      }

      // Reset particle if it goes off screen or fades out
      if (p.y < -boundary || p.opacity <= 0 || p.x < -boundary || p.x > _width + boundary) {
        particles[i] = _createParticle();
      }
    }
  }

  void draw(Canvas canvas, Size size) {
    final mutedMultiplier = muted ? AppTheme.mutedOpacity : 1.0;

    for (final p in particles) {
      final baseOpacity = p.opacity * mutedMultiplier;

      // Draw soft glow
      _glowPaint.color = p.color.withOpacity(baseOpacity * ParticleConfig.glowOpacity);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * ParticleConfig.glowRadius,
        _glowPaint,
      );

      // Draw core
      _corePaint.color = p.color.withOpacity(baseOpacity);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * ParticleConfig.coreRadius,
        _corePaint,
      );
    }
  }
}

/// CustomPainter wrapper for the particle system
class ParticlePainter extends CustomPainter {
  final ParticleSystem particleSystem;

  ParticlePainter(this.particleSystem, Listenable repaintNotifier)
      : super(repaint: repaintNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    particleSystem.draw(canvas, size);
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => false;
}
