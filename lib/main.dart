import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

/// Whether Firebase was successfully initialized
bool firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with generated options
  // Check if already initialized to avoid crash on hot restart/app reopen
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    firebaseInitialized = true;

    // Initialize notification service (handles its own reinitialization)
    await NotificationService().init();

    // Subscribe to announcements topic
    await NotificationService().subscribeToTopic('announcements');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    debugPrint('Push notifications will be disabled.');
  }

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style - light theme with dark icons
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const KarassApp());
}
