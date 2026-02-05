import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Base result for OAuth authentication
class OAuthResult {
  final bool success;
  final String message;
  final String? token;
  final Map<String, dynamic>? userData;
  final bool isNewUser;

  OAuthResult({
    required this.success,
    required this.message,
    this.token,
    this.userData,
    this.isNewUser = false,
  });
}

/// Abstract base class for OAuth services
/// Provides common PKCE OAuth 2.0 flow implementation using Firebase Cloud Functions
abstract class BaseOAuthService {
  static const String callbackScheme = 'karass';

  // Firebase instances
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Provider name for logging (e.g., 'TWITTER', 'GITHUB')
  String get providerName;

  /// Init function name (e.g., 'twitterOAuthInit')
  String get initFunctionName;

  /// Callback function name (e.g., 'twitterOAuthCallback')
  String get callbackFunctionName;

  /// Whether to include codeVerifier in callback (Twitter requires it, GitHub doesn't)
  bool get includeCodeVerifierInCallback => true;

  // Logging helpers - only log in debug mode
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[$providerName AUTH] $message');
    }
  }

  void _logError(String message) {
    if (kDebugMode) {
      debugPrint('[$providerName AUTH ERROR] $message');
    }
  }

  void _logSuccess(String message) {
    if (kDebugMode) {
      debugPrint('[$providerName AUTH SUCCESS] $message');
    }
  }

  void _logStep(int step, String message) {
    if (kDebugMode) {
      debugPrint('[$providerName AUTH STEP $step] $message');
    }
  }

  /// Call a Cloud Function
  Future<Map<String, dynamic>> _callFunction(
    String name,
    Map<String, dynamic>? data,
  ) async {
    try {
      final callable = _functions.httpsCallable(name);
      final result = await callable.call(data);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      _logError('Function $name error: ${e.code} - ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Function call failed',
      };
    } catch (e) {
      _logError('Function $name exception: $e');
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  /// Main authentication flow
  /// Returns the authentication result with user data and Firebase custom token
  Future<OAuthResult> performOAuthFlow() async {
    _log('STARTING OAUTH FLOW');

    String? authUrl;
    String? state;
    String? codeVerifier;

    try {
      // ============ STEP 1: Initialize OAuth via Cloud Function ============
      _logStep(1, 'Initializing OAuth flow with Firebase...');

      Map<String, dynamic> initData;
      try {
        initData = await _callFunction(initFunctionName, {});
        _log('Init function completed');
      } catch (e) {
        _logError('Init function FAILED: $e');
        return OAuthResult(
          success: false,
          message: 'Failed to connect to server: $e',
        );
      }

      if (initData['success'] != true) {
        _logError('Init function returned error: ${initData['message']}');
        return OAuthResult(
          success: false,
          message: initData['message'] ?? 'Failed to initialize auth',
        );
      }

      _logSuccess('Init response received successfully');

      authUrl = initData['authUrl'] as String?;
      state = initData['state'] as String?;
      codeVerifier = initData['codeVerifier'] as String?;

      _log('Auth URL received');
      _log('State and code verifier received');

      if (authUrl == null || state == null) {
        _logError('Missing required fields in init response!');
        return OAuthResult(
          success: false,
          message: 'Invalid OAuth initialization response',
        );
      }

      _logSuccess('Step 1 completed - OAuth initialized');

      // ============ STEP 2: Open Auth Page ============
      _logStep(2, 'Opening authorization page...');
      _log('Using FlutterWebAuth2.authenticate()');
      _log('Callback URL Scheme: $callbackScheme');

      String result;
      try {
        _log('>>> Calling FlutterWebAuth2.authenticate() NOW <<<');
        result = await FlutterWebAuth2.authenticate(
          url: authUrl,
          callbackUrlScheme: callbackScheme,
          options: const FlutterWebAuth2Options(
            preferEphemeral: false,
          ),
        );
        _log('>>> FlutterWebAuth2.authenticate() RETURNED <<<');
        _logSuccess('Received callback!');
        _log('Callback result: $result');
      } on PlatformException catch (e) {
        _logError('PlatformException during web auth!');
        _logError('Code: ${e.code}');
        _logError('Message: ${e.message}');

        if (e.code == 'CANCELED') {
          return OAuthResult(
            success: false,
            message: 'Login was cancelled. Please try again.',
          );
        }
        return OAuthResult(
          success: false,
          message: 'Platform error during login: ${e.code} - ${e.message}',
        );
      } catch (e) {
        _logError('Unknown exception during web auth!');
        _logError('Exception: $e');
        return OAuthResult(
          success: false,
          message: 'Error during login: $e',
        );
      }

      _logSuccess('Step 2 completed - Auth page returned');

      // ============ STEP 3: Parse Callback URL ============
      _logStep(3, 'Parsing callback URL...');

      Uri uri;
      try {
        uri = Uri.parse(result);
        _log('Callback URL parsed successfully');
      } catch (e) {
        _logError('Failed to parse callback URL: $e');
        return OAuthResult(
          success: false,
          message: 'Invalid callback URL received',
        );
      }

      final code = uri.queryParameters['code'];
      final returnedState = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];

      _log('Code received: ${code != null}');
      _log('State received: ${returnedState != null}');

      if (error != null) {
        _logError('Provider returned an error!');
        _logError('Error: $error');
        _logError('Description: $errorDescription');
        return OAuthResult(
          success: false,
          message: 'Authorization denied: $error - $errorDescription',
        );
      }

      if (code == null) {
        _logError('No authorization code in callback!');
        return OAuthResult(
          success: false,
          message: 'No authorization code received',
        );
      }

      _log('Checking state match...');

      if (returnedState != state) {
        _logError('STATE MISMATCH! Possible CSRF attack!');
        return OAuthResult(
          success: false,
          message: 'Security error: State mismatch',
        );
      }

      _logSuccess('Step 3 completed - Callback parsed successfully');

      // ============ STEP 4: Exchange Code for Token via Cloud Function ============
      _logStep(4, 'Exchanging code for token with Firebase...');

      final callbackData = <String, dynamic>{
        'code': code,
        'state': state,
      };

      // Include codeVerifier if required (Twitter needs it, GitHub doesn't)
      if (includeCodeVerifierInCallback && codeVerifier != null) {
        callbackData['codeVerifier'] = codeVerifier;
      }

      Map<String, dynamic> callbackResult;
      try {
        callbackResult = await _callFunction(callbackFunctionName, callbackData);
        _log('Callback function completed');
      } catch (e) {
        _logError('Callback function FAILED: $e');
        return OAuthResult(
          success: false,
          message: 'Failed to complete authentication: $e',
        );
      }

      if (callbackResult['success'] != true) {
        _logError('Backend callback failed: ${callbackResult['message']}');
        return OAuthResult(
          success: false,
          message: callbackResult['message'] ?? 'Authentication failed on server',
        );
      }

      _logSuccess('Step 4 completed - Token exchange successful');

      // ============ STEP 5: Sign in with Firebase Custom Token ============
      _logStep(5, 'Signing in with Firebase...');

      final token = callbackResult['token'] as String?;
      final userData = callbackResult['user'] as Map<dynamic, dynamic>?;
      final isNewUser = callbackResult['isNewUser'] ?? false;

      _log('Token received: ${token != null}');
      _log('User data received: ${userData != null}');
      _log('Is new user: $isNewUser');

      if (token != null) {
        try {
          await _auth.signInWithCustomToken(token);
          _logSuccess('Signed in with Firebase successfully');
        } catch (e) {
          _logError('Failed to sign in with Firebase: $e');
          return OAuthResult(
            success: false,
            message: 'Failed to complete sign in: $e',
          );
        }
      }

      _logSuccess('OAUTH FLOW COMPLETED SUCCESSFULLY!');
      _log('========================================');

      return OAuthResult(
        success: true,
        message: callbackResult['message'] ?? 'Login successful',
        token: token,
        userData: userData != null ? Map<String, dynamic>.from(userData) : null,
        isNewUser: isNewUser,
      );

    } catch (e, stackTrace) {
      _logError('UNEXPECTED ERROR IN OAUTH!');
      _logError('Exception: $e');
      if (kDebugMode) {
        _logError('Stack trace: $stackTrace');
      }

      return OAuthResult(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }
}
