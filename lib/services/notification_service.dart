import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages silently in production
  debugPrint('Background message received');
}

/// Notification types for the app
enum NotificationType {
  beaconDetected,
  announcement,
  userApproved,
}

/// Represents a notification payload
class NotificationPayload {
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;

  NotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'body': body,
        if (data != null) 'data': data,
      };

  factory NotificationPayload.fromJson(Map<String, dynamic> json) {
    return NotificationPayload(
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.announcement,
      ),
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      data: json['data'],
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamController<NotificationPayload>? _notificationController;
  StreamController<String>? _tokenRefreshController;

  // Store Firebase listener subscriptions to prevent duplicates
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  Stream<NotificationPayload> get notificationStream {
    _ensureControllersOpen();
    return _notificationController!.stream;
  }

  /// Stream that emits when FCM token is refreshed
  Stream<String> get tokenRefreshStream {
    _ensureControllersOpen();
    return _tokenRefreshController!.stream;
  }

  /// Ensure stream controllers are open, recreate if closed
  void _ensureControllersOpen() {
    if (_notificationController == null || _notificationController!.isClosed) {
      _notificationController = StreamController<NotificationPayload>.broadcast();
    }
    if (_tokenRefreshController == null || _tokenRefreshController!.isClosed) {
      _tokenRefreshController = StreamController<String>.broadcast();
    }
  }

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> init() async {
    // Ensure controllers are open even if already initialized
    _ensureControllersOpen();

    if (_isInitialized) return;

    // Set up background message handler (safe to call multiple times)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permissions
    await _requestPermissions();

    // Initialize local notifications
    await _initLocalNotifications();

    // Get FCM token
    await _getFcmToken();

    // Cancel any existing subscriptions before creating new ones
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();

    // Listen for token refresh and notify listeners
    _tokenRefreshSubscription = _fcm.onTokenRefresh.listen((token) {
      _fcmToken = token;
      debugPrint('FCM Token refreshed');
      _ensureControllersOpen();
      _tokenRefreshController?.add(token);
    });

    // Handle foreground messages
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state via notification)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _isInitialized = true;
  }

  Future<void> _requestPermissions() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('Notification permission status: ${settings.authorizationStatus}');
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Beacon detection channel (no sound)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'beacon_channel',
          'Beacon Notifications',
          description: 'Notifications when a Karass beacon is detected nearby',
          importance: Importance.high,
          enableVibration: true,
          playSound: false,
        ),
      );

      // Announcements channel (no sound)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'announcement_channel',
          'Announcements',
          description: 'Community announcements from Karass admins',
          importance: Importance.high,
          enableVibration: true,
          playSound: false,
        ),
      );

      // General channel (no sound)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'general_channel',
          'General',
          description: 'General notifications from Karass',
          importance: Importance.defaultImportance,
          playSound: false,
        ),
      );
    }
  }

  Future<void> _getFcmToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      debugPrint('FCM Token obtained');
      // TODO: Send token to backend for push notification targeting
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Received foreground message');

    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      // Show local notification
      showLocalNotification(
        title: notification.title ?? 'Karass',
        body: notification.body ?? '',
        type: _parseNotificationType(data['type']),
        data: data,
      );
    }

    // Emit to stream
    _ensureControllersOpen();
    _notificationController?.add(NotificationPayload(
      type: _parseNotificationType(data['type']),
      title: notification?.title ?? data['title'] ?? '',
      body: notification?.body ?? data['body'] ?? '',
      data: data,
    ));
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped');

    final data = message.data;
    final notification = message.notification;

    _ensureControllersOpen();
    _notificationController?.add(NotificationPayload(
      type: _parseNotificationType(data['type']),
      title: notification?.title ?? data['title'] ?? '',
      body: notification?.body ?? data['body'] ?? '',
      data: data,
    ));
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _ensureControllersOpen();
        _notificationController?.add(NotificationPayload.fromJson(data));
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  NotificationType _parseNotificationType(String? type) {
    switch (type) {
      case 'beacon':
        return NotificationType.beaconDetected;
      case 'announcement':
        return NotificationType.announcement;
      case 'approved':
        return NotificationType.userApproved;
      default:
        return NotificationType.announcement;
    }
  }

  /// Show a local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.announcement,
    Map<String, dynamic>? data,
  }) async {
    final channelId = _getChannelId(type);

    // All notifications should be silent (no sound)
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final payload = NotificationPayload(
      type: type,
      title: title,
      body: body,
      data: data,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: jsonEncode(payload.toJson()),
    );
  }

  String _getChannelId(NotificationType type) {
    switch (type) {
      case NotificationType.beaconDetected:
        return 'beacon_channel';
      case NotificationType.announcement:
        return 'announcement_channel';
      case NotificationType.userApproved:
        return 'general_channel';
    }
  }

  String _getChannelName(NotificationType type) {
    switch (type) {
      case NotificationType.beaconDetected:
        return 'Beacon Notifications';
      case NotificationType.announcement:
        return 'Announcements';
      case NotificationType.userApproved:
        return 'General';
    }
  }

  String _getChannelDescription(NotificationType type) {
    switch (type) {
      case NotificationType.beaconDetected:
        return 'Notifications when a Karass beacon is detected nearby';
      case NotificationType.announcement:
        return 'Community announcements from Karass admins';
      case NotificationType.userApproved:
        return 'General notifications from Karass';
    }
  }

  /// Show beacon detected notification
  Future<void> showBeaconDetectedNotification() async {
    await showLocalNotification(
      title: 'Karass Member Nearby',
      body: 'A member of your Karass is in range. Tap to connect.',
      type: NotificationType.beaconDetected,
    );
  }

  /// Show announcement notification
  Future<void> showAnnouncementNotification({
    required String title,
    required String message,
    String? announcementId,
  }) async {
    await showLocalNotification(
      title: title,
      body: message,
      type: NotificationType.announcement,
      data: {'announcementId': announcementId},
    );
  }

  /// Subscribe to a topic (e.g., 'announcements', 'all_users')
  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
    debugPrint('Unsubscribed from topic: $topic');
  }

  Future<void> dispose() async {
    // Cancel Firebase subscriptions
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
    _messageOpenedSubscription = null;

    // Close stream controllers
    await _notificationController?.close();
    await _tokenRefreshController?.close();
    _notificationController = null;
    _tokenRefreshController = null;

    // Reset initialization flag so it can reinitialize if needed
    _isInitialized = false;
  }
}
