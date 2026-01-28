import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

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
/// Provides common PKCE OAuth 2.0 flow implementation
abstract class BaseOAuthService {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String callbackScheme = 'karass';

  /// Provider name for logging (e.g., 'TWITTER', 'GITHUB')
  String get providerName;

  /// Init endpoint path (e.g., '/auth/twitter/init')
  String get initEndpoint;

  /// Callback endpoint path (e.g., '/auth/twitter/callback')
  String get callbackEndpoint;

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

  /// Main authentication flow
  /// Returns the authentication result with user data and JWT token
  Future<OAuthResult> performOAuthFlow() async {
    _log('STARTING OAUTH FLOW');

    String? authUrl;
    String? state;
    String? codeVerifier;

    try {
      // ============ STEP 1: Initialize OAuth ============
      _logStep(1, 'Initializing OAuth flow with backend...');

      http.Response initResponse;
      try {
        initResponse = await http.get(
          Uri.parse('$baseUrl$initEndpoint'),
        ).timeout(const Duration(seconds: 30));
        _log('Init request completed');
      } catch (e) {
        _logError('Init request FAILED: $e');
        return OAuthResult(
          success: false,
          message: 'Failed to connect to server: $e',
        );
      }

      _log('Init response status: ${initResponse.statusCode}');

      if (initResponse.statusCode != 200) {
        _logError('Init response was NOT 200!');
        try {
          final data = jsonDecode(initResponse.body);
          _logError('Error message from server: ${data['message']}');
          return OAuthResult(
            success: false,
            message: data['message'] ?? 'Failed to initialize auth (status ${initResponse.statusCode})',
          );
        } catch (e) {
          _logError('Could not parse error response: $e');
          return OAuthResult(
            success: false,
            message: 'Failed to initialize auth (status ${initResponse.statusCode})',
          );
        }
      }

      _logSuccess('Init response received successfully');

      Map<String, dynamic> initData;
      try {
        initData = jsonDecode(initResponse.body);
        _log('Parsed init data successfully');
      } catch (e) {
        _logError('Failed to parse init response JSON: $e');
        return OAuthResult(
          success: false,
          message: 'Invalid response from server',
        );
      }

      authUrl = initData['authUrl'] as String?;
      state = initData['state'] as String?;
      codeVerifier = initData['codeVerifier'] as String?;

      _log('Auth URL received');
      _log('State and code verifier received');

      if (authUrl == null || state == null || codeVerifier == null) {
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

      // ============ STEP 4: Exchange Code for Token ============
      _logStep(4, 'Exchanging code for token with backend...');

      final callbackBody = {
        'code': code,
        'state': state,
        'codeVerifier': codeVerifier,
      };

      http.Response callbackResponse;
      try {
        callbackResponse = await http.post(
          Uri.parse('$baseUrl$callbackEndpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(callbackBody),
        ).timeout(const Duration(seconds: 30));
        _log('Callback request completed');
      } catch (e) {
        _logError('Callback request FAILED: $e');
        return OAuthResult(
          success: false,
          message: 'Failed to complete authentication: $e',
        );
      }

      _log('Callback response status: ${callbackResponse.statusCode}');

      Map<String, dynamic> callbackData;
      try {
        callbackData = jsonDecode(callbackResponse.body);
        _log('Callback data parsed successfully');
      } catch (e) {
        _logError('Failed to parse callback response: $e');
        return OAuthResult(
          success: false,
          message: 'Invalid response from server during token exchange',
        );
      }

      if (callbackResponse.statusCode != 200 || callbackData['success'] != true) {
        _logError('Backend callback failed: ${callbackData['message']}');
        return OAuthResult(
          success: false,
          message: callbackData['message'] ?? 'Authentication failed on server',
        );
      }

      _logSuccess('Step 4 completed - Token exchange successful');

      // ============ STEP 5: Return Success ============
      _logStep(5, 'Building success response...');

      final token = callbackData['token'];
      final userData = callbackData['user'];
      final isNewUser = callbackData['isNewUser'] ?? false;

      _log('Token received: ${token != null}');
      _log('User data received: ${userData != null}');
      _log('Is new user: $isNewUser');

      _logSuccess('OAUTH FLOW COMPLETED SUCCESSFULLY!');
      _log('========================================');

      return OAuthResult(
        success: true,
        message: callbackData['message'] ?? 'Login successful',
        token: token,
        userData: userData,
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
