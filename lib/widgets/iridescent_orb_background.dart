import 'package:flutter/material.dart';

/// Simple pass-through widget - shader removed for performance
class IridescentOrbBackground extends StatelessWidget {
  final Widget? child;

  const IridescentOrbBackground({
    super.key,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Just return the child directly - no shader overhead
    return child ?? const SizedBox.shrink();
  }
}
