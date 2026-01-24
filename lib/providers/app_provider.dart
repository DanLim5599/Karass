import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/storage_service.dart';
import '../services/bluetooth_service.dart';
import '../services/haptic_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/twitter_auth_service.dart';

export '../services/api_service.dart' show Announcement;

class AuthResult {
  final bool success;
  final String message;

  AuthResult({required this.success, required this.message});
}

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final BluetoothService _bluetooth = BluetoothService();
  final HapticService _haptic = HapticService();
  final ApiService _api = ApiService();
  final NotificationService _notifications = NotificationService();
  final TwitterAuthService _twitterAuth = TwitterAuthService();

  AppStage _stage = AppStage.splash;
  UserData _userData = const UserData();
  BeaconData _beaconData = const BeaconData();
  bool _isBluetoothOn = false;
  bool _isInitialized = false;
  String? _userId;
  List<Announcement> _announcements = [];

  StreamSubscription<bool>? _bluetoothSubscription;
  StreamSubscription<bool>? _karassSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  AppStage get stage => _stage;
  UserData get userData => _userData;
  BeaconData get beaconData => _beaconData;
  bool get isBluetoothOn => _isBluetoothOn;
  bool get isInitialized => _isInitialized;
  List<Announcement> get announcements => _announcements;
  String? get userId => _userId;

  StorageService get storage => _storage;
  BluetoothService get bluetooth => _bluetooth;
  HapticService get haptic => _haptic;
  NotificationService get notifications => _notifications;

  Future<void> init() async {
    try {
      await _storage.init();
    } catch (e) {
      debugPrint('Storage init failed: $e');
    }

    try {
      await _haptic.init();
    } catch (e) {
      debugPrint('Haptic init failed: $e');
    }

    try {
      await _bluetooth.init();
    } catch (e) {
      debugPrint('Bluetooth init failed: $e');
    }

    // Load saved user data and userId
    _userData = _storage.userData;
    _userId = _storage.userId;

    // Check Bluetooth state (with error handling)
    try {
      _isBluetoothOn = await _bluetooth.isBluetoothOn();
    } catch (e) {
      debugPrint('Bluetooth state check failed: $e');
      _isBluetoothOn = false;
    }

    // Listen to Bluetooth state changes
    _bluetoothSubscription = _bluetooth.bluetoothStateStream.listen(
      (isOn) {
        _isBluetoothOn = isOn;
        _updateStage(); // _updateStage already calls notifyListeners()
      },
      onError: (e) => debugPrint('Bluetooth state stream error: $e'),
    );

    // Listen for Karass beacon detection (only matters after signup)
    _karassSubscription = _bluetooth.karassDetectedStream.listen(
      (detected) {
        if (detected && _stage == AppStage.waitingForBeacon) {
          _onBeaconDetected();
        }
      },
      onError: (e) => debugPrint('Karass detection stream error: $e'),
    );

    // Listen for FCM token refresh and update backend
    _tokenRefreshSubscription = _notifications.tokenRefreshStream.listen(
      (token) {
        _updateFcmTokenOnBackend(token);
      },
      onError: (e) => debugPrint('Token refresh stream error: $e'),
    );

    _isInitialized = true;
    notifyListeners();
  }

  /// Update FCM token on backend when it refreshes
  Future<void> _updateFcmTokenOnBackend(String token) async {
    if (_userId == null) return;
    try {
      // Use HTTP directly to update FCM token
      // This ensures the token is always up to date on the server
      await _api.updateFcmToken(_userId!, token);
    } catch (e) {
      debugPrint('Failed to update FCM token: $e');
    }
  }

  void _updateStage({bool fromSplash = false}) {
    // Only skip if we're in splash AND this isn't called from onSplashComplete
    if (_stage == AppStage.splash && !fromSplash) {
      return;
    }

    // New flow: splash -> signUp -> waitingForBeacon -> unlocked
    if (!_storage.hasCompletedSignUp) {
      _stage = AppStage.signUp;
    } else if (!_storage.isUnlocked) {
      _stage = AppStage.waitingForBeacon;
    } else {
      _stage = AppStage.unlocked;
    }
    notifyListeners();
  }

  /// Called after splash screen completes
  Future<void> onSplashComplete() async {
    await _haptic.lightImpact();
    _updateStage(fromSplash: true);
  }

  /// Called when Karass beacon is detected (after user has signed up)
  Future<void> _onBeaconDetected() async {
    await _haptic.successPattern();
    await _storage.setUnlocked(true);
    await _notifications.showBeaconDetectedNotification();

    _stage = AppStage.unlocked;
    notifyListeners();
  }

  /// For testing: manually trigger beacon detection (simulate finding another Karass user)
  Future<void> debugTriggerBeaconDetected() async {
    if (_stage == AppStage.waitingForBeacon) {
      await _onBeaconDetected();
    }
  }

  /// For testing: reset all state
  Future<void> debugReset() async {
    await _storage.clearAll();
    _userData = const UserData();
    _userId = null;
    _announcements = [];
    _stage = AppStage.splash;
    notifyListeners();
  }

  /// Create account with API
  Future<AuthResult> createAccount({
    required String email,
    required String username,
    required String password,
    String? twitterHandle,
  }) async {
    final response = await _api.register(
      email: email,
      username: username,
      password: password,
      twitterHandle: twitterHandle,
    );

    if (response.success && response.user != null) {
      _userId = response.user!.id;
      _userData = UserData(
        email: response.user!.email,
        username: response.user!.username,
        twitterHandle: response.user!.twitterHandle,
        isAdmin: response.user!.isAdmin,
      );
      await _storage.saveUserData(_userData);
      await _storage.setUserId(_userId);
      await _storage.setHasCompletedSignUp(true);

      await _haptic.mediumImpact();

      // After signup, go to waiting for beacon stage
      _stage = AppStage.waitingForBeacon;
      notifyListeners();
    }

    return AuthResult(success: response.success, message: response.message);
  }

  /// Login with API
  Future<AuthResult> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final response = await _api.login(
      emailOrUsername: emailOrUsername,
      password: password,
    );

    if (response.success && response.user != null) {
      _userId = response.user!.id;
      _userData = UserData(
        email: response.user!.email,
        username: response.user!.username,
        twitterHandle: response.user!.twitterHandle,
        isAdmin: response.user!.isAdmin,
      );
      await _storage.saveUserData(_userData);
      await _storage.setUserId(_userId);
      await _storage.setHasCompletedSignUp(true);

      await _haptic.mediumImpact();

      // After login, go to waiting for beacon stage
      _stage = AppStage.waitingForBeacon;
      notifyListeners();
    }

    return AuthResult(success: response.success, message: response.message);
  }

  /// Login with Twitter/X OAuth
  Future<AuthResult> loginWithTwitter() async {
    final result = await _twitterAuth.authenticate();

    if (result.success && result.user != null) {
      _userId = result.user!.id;
      _userData = UserData(
        email: result.user!.email,
        username: result.user!.username,
        twitterHandle: result.user!.twitterHandle,
        isAdmin: result.user!.isAdmin,
      );

      // Store the JWT token
      if (result.token != null) {
        await _api.setToken(result.token);
      }

      await _storage.saveUserData(_userData);
      await _storage.setUserId(_userId);
      await _storage.setHasCompletedSignUp(true);

      await _haptic.mediumImpact();

      // After Twitter login, go to waiting for beacon stage
      _stage = AppStage.waitingForBeacon;
      notifyListeners();
    }

    return AuthResult(success: result.success, message: result.message);
  }

  /// Logout - clears all stored data and tokens
  Future<void> logout() async {
    // Clear JWT token
    await _api.clearToken();

    // Clear local storage
    await _storage.clearAll();

    // Reset state
    _userData = const UserData();
    _userId = null;
    _announcements = [];

    // Go back to signup screen
    _stage = AppStage.signUp;

    await _haptic.lightImpact();
    notifyListeners();
  }

  /// Fetch announcements
  Future<void> fetchAnnouncements() async {
    _announcements = await _api.getAnnouncements();
    notifyListeners();
  }

  /// Create announcement (admin only)
  Future<bool> createAnnouncement({
    required String message,
    DateTime? startsAt,
    DateTime? expiresAt,
  }) async {
    if (!_userData.isAdmin) return false;

    final success = await _api.createAnnouncement(
      message: message,
      startsAt: startsAt,
      expiresAt: expiresAt,
    );

    if (success) {
      await _haptic.successPattern();
      await fetchAnnouncements();

      // Send push notification for the announcement
      // Note: In production, this would be sent via FCM from the backend
      // to all subscribed users. This local notification is for the admin.
      await _notifications.showAnnouncementNotification(
        title: 'New Announcement',
        message: message,
      );
    }

    return success;
  }

  /// Start scanning for beacons (called when entering waitingForBeacon stage)
  Future<void> startBeaconScanning() async {
    if (_isBluetoothOn) {
      await _bluetooth.startScanning();
    }
  }

  /// Stop scanning for beacons
  Future<void> stopBeaconScanning() async {
    await _bluetooth.stopScanning();
  }

  /// Toggle beaconing
  Future<void> toggleBeaconing() async {
    if (_beaconData.isBeaconing) {
      await _bluetooth.stopBeaconing();
      _beaconData = _beaconData.copyWith(isBeaconing: false);
    } else {
      await _bluetooth.startBeaconing();
      await _haptic.beaconActivated();
      _beaconData = _beaconData.copyWith(isBeaconing: true);
    }
    notifyListeners();
  }

  /// Fire a single beacon pulse (charge-up mechanic)
  Future<void> fireBeacon() async {
    await _bluetooth.startBeaconing();
    await _haptic.heavyImpact();

    // Beacon for 2 seconds then stop
    await Future.delayed(const Duration(seconds: 2));
    await _bluetooth.stopBeaconing();
  }

  /// Start beacon (for tap and hold) - legacy
  Future<void> startBeaconing() async {
    if (!_beaconData.isBeaconing) {
      await _bluetooth.startBeaconing();
      await _haptic.beaconActivated();
      _beaconData = _beaconData.copyWith(isBeaconing: true);
      notifyListeners();
    }
  }

  /// Stop beacon - legacy
  Future<void> stopBeaconing() async {
    if (_beaconData.isBeaconing) {
      await _bluetooth.stopBeaconing();
      _beaconData = _beaconData.copyWith(isBeaconing: false);
      notifyListeners();
    }
  }

  /// Start scanning for nearby Karass users
  Future<void> startScanning() async {
    if (!_beaconData.isScanning) {
      await _bluetooth.startScanning();
      _beaconData = _beaconData.copyWith(isScanning: true);
      notifyListeners();
    }
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    if (_beaconData.isScanning) {
      await _bluetooth.stopScanning();
      _beaconData = _beaconData.copyWith(isScanning: false);
      notifyListeners();
    }
  }

  @override
  @override
  void dispose() {
    _bluetoothSubscription?.cancel();
    _karassSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _bluetooth.dispose();
    super.dispose();
  }
}
