import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../config/theme.dart';
import '../painters/particle_painter.dart';

class AnimatedBackground extends StatefulWidget {
  final bool muted;
  final Widget? child;

  const AnimatedBackground({
    super.key,
    this.muted = false,
    this.child,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late ParticleSystem _particleSystem;
  bool _initialized = false;
  final _repaintNotifier = _ParticleRepaintNotifier();

  @override
  void initState() {
    super.initState();
    _particleSystem = ParticleSystem(muted: widget.muted);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(AnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.muted != widget.muted) {
      _particleSystem = ParticleSystem(muted: widget.muted);
      _initialized = false;
    }
  }

  void _onTick(Duration elapsed) {
    if (_initialized) {
      _particleSystem.update();
      _repaintNotifier.notify();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialized && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
          _particleSystem.init(constraints.maxWidth, constraints.maxHeight);
          _initialized = true;
        }

        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            gradient: widget.muted
                ? AppTheme.mutedBackgroundGradient
                : AppTheme.backgroundGradient,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_initialized)
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: ParticlePainter(_particleSystem, _repaintNotifier),
                  ),
                ),
              if (widget.child != null)
                Positioned.fill(child: widget.child!),
            ],
          ),
        );
      },
    );
  }
}

class _ParticleRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
