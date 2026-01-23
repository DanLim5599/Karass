import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

/// A widget that animates text materializing with a fade effect.
/// Characters appear one at a time from left to right over 2 seconds.
/// The text shrinks from max size to 14 over 1 second.
class DustTextAnimation extends StatefulWidget {
  final String text;
  final VoidCallback? onComplete;

  const DustTextAnimation({
    super.key,
    required this.text,
    this.onComplete,
  });

  @override
  State<DustTextAnimation> createState() => _DustTextAnimationState();
}

class _DustTextAnimationState extends State<DustTextAnimation>
    with TickerProviderStateMixin {
  late AnimationController _materializeController;
  late AnimationController _shrinkController;

  // Cache the Open Sans text style to ensure consistency
  late TextStyle _baseTextStyle;

  List<_CharacterState> _characterStates = [];
  double _startFontSize = 48;
  bool _hasCalculatedSize = false;
  bool _materializationComplete = false;

  @override
  void initState() {
    super.initState();

    // Pre-load the Open Sans font style
    _baseTextStyle = GoogleFonts.openSans(
      fontWeight: FontWeight.w400,
      color: AppTheme.textPrimary,
    );

    // Materialization: 2 seconds for all characters to appear
    _materializeController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Shrink: 1 second to shrink from max to 14
    _shrinkController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _materializeController.addListener(_updateCharacterStates);

    _materializeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _materializationComplete = true;
        widget.onComplete?.call();
      }
    });
  }

  void _calculateStartFontSize(BoxConstraints constraints) {
    if (_hasCalculatedSize) return;

    final maxWidth = constraints.maxWidth - 48; // Padding

    // Binary search for the largest font size that fits
    double minSize = 14;
    double maxSize = 200;

    while (maxSize - minSize > 0.5) {
      final testSize = (minSize + maxSize) / 2;
      final textPainter = TextPainter(
        text: TextSpan(
          text: widget.text,
          style: _baseTextStyle.copyWith(fontSize: testSize),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      if (textPainter.width <= maxWidth) {
        minSize = testSize;
      } else {
        maxSize = testSize;
      }
    }

    _startFontSize = minSize;

    // Initialize character states
    _characterStates = List.generate(
      widget.text.length,
      (index) => _CharacterState(
        character: widget.text[index],
        appearTime: index / widget.text.length,
      ),
    );

    _hasCalculatedSize = true;

    // Start the animations
    _materializeController.forward();
    _shrinkController.forward();
  }

  void _updateCharacterStates() {
    final progress = _materializeController.value;

    for (var state in _characterStates) {
      if (progress >= state.appearTime && !state.isVisible) {
        state.isVisible = true;
      }

      if (state.isVisible) {
        // Quick fade-in for each character
        final charProgress = ((progress - state.appearTime) / 0.1).clamp(0.0, 1.0);
        state.opacity = charProgress;
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _materializeController.dispose();
    _shrinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_hasCalculatedSize) {
          _calculateStartFontSize(constraints);
        }

        return AnimatedBuilder(
          animation: Listenable.merge([
            _shrinkController,
            _materializeController,
          ]),
          builder: (context, child) {
            // Font size: lerp from _startFontSize to 14 over 1 second
            final fontSize = _hasCalculatedSize
                ? _startFontSize - (_startFontSize - 14) * _shrinkController.value
                : _startFontSize;

            return Center(
              child: _buildText(fontSize),
            );
          },
        );
      },
    );
  }

  Widget _buildText(double fontSize) {
    // Use the cached base text style with the current font size
    final textStyle = _baseTextStyle.copyWith(fontSize: fontSize);

    // Always use RichText for consistent rendering throughout the animation
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: textStyle,
        children: List.generate(widget.text.length, (index) {
          // After materialization, all characters are fully visible
          final charOpacity = _materializationComplete
              ? 1.0
              : (_characterStates.isNotEmpty && _characterStates[index].isVisible
                  ? _characterStates[index].opacity
                  : 0.0);

          return TextSpan(
            text: widget.text[index],
            style: TextStyle(
              color: AppTheme.textPrimary.withOpacity(charOpacity),
            ),
          );
        }),
      ),
    );
  }
}

class _CharacterState {
  final String character;
  final double appearTime;
  bool isVisible = false;
  double opacity = 0.0;

  _CharacterState({
    required this.character,
    required this.appearTime,
  });
}

/// Widget to display the announcement with dust animation and location
class AnnouncementDisplay extends StatefulWidget {
  final String announcementText;
  final String location;
  final VoidCallback? onAnimationComplete;

  const AnnouncementDisplay({
    super.key,
    required this.announcementText,
    this.location = '123 Test Ave, Test City, Test State',
    this.onAnimationComplete,
  });

  @override
  State<AnnouncementDisplay> createState() => _AnnouncementDisplayState();
}

class _AnnouncementDisplayState extends State<AnnouncementDisplay> {
  bool _showLocation = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Location notification at top
        AnimatedOpacity(
          opacity: _showLocation ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(AppTheme.hintOpacity),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(
                  widget.location,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Dust text animation
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DustTextAnimation(
            text: widget.announcementText,
            onComplete: () {
              setState(() {
                _showLocation = true;
              });
              widget.onAnimationComplete?.call();
            },
          ),
        ),
      ],
    );
  }
}
