import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

/// Result of Twitter authentication
class TwitterAuthResult {
  final bool success;
  final String message;
  final String? token;
  final TwitterUserResponse? user;
  final bool isNewUser;

  TwitterAuthResult({
    required this.success,
    required this.message,
    this.token,
    this.user,
    this.isNewUser = false,
  });
}

/// Twitter user data returned from authentication
class TwitterUserResponse {
  final String id;
  final String? email;
  final String username;
  final String? twitterHandle;
  final String? twitterId;
  final bool isApproved;
  final bool isAdmin;

  TwitterUserResponse({
    required this.id,
    this.email,
    required this.username,
    this.twitterHandle,
    this.twitterId,
    required this.isApproved,
    required this.isAdmin,
  });

  factory TwitterUserResponse.fromJson(Map<String, dynamic> json) {
    return TwitterUserResponse(
      id: json['id'] ?? '',
      email: json['email'],
      username: json['username'] ?? '',
      twitterHandle: json['twitterHandle'],
      twitterId: json['twitterId'],
      isApproved: json['isApproved'] ?? false,
      isAdmin: json['isAdmin'] ?? false,
    );
  }
}

/// Service to handle Twitter/X OAuth authentication
class TwitterAuthService {
  static const String baseUrl = ApiConfig.baseUrl;
  static const String callbackScheme = 'karass';

  // Only log in debug mode to prevent sensitive data exposure
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[TWITTER AUTH] $message');
    }
  }

  static void _logError(String message) {
    if (kDebugMode) {
      debugPrint('[TWITTER AUTH ERROR] $message');
    }
  }

  static void _logSuccess(String message) {
    if (kDebugMode) {
      debugPrint('[TWITTER AUTH SUCCESS] $message');
    }
  }

  static void _logStep(int step, String message) {
    if (kDebugMode) {
      debugPrint('[TWITTER AUTH STEP $step] $message');
    }
  }

  /// Initiates the Twitter OAuth flow
  /// Returns the authentication result with user data and JWT token
  Future<TwitterAuthResult> authenticate() async {
    _log('STARTING TWITTER OAUTH FLOW');

    String? authUrl;
    String? state;
    String? codeVerifier;

    try {
      // ============ STEP 1: Initialize OAuth ============
      _logStep(1, 'Initializing OAuth flow with backend...');

      http.Response initResponse;
      try {
        initResponse = await http.get(
          Uri.parse('$baseUrl/auth/twitter/init'),
        ).timeout(const Duration(seconds: 30));
        _log('Init request completed');
      } catch (e) {
        _logError('Init request FAILED: $e');
        return TwitterAuthResult(
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
          return TwitterAuthResult(
            success: false,
            message: data['message'] ?? 'Failed to initialize Twitter auth (status ${initResponse.statusCode})',
          );
        } catch (e) {
          _logError('Could not parse error response: $e');
          return TwitterAuthResult(
            success: false,
            message: 'Failed to initialize Twitter auth (status ${initResponse.statusCode})',
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
        return TwitterAuthResult(
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
        _logError('authUrl is null: ${authUrl == null}');
        _logError('state is null: ${state == null}');
        _logError('codeVerifier is null: ${codeVerifier == null}');
        return TwitterAuthResult(
          success: false,
          message: 'Invalid OAuth initialization response',
        );
      }

      _logSuccess('Step 1 completed - OAuth initialized');

      // ============ STEP 2: Open Twitter Auth ============
      _logStep(2, 'Opening Twitter authorization page...');
      _log('Using FlutterWebAuth2.authenticate()');
      _log('URL: $authUrl');
      _log('Callback URL Scheme: $callbackScheme');
      _log('Options: preferEphemeral=false');

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
        _logSuccess('Received callback from Twitter!');
        _log('Callback result: $result');
      } on PlatformException catch (e) {
        _logError('PlatformException during web auth!');
        _logError('Code: ${e.code}');
        _logError('Message: ${e.message}');
        _logError('Details: ${e.details}');
        _logError('StackTrace: ${e.stacktrace}');

        if (e.code == 'CANCELED') {
          return TwitterAuthResult(
            success: false,
            message: 'Login was cancelled. Please try again. (PlatformException: ${e.code} - ${e.message})',
          );
        }
        return TwitterAuthResult(
          success: false,
          message: 'Platform error during login: ${e.code} - ${e.message}',
        );
      } catch (e) {
        _logError('Unknown exception during web auth!');
        _logError('Exception: $e');
        _logError('Type: ${e.runtimeType}');
        return TwitterAuthResult(
          success: false,
          message: 'Error during Twitter login: $e',
        );
      }

      _logSuccess('Step 2 completed - Twitter auth page returned');

      // ============ STEP 3: Parse Callback URL ============
      _logStep(3, 'Parsing callback URL...');

      Uri uri;
      try {
        uri = Uri.parse(result);
        _log('Callback URL parsed successfully');
      } catch (e) {
        _logError('Failed to parse callback URL: $e');
        return TwitterAuthResult(
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
        _log('Error: $error - $errorDescription');
      }

      if (error != null) {
        _logError('Twitter returned an error!');
        _logError('Error: $error');
        _logError('Description: $errorDescription');
        return TwitterAuthResult(
          success: false,
          message: 'Twitter authorization denied: $error - $errorDescription',
        );
      }

      if (code == null) {
        _logError('No authorization code in callback!');
        _logError('Full query parameters: ${uri.queryParameters}');
        return TwitterAuthResult(
          success: false,
          message: 'No authorization code received from Twitter',
        );
      }

      _log('Checking state match...');

      if (returnedState != state) {
        _logError('STATE MISMATCH! Possible CSRF attack!');
        return TwitterAuthResult(
          success: false,
          message: 'Security error: State mismatch',
        );
      }

      _logSuccess('Step 3 completed - Callback parsed successfully');
      _logSuccess('Authorization code received');

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
          Uri.parse('$baseUrl/auth/twitter/callback'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(callbackBody),
        ).timeout(const Duration(seconds: 30));
        _log('Callback request completed');
      } catch (e) {
        _logError('Callback request FAILED: $e');
        return TwitterAuthResult(
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
        return TwitterAuthResult(
          success: false,
          message: 'Invalid response from server during token exchange',
        );
      }

      if (callbackResponse.statusCode != 200 || callbackData['success'] != true) {
        _logError('Backend callback failed: ${callbackData['message']}');
        return TwitterAuthResult(
          success: false,
          message: callbackData['message'] ?? 'Twitter authentication failed on server',
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

      if (userData != null) {
        _log('Username: ${userData['username']}');
      }

      _logSuccess('TWITTER OAUTH FLOW COMPLETED SUCCESSFULLY!');
      _log('========================================');

      return TwitterAuthResult(
        success: true,
        message: callbackData['message'] ?? 'Login successful',
        token: token,
        user: userData != null ? TwitterUserResponse.fromJson(userData) : null,
        isNewUser: isNewUser,
      );

    } catch (e, stackTrace) {
      _logError('UNEXPECTED ERROR IN TWITTER AUTH!');
      _logError('Exception: $e');
      if (kDebugMode) {
        _logError('Stack trace: $stackTrace');
      }

      return TwitterAuthResult(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }
}
