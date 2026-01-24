import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/karass_logo.dart';

class WaitingForBeaconScreen extends StatefulWidget {
  const WaitingForBeaconScreen({super.key});

  @override
  State<WaitingForBeaconScreen> createState() => _WaitingForBeaconScreenState();
}

class _WaitingForBeaconScreenState extends State<WaitingForBeaconScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the scanning indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start scanning for beacons when this screen appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().startBeaconScanning();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // Stop scanning when leaving this screen
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Spacer(),
                const KarassLogo(size: 100, animated: true),
                const SizedBox(height: 24),
                const KarassLogoText(fontSize: 22),
                const Spacer(),
                _buildWaitingCard(context, appProvider),
                const Spacer(),
                // Debug button only visible in debug builds
                if (kDebugMode)
                  TextButton(
                    onPressed: () => appProvider.debugTriggerBeaconDetected(),
                    child: Text(
                      'DEBUG: Simulate Beacon Found',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingCard(BuildContext context, AppProvider appProvider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(AppTheme.highOpacity),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withOpacity(AppTheme.disabledOpacity),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(AppTheme.faintOpacity),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated scanning indicator
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(AppTheme.subtleOpacity),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    appProvider.isBluetoothOn
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                    size: 40,
                    color: appProvider.isBluetoothOn
                        ? AppTheme.primary
                        : AppTheme.secondary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            appProvider.isBluetoothOn
                ? 'Waiting for Beacon'
                : 'Bluetooth Required',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            appProvider.isBluetoothOn
                ? 'Find another Karass user nearby\nto complete your journey'
                : 'Enable Bluetooth to discover\nother Karass users',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary.withOpacity(AppTheme.highOpacity),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Bluetooth status or scanning indicator
          if (appProvider.isBluetoothOn)
            _buildScanningIndicator()
          else
            _buildEnableBluetoothButton(appProvider),

          const SizedBox(height: 20),

          // User info summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.background.withOpacity(AppTheme.mutedOpacity),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildInfoRow('Username', appProvider.userData.username ?? 'N/A'),
                const SizedBox(height: 8),
                _buildInfoRow('Email', appProvider.userData.email ?? 'N/A'),
                if (appProvider.userData.twitterHandle != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Twitter', appProvider.userData.twitterHandle!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(AppTheme.faintOpacity),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppTheme.primary.withOpacity(AppTheme.highOpacity),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Scanning for nearby users...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary.withOpacity(AppTheme.highOpacity),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnableBluetoothButton(AppProvider appProvider) {
    return OutlinedButton.icon(
      onPressed: () async {
        await appProvider.bluetooth.requestBluetoothOn();
      },
      icon: const Icon(Icons.bluetooth),
      label: const Text('Enable Bluetooth'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
