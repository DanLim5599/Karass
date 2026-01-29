import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../providers/app_provider.dart';
import '../widgets/iridescent_orb_background.dart';
import '../widgets/karass_logo.dart';
import '../widgets/dust_text_animation.dart';
import '../services/api_service.dart';
import 'beacon_status_screen.dart';

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
      // No need to scan on HomeScreen - user is already unlocked
      // Scanning only happens on WaitingForBeaconScreen
      _fetchAndShowAnnouncement(provider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check announcement when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _recheckAnnouncementExpiry();
    }
  }

  void _recheckAnnouncementExpiry() {
    if (!mounted) return;
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
      final eventTime = _getAnnouncementExpiry(latest);

      // Only show if the event time is valid and in the future (or no expiry set)
      if (eventTime == null || eventTime.isAfter(DateTime.now())) {
        setState(() {
          _showDustAnimation = true;
          // Only show the message, not the date/time
          _dustAnimationText = latest.message;
          _currentAnnouncementExpiry = eventTime;
        });
        // Schedule timer to auto-hide when event time passes
        if (eventTime != null) {
          _scheduleExpiryTimer(eventTime);
        }
      } else {
        // Event time has passed - don't show
        setState(() {
          _showDustAnimation = false;
          _dustAnimationText = '';
          _currentAnnouncementExpiry = null;
        });
      }
    }
  }

  /// Get the expiry time from announcement
  DateTime? _getAnnouncementExpiry(Announcement announcement) {
    // Use expiresAt if available
    if (announcement.expiresAt != null) {
      return announcement.expiresAt;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();

    return Scaffold(
      body: IridescentOrbBackground(
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

              // Admin buttons
              if (appProvider.userData.isAdmin)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showAnnouncementDialog(context, appProvider),
                          icon: const Icon(Icons.campaign, size: 16),
                          label: const Text('ANNOUNCE'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showSetBeaconDialog(context, appProvider),
                          icon: const Icon(Icons.person_pin, size: 16),
                          label: const Text('SET BEACON'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.secondary,
                            side: const BorderSide(color: AppTheme.secondary, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
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

              // Bottom: Beacon Status button and member ID
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Beacon Status button
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const BeaconStatusScreen(),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: BorderSide(
                          color: AppTheme.textSecondary.withOpacity(0.3),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'Beacon Status →',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Member ID
                    Text(
                      'member #${appProvider.userId ?? '—'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withOpacity(0.6),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
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
        onSend: (message, expiresAt, imageUrl) async {
          final success = await appProvider.createAnnouncement(
            message: message,
            expiresAt: expiresAt,
            imageUrl: imageUrl,
          );
          if (success) {
            // Only show if event time is in the future (or no expiry)
            if (expiresAt == null || expiresAt.isAfter(DateTime.now())) {
              setState(() {
                _showDustAnimation = true;
                _dustAnimationText = message;
                _currentAnnouncementExpiry = expiresAt;
              });
              if (expiresAt != null) {
                _scheduleExpiryTimer(expiresAt);
              }
            }
          }
          return success;
        },
      ),
    );
  }

  void _showSetBeaconDialog(BuildContext context, AppProvider appProvider) {
    showDialog(
      context: context,
      builder: (context) => _SetBeaconDialog(),
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

/// Dialog for creating announcements with date/time pickers and optional image
class _AnnouncementDialog extends StatefulWidget {
  final Future<bool> Function(String message, DateTime? expiresAt, String? imageUrl) onSend;

  const _AnnouncementDialog({required this.onSend});

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _messageController = TextEditingController();
  final _imagePicker = ImagePicker();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isSending = false;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

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

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = image.name;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
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
            // Message field
            TextField(
              controller: _messageController,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: 'Enter your announcement message',
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

            // Image picker
            Text(
              'Image (optional)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_selectedImageBytes != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: _removeImage,
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              InkWell(
                onTap: _pickImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.textMuted, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, color: AppTheme.textSecondary, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Add Image',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // End Date picker
            Text(
              'End Date',
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

            // End Time picker
            Text(
              'End Time',
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

            // End Timezone display
            Text(
              'End Timezone',
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
                  if (_messageController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a message')),
                    );
                    return;
                  }

                  setState(() => _isSending = true);

                  // Calculate expiry datetime
                  final expiresAt = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    _selectedTime.hour,
                    _selectedTime.minute,
                  );

                  // Upload image if selected
                  String? imageUrl;
                  if (_selectedImageBytes != null) {
                    final apiService = ApiService();
                    imageUrl = await apiService.uploadImage(
                      _selectedImageBytes!,
                      'image/jpeg',
                    );
                  }

                  final success = await widget.onSend(
                    _messageController.text.trim(),
                    expiresAt,
                    imageUrl,
                  );

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

/// Dialog for setting the beacon user (admin only)
class _SetBeaconDialog extends StatefulWidget {
  const _SetBeaconDialog();

  @override
  State<_SetBeaconDialog> createState() => _SetBeaconDialogState();
}

class _SetBeaconDialogState extends State<_SetBeaconDialog> {
  final _userIdController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _isClearing = false;
  BeaconUser? _currentBeacon;

  @override
  void initState() {
    super.initState();
    _loadCurrentBeacon();
  }

  Future<void> _loadCurrentBeacon() async {
    final beacon = await _apiService.getCurrentBeacon();
    if (mounted) {
      setState(() => _currentBeacon = beacon);
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _setBeacon() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a user ID')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await _apiService.setBeaconUser(userId);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beacon user set successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to set beacon user')),
        );
      }
    }
  }

  Future<void> _clearBeacon() async {
    setState(() => _isClearing = true);

    final success = await _apiService.clearBeacon();

    if (mounted) {
      setState(() => _isClearing = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beacon cleared')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to clear beacon')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Set Beacon User',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current beacon info
          if (_currentBeacon != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Beacon',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${_currentBeacon!.username} (ID: ${_currentBeacon!.id})',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_off, color: AppTheme.textSecondary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'No beacon assigned',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // User ID input
          TextField(
            controller: _userIdController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'User ID',
              hintText: 'Enter user ID from database',
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
        ],
      ),
      actions: [
        // Clear beacon button
        if (_currentBeacon != null)
          TextButton(
            onPressed: _isLoading || _isClearing ? null : _clearBeacon,
            child: _isClearing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Clear', style: TextStyle(color: AppTheme.error)),
          ),
        TextButton(
          onPressed: _isLoading || _isClearing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: _isLoading || _isClearing ? null : _setBeacon,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Set Beacon'),
        ),
      ],
    );
  }
}
