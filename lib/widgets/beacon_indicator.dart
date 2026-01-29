import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

class BeaconIndicator extends StatefulWidget {
  final VoidCallback? onBeaconFired;
  final bool enabled;

  const BeaconIndicator({
    super.key,
    this.onBeaconFired,
    this.enabled = true,
  });

  @override
  State<BeaconIndicator> createState() => _BeaconIndicatorState();
}

class _BeaconIndicatorState extends State<BeaconIndicator>
    with TickerProviderStateMixin {
  late AnimationController _chargeController;
  late AnimationController _releaseController;

  bool _isCharging = false;
  bool _isCharged = false;
  bool _beaconFired = false;
  double _chargeProgress = 0.0;

  static const Duration _chargeDuration = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();

    _chargeController = AnimationController(
      duration: _chargeDuration,
      vsync: this,
    );

    _chargeController.addListener(_onChargeProgress);
    _chargeController.addStatusListener(_onChargeStatus);

    _releaseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _releaseController.addListener(() {
      setState(() {
        _chargeProgress = _releaseController.value;
      });
    });

    _releaseController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() {
          _beaconFired = false;
        });
      }
    });
  }

  void _onChargeProgress() {
    setState(() {
      _chargeProgress = _chargeController.value;
    });

    // Haptic feedback at progress milestones
    if (_chargeController.value >= 0.33 && _chargeController.value < 0.34) {
      HapticFeedback.lightImpact();
    } else if (_chargeController.value >= 0.66 && _chargeController.value < 0.67) {
      HapticFeedback.lightImpact();
    } else if (_chargeController.value >= 0.95 && !_isCharged) {
      HapticFeedback.mediumImpact();
    }
  }

  void _onChargeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _isCharged = true;
      });
      HapticFeedback.heavyImpact();
    }
  }

  void _onPressStart() {
    // Don't allow charging if beacon is disabled
    if (!widget.enabled) return;

    // Stop any uncharge animation
    _releaseController.stop();

    // Start charging from current progress (don't reset to 0)
    final currentProgress = _chargeProgress;

    setState(() {
      _isCharging = true;
      _isCharged = false;
      _beaconFired = false;
    });

    _chargeController.forward(from: currentProgress);
    HapticFeedback.selectionClick();
  }

  void _onPressEnd() {
    _chargeController.stop();

    if (_isCharged) {
      // Beacon fires!
      setState(() {
        _beaconFired = true;
        _isCharging = false;
      });

      HapticFeedback.heavyImpact();
      widget.onBeaconFired?.call();

      // Animate release ripple then fade out
      _releaseController.reverse(from: 1.0);
    } else {
      // Released too early - animate charge down
      setState(() {
        _isCharging = false;
      });

      final currentProgress = _chargeController.value;
      _releaseController.value = currentProgress;
      _releaseController.reverse(from: currentProgress);
    }

    setState(() {
      _isCharged = false;
    });
  }

  @override
  void dispose() {
    _chargeController.dispose();
    _releaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onPressStart(),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: () => _onPressEnd(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Charge ring
                  CustomPaint(
                    size: const Size(100, 100),
                    painter: ChargeRingPainter(
                      progress: _chargeProgress,
                      isCharged: _isCharged,
                      beaconFired: _beaconFired,
                    ),
                  ),
                  // Center beacon icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !widget.enabled
                          ? AppTheme.surface.withOpacity(0.5)
                          : _isCharged || _beaconFired
                              ? AppTheme.primary
                              : AppTheme.surface,
                      border: Border.all(
                        color: !widget.enabled
                            ? AppTheme.textMuted.withOpacity(0.3)
                            : _isCharging || _beaconFired
                                ? AppTheme.primary
                                : AppTheme.textSecondary.withOpacity(AppTheme.subtleOpacity),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.wifi_tethering,
                      color: !widget.enabled
                          ? AppTheme.textMuted.withOpacity(0.4)
                          : _isCharged || _beaconFired
                              ? Colors.white
                              : AppTheme.textSecondary,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
                color: !widget.enabled
                    ? AppTheme.textMuted.withOpacity(0.4)
                    : _beaconFired
                        ? AppTheme.primary
                        : _isCharged
                            ? AppTheme.primary
                            : _isCharging
                                ? AppTheme.textSecondary
                                : AppTheme.textMuted,
              ),
              child: Text(
                !widget.enabled
                    ? 'BEACON DISABLED'
                    : _beaconFired
                        ? 'BEACON SENT'
                        : _isCharged
                            ? 'RELEASE TO SEND'
                            : _isCharging
                                ? 'CHARGING...'
                                : 'HOLD TO BEACON',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChargeRingPainter extends CustomPainter {
  final double progress;
  final bool isCharged;
  final bool beaconFired;

  ChargeRingPainter({
    required this.progress,
    required this.isCharged,
    required this.beaconFired,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background ring
    final bgPaint = Paint()
      ..color = AppTheme.textSecondary.withOpacity(AppTheme.faintOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      // Progress ring
      final progressPaint = Paint()
        ..color = isCharged || beaconFired
            ? AppTheme.primary
            : AppTheme.textSecondary.withOpacity(AppTheme.mutedOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2, // Start from top
        sweepAngle,
        false,
        progressPaint,
      );
    }

    // Ripple effect when beacon fires
    if (beaconFired && progress > 0) {
      for (int i = 0; i < 2; i++) {
        final rippleProgress = ((1.0 - progress) + i * 0.3) % 1.0;
        final rippleRadius = radius + (30 * rippleProgress);
        final opacity = (1.0 - rippleProgress) * 0.3;

        final ripplePaint = Paint()
          ..color = AppTheme.primary.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

        canvas.drawCircle(center, rippleRadius, ripplePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChargeRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isCharged != isCharged ||
        oldDelegate.beaconFired != beaconFired;
  }
}
