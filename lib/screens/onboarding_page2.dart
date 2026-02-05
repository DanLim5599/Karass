import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/gradient_overlay.dart';

class OnboardingPage2 extends StatefulWidget {
  const OnboardingPage2({super.key});

  @override
  State<OnboardingPage2> createState() => _OnboardingPage2State();
}

class _OnboardingPage2State extends State<OnboardingPage2> {
  bool _isNextPressed = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    // Design dimensions (iPhone 16 Pro)
    const designWidth = 402.0;
    const designHeight = 874.0;

    // Calculate scale factor based on width
    final scale = screenWidth / designWidth;

    // Available height after safe areas
    final availableHeight = screenHeight - safeAreaTop - safeAreaBottom;
    final heightRatio = availableHeight / designHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GradientOverlay(
        child: Stack(
          children: [
          // Blurred shadow behind logo
          Positioned(
            left: 131 * scale,
            top: safeAreaTop + 35 * heightRatio,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12.25 * scale, sigmaY: 12.25 * scale),
              child: Container(
                width: 127 * scale,
                height: 30 * scale,
                decoration: BoxDecoration(
                  color: const Color(0xFFC5CACF).withOpacity(0.59),
                ),
              ),
            ),
          ),

          // Logo text "karass"
          Positioned(
            left: 0,
            right: 0,
            top: safeAreaTop + 27 * heightRatio,
            child: Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ' ',
                      style: GoogleFonts.michroma(
                        color: const Color(0xFF6C6C6C),
                        fontSize: 24.3 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.67 * scale,
                      ),
                    ),
                    TextSpan(
                      text: 'k',
                      style: GoogleFonts.michroma(
                        color: const Color(0xFF6C6C6C),
                        fontSize: 28 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.67 * scale,
                      ),
                    ),
                    TextSpan(
                      text: 'arass',
                      style: GoogleFonts.michroma(
                        color: const Color(0xFF6C6C6C),
                        fontSize: 24.3 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.67 * scale,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Braille text
          Positioned(
            left: 0,
            right: 0,
            top: safeAreaTop + 69 * heightRatio,
            child: Center(
              child: Opacity(
                opacity: 0.64,
                child: Text(
                  '⠁⠝⠙ ⠽⠕⠥ ⠋⠊⠝⠙',
                  style: GoogleFonts.ibmPlexMono(
                    color: const Color(0xFF848484),
                    fontSize: 13.5 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.35 * scale,
                  ),
                ),
              ),
            ),
          ),

          // First text block - "Each week, one member..."
          Positioned(
            left: 39 * scale,
            right: 39 * scale,
            top: safeAreaTop + 220 * heightRatio,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Each week, one member of the network is appointed as a ',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w300,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: 'Beacon',
                    style: GoogleFonts.michroma(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: '.',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w300,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Beacon image - outer glow 2
          Positioned(
            left: (screenWidth - 143 * scale) / 2,
            top: safeAreaTop + 330 * heightRatio,
            child: Opacity(
              opacity: 0.87,
              child: Image.asset(
                'assets/images/beacon_glow2.png',
                width: 143 * scale,
                height: 143 * scale,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Beacon image - outer glow 1
          Positioned(
            left: (screenWidth - 130 * scale) / 2,
            top: safeAreaTop + 330 * heightRatio,
            child: Opacity(
              opacity: 0.87,
              child: Image.asset(
                'assets/images/beacon_glow1.png',
                width: 130 * scale,
                height: 130 * scale,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Beacon image - main circle
          Positioned(
            left: (screenWidth - 113 * scale) / 2,
            top: safeAreaTop + 338 * heightRatio,
            child: Opacity(
              opacity: 0.87,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  1.15, 0, 0, 0, 25,
                  0, 1.15, 0, 0, 25,
                  0, 0, 1.15, 0, 25,
                  0, 0, 0, 1, 0,
                ]),
                child: Image.asset(
                  'assets/images/beacon_circle.png',
                  width: 113 * scale,
                  height: 113 * scale,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Second text block - "A Beacon broadcasts..."
          Positioned(
            left: 39 * scale,
            right: 39 * scale,
            top: safeAreaTop + 470 * heightRatio,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'A ',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w300,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: 'Beacon',
                    style: GoogleFonts.michroma(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  TextSpan(
                    text: ' broadcasts a local signal opening membership access to select, nearby applicants.',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7C7B7B),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w300,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Blurred button background
          Positioned(
            right: 33 * scale,
            top: safeAreaTop + 599 * heightRatio,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18.55 * scale, sigmaY: 18.55 * scale),
              child: Container(
                width: 100 * scale,
                height: 31 * scale,
                decoration: BoxDecoration(
                  color: const Color(0xFFAFB5BB),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x40000000),
                      blurRadius: 4.9 * scale,
                      offset: Offset(0, 1 * scale),
                      spreadRadius: 1 * scale,
                    )
                  ],
                ),
              ),
            ),
          ),

          // Next button
          Positioned(
            right: 33 * scale,
            top: safeAreaTop + 599 * heightRatio,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isNextPressed = true),
              onTapUp: (_) => setState(() => _isNextPressed = false),
              onTapCancel: () => setState(() => _isNextPressed = false),
              onTap: () {
                context.read<AppProvider>().goToCreateAccount();
              },
              child: Container(
                width: 100 * scale,
                height: 31 * scale,
                alignment: Alignment.center,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: _isNextPressed ? 1.0 : 0.64,
                  child: Text(
                    'Next→',
                    style: GoogleFonts.manrope(
                      color: _isNextPressed
                          ? Colors.black
                          : Colors.white.withOpacity(0.97),
                      fontSize: 16.5 * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.64 * scale,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
