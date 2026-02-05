import 'package:flutter/material.dart';

/// A widget that overlays a gradient image on top of its child.
/// The gradient is displayed at 55% opacity and covers the entire screen.
class GradientOverlay extends StatelessWidget {
  final Widget child;

  const GradientOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Original content
        child,
        // Gradient overlay on top
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 1.0,
              child: Image.asset(
                'assets/images/gradient_overlay.png',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
