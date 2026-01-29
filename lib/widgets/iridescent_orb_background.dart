import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class IridescentOrbBackground extends StatefulWidget {
  final Widget? child;

  const IridescentOrbBackground({
    super.key,
    this.child,
  });

  @override
  State<IridescentOrbBackground> createState() => _IridescentOrbBackgroundState();
}

class _IridescentOrbBackgroundState extends State<IridescentOrbBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  double _time = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadShader() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/iridescent_orb.frag');
      _shader = _program!.fragmentShader();
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load shader: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _time = elapsed.inMilliseconds / 1000.0;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Shader background
            if (_shader != null && !_loading)
              RepaintBoundary(
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _ShaderPainter(
                    shader: _shader!,
                    time: _time,
                    resolution: Size(width, height),
                  ),
                ),
              )
            else
              // Fallback gradient while loading or on error
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFF8F9FA),
                      Color(0xFFFFFFFF),
                    ],
                  ),
                ),
              ),

            // Child content
            if (widget.child != null)
              Positioned.fill(child: widget.child!),
          ],
        );
      },
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final Size resolution;

  _ShaderPainter({
    required this.shader,
    required this.time,
    required this.resolution,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Set uniforms: uResolution (vec2) and uTime (float)
    // Index 0: resolution.x
    // Index 1: resolution.y
    // Index 2: time
    shader.setFloat(0, resolution.width);
    shader.setFloat(1, resolution.height);
    shader.setFloat(2, time);

    final paint = Paint()..shader = shader;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShaderPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.resolution != resolution;
  }
}
