import 'base_oauth_service.dart';

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

  /// Create from base OAuthResult
  factory TwitterAuthResult.fromOAuthResult(OAuthResult result) {
    return TwitterAuthResult(
      success: result.success,
      message: result.message,
      token: result.token,
      user: result.userData != null
          ? TwitterUserResponse.fromJson(result.userData!)
          : null,
      isNewUser: result.isNewUser,
    );
  }
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

/// Service to handle Twitter/X OAuth authentication using Firebase Cloud Functions
class TwitterAuthService extends BaseOAuthService {
  @override
  String get providerName => 'TWITTER';

  @override
  String get initFunctionName => 'twitterOAuthInit';

  @override
  String get callbackFunctionName => 'twitterOAuthCallback';

  @override
  bool get includeCodeVerifierInCallback => true;

  /// Initiates the Twitter OAuth flow
  /// Returns the authentication result with user data and Firebase custom token
  Future<TwitterAuthResult> authenticate() async {
    final result = await performOAuthFlow();
    return TwitterAuthResult.fromOAuthResult(result);
  }
}
