import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/iridescent_orb_background.dart';
import '../widgets/karass_logo.dart';
import '../widgets/beacon_indicator.dart';
import '../widgets/gradient_overlay.dart';

class BeaconStatusScreen extends StatefulWidget {
  const BeaconStatusScreen({super.key});

  @override
  State<BeaconStatusScreen> createState() => _BeaconStatusScreenState();
}

class _BeaconStatusScreenState extends State<BeaconStatusScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh beacon status when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().checkBeaconStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final isBeacon = appProvider.canBeacon;

    return Scaffold(
      body: GradientOverlay(
        child: IridescentOrbBackground(
          child: SafeArea(
            child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Top: Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    KarassLogo(size: 40),
                    SizedBox(width: 12),
                    KarassLogoText(fontSize: 18),
                  ],
                ),

                const Spacer(),

                // Center: Beacon indicator and status text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Beacon indicator (above the text)
                    BeaconIndicator(
                      onBeaconFired: isBeacon ? () => appProvider.fireBeacon() : null,
                      enabled: isBeacon,
                    ),

                    const SizedBox(height: 32),

                    // Status text
                    Text(
                      isBeacon ? 'Tap to Broadcast' : 'Signaling local users...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: isBeacon
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary.withOpacity(0.7),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Exit button (below the text)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(
                          color: AppTheme.textSecondary.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Exit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
