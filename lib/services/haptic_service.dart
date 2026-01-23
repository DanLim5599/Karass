import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

class HapticService {
  bool _hasVibrator = false;

  Future<void> init() async {
    final hasVibrator = await Vibration.hasVibrator();
    _hasVibrator = hasVibrator == true;
  }

  /// Subtle haptic for app launch
  Future<void> lightImpact() async {
    if (_hasVibrator) {
      await Vibration.vibrate(duration: 10, amplitude: 40);
    } else {
      await HapticFeedback.lightImpact();
    }
  }

  /// Medium haptic for beacon detection
  Future<void> mediumImpact() async {
    if (_hasVibrator) {
      await Vibration.vibrate(duration: 20, amplitude: 80);
    } else {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Strong haptic for unlock event
  Future<void> heavyImpact() async {
    if (_hasVibrator) {
      await Vibration.vibrate(duration: 50, amplitude: 128);
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  /// Pattern haptic for special events
  Future<void> successPattern() async {
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 50, 100, 50],
        intensities: [0, 128, 0, 200],
      );
    } else {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.mediumImpact();
    }
  }

  /// Haptic for tap and hold beacon activation
  Future<void> beaconActivated() async {
    if (_hasVibrator) {
      await Vibration.vibrate(duration: 30, amplitude: 100);
    } else {
      await HapticFeedback.selectionClick();
    }
  }
}
