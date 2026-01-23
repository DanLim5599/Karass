import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Logo configuration - Minimalist design
class LogoConfig {
  static const String logoText = 'K';
  static const String appName = 'KARASS';
  static const double defaultLogoSize = 120;
  static const double defaultFontSize = 32;
  static const double textLetterSpacingRatio = 0.4;
  static const double logoFontSizeRatio = 0.45;
}

/// Minimalist logo - simple circle with letter
class KarassLogo extends StatelessWidget {
  final double size;
  final bool muted;
  final bool animated;

  const KarassLogo({
    super.key,
    this.size = LogoConfig.defaultLogoSize,
    this.muted = false,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = muted ? AppTheme.mutedOpacity : 1.0;

    Widget logo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: AppTheme.primary.withOpacity(opacity * 0.15),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          LogoConfig.logoText,
          style: TextStyle(
            fontSize: size * LogoConfig.logoFontSizeRatio,
            fontWeight: FontWeight.w300,
            color: AppTheme.textPrimary.withOpacity(opacity),
            letterSpacing: -2,
          ),
        ),
      ),
    );

    if (animated) {
      return _AnimatedLogo(child: logo);
    }

    return logo;
  }
}

class _AnimatedLogo extends StatefulWidget {
  final Widget child;

  const _AnimatedLogo({required this.child});

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: widget.child,
        );
      },
    );
  }
}

/// Minimalist app name text
class KarassLogoText extends StatelessWidget {
  final double fontSize;
  final bool muted;

  const KarassLogoText({
    super.key,
    this.fontSize = LogoConfig.defaultFontSize,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = muted ? AppTheme.mutedOpacity : 1.0;

    return Text(
      LogoConfig.appName,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w300,
        letterSpacing: fontSize * LogoConfig.textLetterSpacingRatio,
        color: AppTheme.textPrimary.withOpacity(opacity),
      ),
    );
  }
}
