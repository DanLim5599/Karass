import 'dart:convert';
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

  /// Initiates the Twitter OAuth flow
  /// Returns the authentication result with user data and JWT token
  Future<TwitterAuthResult> authenticate() async {
    try {
      // Step 1: Initialize OAuth flow and get auth URL from backend
      final initResponse = await http.get(
        Uri.parse('$baseUrl/auth/twitter/init'),
      );

      if (initResponse.statusCode != 200) {
        final data = jsonDecode(initResponse.body);
        return TwitterAuthResult(
          success: false,
          message: data['message'] ?? 'Failed to initialize Twitter auth',
        );
      }

      final initData = jsonDecode(initResponse.body);
      final authUrl = initData['authUrl'] as String;
      final state = initData['state'] as String;
      final codeVerifier = initData['codeVerifier'] as String;

      // Step 2: Open Twitter auth page in secure webview
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: callbackScheme,
        options: const FlutterWebAuth2Options(
          preferEphemeral: true,
        ),
      );

      // Step 3: Parse the callback URL to get the authorization code
      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];
      final returnedState = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        return TwitterAuthResult(
          success: false,
          message: 'Twitter authorization denied: $error',
        );
      }

      if (code == null) {
        return TwitterAuthResult(
          success: false,
          message: 'No authorization code received',
        );
      }

      // Verify state matches (CSRF protection)
      if (returnedState != state) {
        return TwitterAuthResult(
          success: false,
          message: 'State mismatch - possible CSRF attack',
        );
      }

      // Step 4: Send code to backend to complete authentication
      final callbackResponse = await http.post(
        Uri.parse('$baseUrl/auth/twitter/callback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'state': state,
          'codeVerifier': codeVerifier,
        }),
      );

      final callbackData = jsonDecode(callbackResponse.body);

      if (callbackResponse.statusCode != 200 || callbackData['success'] != true) {
        return TwitterAuthResult(
          success: false,
          message: callbackData['message'] ?? 'Twitter authentication failed',
        );
      }

      // Step 5: Return success with user data and token
      return TwitterAuthResult(
        success: true,
        message: callbackData['message'] ?? 'Login successful',
        token: callbackData['token'],
        user: callbackData['user'] != null
            ? TwitterUserResponse.fromJson(callbackData['user'])
            : null,
        isNewUser: callbackData['isNewUser'] ?? false,
      );
    } on Exception catch (e) {
      // Handle user cancellation
      if (e.toString().contains('CANCELED') ||
          e.toString().contains('cancelled') ||
          e.toString().contains('user_cancelled')) {
        return TwitterAuthResult(
          success: false,
          message: 'Authentication cancelled',
        );
      }
      return TwitterAuthResult(
        success: false,
        message: 'Authentication error: $e',
      );
    }
  }
}
