import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/gradient_overlay.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _isInvitationPressed = false;
  bool _isLoginPressed = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Design dimensions (iPhone 16 Pro)
    const designWidth = 402.0;
    const designHeight = 874.0;

    // Calculate scale factor based on screen width, maintaining aspect ratio
    final scale = screenWidth / designWidth;

    // Calculate vertical offset to position elements proportionally
    // This ensures elements stay in the same relative position regardless of screen height
    final heightRatio = screenHeight / designHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GradientOverlay(
        child: Stack(
          children: [
          // Blurred gray shadow behind logo
          Positioned(
            left: 58 * scale,
            top: 220 * heightRatio,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 12.25 * scale, sigmaY: 12.25 * scale),
              child: Container(
                width: 152 * scale,
                height: 41 * scale,
                decoration: const BoxDecoration(
                  color: Color(0xFFC5CACF),
                ),
              ),
            ),
          ),

          // Karass logo text
          Positioned(
            left: 29 * scale,
            top: 210 * heightRatio,
            child: SizedBox(
              width: 190 * scale,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: ' k',
                      style: GoogleFonts.michroma(
                        color: Colors.black,
                        fontSize: 36 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.67 * scale,
                      ),
                    ),
                    TextSpan(
                      text: 'arass',
                      style: GoogleFonts.michroma(
                        color: Colors.black,
                        fontSize: 32 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2.67 * scale,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Braille text
          Positioned(
            left: 88 * scale,
            top: 253 * heightRatio,
            child: SizedBox(
              width: 171 * scale,
              child: Opacity(
                opacity: 0.64,
                child: Text(
                  '⠁⠝⠙ ⠽⠕⠥ ⠋⠊⠝⠙',
                  style: GoogleFonts.ibmPlexMono(
                    color: const Color(0xFF848484),
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8 * scale,
                  ),
                ),
              ),
            ),
          ),

          // Grey rectangle with progressive blur (least at top, most at bottom)
          Positioned(
            left: 29 * scale,
            top: 599 * heightRatio,
            child: SizedBox(
              width: 373 * scale,
              height: 35 * scale,
              child: Column(
                children: [
                  // Top - least blur
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 2 * scale, sigmaY: 2 * scale),
                    child: Container(
                      width: 373 * scale,
                      height: 7 * scale,
                      color: const Color(0xFFAFB5BB),
                    ),
                  ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 6 * scale, sigmaY: 6 * scale),
                    child: Container(
                      width: 373 * scale,
                      height: 7 * scale,
                      color: const Color(0xFFAFB5BB),
                    ),
                  ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 10 * scale, sigmaY: 10 * scale),
                    child: Container(
                      width: 373 * scale,
                      height: 7 * scale,
                      color: const Color(0xFFAFB5BB),
                    ),
                  ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 14 * scale, sigmaY: 14 * scale),
                    child: Container(
                      width: 373 * scale,
                      height: 7 * scale,
                      color: const Color(0xFFAFB5BB),
                    ),
                  ),
                  // Bottom - most blur
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 18 * scale, sigmaY: 18 * scale),
                    child: Container(
                      width: 373 * scale,
                      height: 7 * scale,
                      color: const Color(0xFFAFB5BB),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Request an Invitation button
          Positioned(
            left: 53 * scale,
            top: 600 * heightRatio,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isInvitationPressed = true),
              onTapUp: (_) => setState(() => _isInvitationPressed = false),
              onTapCancel: () => setState(() => _isInvitationPressed = false),
              onTap: () {
                context.read<AppProvider>().goToOnboarding1();
              },
              child: Container(
                width: 320 * scale,
                height: 35 * scale,
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: _isInvitationPressed ? 1.0 : 0.64,
                  child: Text(
                    '← Request an Invitation',
                    style: GoogleFonts.manrope(
                      color: _isInvitationPressed
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

          // Login text
          Positioned(
            left: 56 * scale,
            top: 632 * heightRatio,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isLoginPressed = true),
              onTapUp: (_) => setState(() => _isLoginPressed = false),
              onTapCancel: () => setState(() => _isLoginPressed = false),
              onTap: () {
                context.read<AppProvider>().goToLogin();
              },
              child: Container(
                width: 271 * scale,
                height: 30 * scale,
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: _isLoginPressed ? 1.0 : 0.64,
                  child: Text(
                    '    Login',
                    style: GoogleFonts.manrope(
                      color: _isLoginPressed
                          ? Colors.black
                          : const Color(0xFF6C6C6C),
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
