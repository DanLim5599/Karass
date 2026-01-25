import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/animated_background.dart';
import '../widgets/karass_logo.dart';
import '../widgets/beacon_indicator.dart';
import '../widgets/dust_text_animation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _showDustAnimation = false;
  String _dustAnimationText = '';
  DateTime? _currentAnnouncementExpiry;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppProvider>();
      provider.startScanning();
      _fetchAndShowAnnouncement(provider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    // Stop scanning when leaving this screen
    context.read<AppProvider>().stopScanning();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<AppProvider>();

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Stop scanning when app goes to background to save battery
      provider.stopScanning();
    } else if (state == AppLifecycleState.resumed) {
      // Resume scanning when app comes back
      provider.startScanning();
      // Re-check announcement expiry
      _recheckAnnouncementExpiry();
    }
  }

  void _recheckAnnouncementExpiry() {
    if (_showDustAnimation && _currentAnnouncementExpiry != null) {
      if (_currentAnnouncementExpiry!.isBefore(DateTime.now())) {
        // Event time has passed, hide the announcement
        setState(() {
          _showDustAnimation = false;
          _dustAnimationText = '';
          _currentAnnouncementExpiry = null;
        });
        _expiryTimer?.cancel();
      }
    }
  }

  void _scheduleExpiryTimer(DateTime expiryTime) {
    _expiryTimer?.cancel();
    final duration = expiryTime.difference(DateTime.now());
    if (duration.isNegative) return;

    _expiryTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _showDustAnimation = false;
          _dustAnimationText = '';
          _currentAnnouncementExpiry = null;
        });
      }
    });
  }

  Future<void> _fetchAndShowAnnouncement(AppProvider provider) async {
    await provider.fetchAnnouncements();

    if (!mounted) return;

    final announcements = provider.announcements;

    if (announcements.isNotEmpty) {
      final latest = announcements.first;
      final eventTime = _parseEventTime(latest.message);

      // Only show if the event time is valid and in the future
      if (eventTime != null && eventTime.isAfter(DateTime.now())) {
        setState(() {
          _showDustAnimation = true;
          _dustAnimationText = latest.message;
          _currentAnnouncementExpiry = eventTime;
        });
        // Schedule timer to auto-hide when event time passes
        _scheduleExpiryTimer(eventTime);
      } else {
        // Event time has passed or couldn't be parsed - don't show
        setState(() {
          _showDustAnimation = false;
          _dustAnimationText = '';
          _currentAnnouncementExpiry = null;
        });
      }
    }
  }

  /// Try to parse event time from announcement message
  /// Expected format: "Address @ Time" or "Address | Time" or just contains a date/time
  DateTime? _parseEventTime(String message) {
    // Try to find time after @ or |
    final patterns = ['@', '|', ' - '];

    for (final pattern in patterns) {
      if (message.contains(pattern)) {
        final parts = message.split(pattern);
        if (parts.length >= 2) {
          final timePart = parts.last.trim();
          final parsed = _tryParseDateTime(timePart);
          if (parsed != null) return parsed;
        }
      }
    }

    // Try to parse the whole message as containing a date
    return _tryParseDateTime(message);
  }

  DateTime? _tryParseDateTime(String text) {
    // Common time patterns to try
    final now = DateTime.now();

    // Try standard DateTime parse
    try {
      return DateTime.parse(text);
    } catch (_) {}

    // Try parsing common formats like "3:00 PM Jan 22" or "Jan 22, 2026 3:00 PM"
    // Simple regex for time like "3:00 PM" or "15:00"
    final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?', caseSensitive: false);
    final timeMatch = timeRegex.firstMatch(text);

    // Simple regex for date like "Jan 22" or "January 22, 2026"
    final monthNames = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final dateRegex = RegExp(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*(\d{1,2})(?:,?\s*(\d{4}))?', caseSensitive: false);
    final dateMatch = dateRegex.firstMatch(text);

    if (timeMatch != null) {
      int hour = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2)!);
      final ampm = timeMatch.group(3)?.toLowerCase();

      if (ampm == 'pm' && hour != 12) hour += 12;
      if (ampm == 'am' && hour == 12) hour = 0;

      int year = now.year;
      int month = now.month;
      int day = now.day;

      if (dateMatch != null) {
        final monthStr = dateMatch.group(1)!.toLowerCase().substring(0, 3);
        month = monthNames.indexOf(monthStr) + 1;
        day = int.parse(dateMatch.group(2)!);
        if (dateMatch.group(3) != null) {
          year = int.parse(dateMatch.group(3)!);
        }
      }

      return DateTime(year, month, day, hour, minute);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top: Logo
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const KarassLogo(size: 40),
                    const SizedBox(width: 12),
                    const KarassLogoText(fontSize: 18),
                    const Spacer(),
                    // Settings/menu button
                    IconButton(
                      onPressed: () => _showSettingsSheet(context, appProvider),
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Admin: Send Announcement button
              if (appProvider.userData.isAdmin)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: OutlinedButton.icon(
                    onPressed: () => _showAnnouncementDialog(context, appProvider),
                    icon: const Icon(Icons.campaign, size: 18),
                    label: const Text('SEND ANNOUNCEMENT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

              // Middle: Announcement text (if any)
              Expanded(
                child: _showDustAnimation
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: DustTextAnimation(
                            key: ValueKey(_dustAnimationText),
                            text: _dustAnimationText,
                            onComplete: () {
                              // Animation complete - text stays visible
                            },
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),

              // Bottom: Beacon indicator
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: BeaconIndicator(
                  onBeaconFired: () => appProvider.fireBeacon(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnnouncementDialog(BuildContext context, AppProvider appProvider) {
    showDialog(
      context: context,
      builder: (context) => _AnnouncementDialog(
        onSend: (message) async {
          final success = await appProvider.createAnnouncement(message: message);
          if (success) {
            final eventTime = _parseEventTime(message);
            // Only show if event time is valid and in the future
            if (eventTime != null && eventTime.isAfter(DateTime.now())) {
              setState(() {
                _showDustAnimation = true;
                _dustAnimationText = message;
                _currentAnnouncementExpiry = eventTime;
              });
              _scheduleExpiryTimer(eventTime);
            }
          }
          return success;
        },
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, AppProvider appProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withOpacity(AppTheme.disabledOpacity),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.person_outline, color: AppTheme.textPrimary),
                  title: Text(
                    appProvider.userData.username ?? 'User',
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    appProvider.userData.email ?? '',
                    style: TextStyle(color: AppTheme.textSecondary.withOpacity(AppTheme.mediumOpacity)),
                  ),
                ),
                const Divider(color: AppTheme.textSecondary),
                ListTile(
                  leading: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                  title: const Text(
                    'Reset App (Debug)',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await appProvider.debugReset();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dialog for creating announcements with date/time pickers
class _AnnouncementDialog extends StatefulWidget {
  final Future<bool> Function(String message) onSend;

  const _AnnouncementDialog({required this.onSend});

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _addressController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isSending = false;

  String get _timezone {
    final offset = DateTime.now().timeZoneOffset;
    final hours = offset.inHours.abs();
    final minutes = (offset.inMinutes.abs() % 60);
    final sign = offset.isNegative ? '-' : '+';
    final name = DateTime.now().timeZoneName;
    return '$name (UTC$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')})';
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Send Announcement',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address field
            TextField(
              controller: _addressController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: '123 Main St, City',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.textMuted),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 20),

            // Date picker
            Text(
              'Date',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.textMuted),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _formatDate(_selectedDate),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time picker
            Text(
              'Time',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.textMuted),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, color: AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _formatTime(_selectedTime),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Timezone display
            Text(
              'Timezone',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.textMuted.withOpacity(AppTheme.mutedOpacity)),
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.surface.withOpacity(AppTheme.disabledOpacity),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, color: AppTheme.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _timezone,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: _isSending
              ? null
              : () async {
                  if (_addressController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter an address')),
                    );
                    return;
                  }

                  setState(() => _isSending = true);

                  // Format: "Address @ Jan 22, 2026 3:00 PM"
                  final dateTimeStr = '${_formatDate(_selectedDate)} ${_formatTime(_selectedTime)}';
                  final message = '${_addressController.text.trim()} @ $dateTimeStr';

                  final success = await widget.onSend(message);

                  if (context.mounted) {
                    Navigator.pop(context);
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to send announcement')),
                      );
                    }
                  }
                },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
