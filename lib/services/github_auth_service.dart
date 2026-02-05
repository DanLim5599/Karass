import 'base_oauth_service.dart';

/// Result of GitHub authentication
class GitHubAuthResult {
  final bool success;
  final String message;
  final String? token;
  final GitHubUserResponse? user;
  final bool isNewUser;

  GitHubAuthResult({
    required this.success,
    required this.message,
    this.token,
    this.user,
    this.isNewUser = false,
  });

  /// Create from base OAuthResult
  factory GitHubAuthResult.fromOAuthResult(OAuthResult result) {
    return GitHubAuthResult(
      success: result.success,
      message: result.message,
      token: result.token,
      user: result.userData != null
          ? GitHubUserResponse.fromJson(result.userData!)
          : null,
      isNewUser: result.isNewUser,
    );
  }
}

/// GitHub user data returned from authentication
class GitHubUserResponse {
  final String id;
  final String? email;
  final String username;
  final String? githubHandle;
  final String? githubId;
  final bool isApproved;
  final bool isAdmin;

  GitHubUserResponse({
    required this.id,
    this.email,
    required this.username,
    this.githubHandle,
    this.githubId,
    required this.isApproved,
    required this.isAdmin,
  });

  factory GitHubUserResponse.fromJson(Map<String, dynamic> json) {
    return GitHubUserResponse(
      id: json['id'] ?? '',
      email: json['email'],
      username: json['username'] ?? '',
      githubHandle: json['githubHandle'],
      githubId: json['githubId'],
      isApproved: json['isApproved'] ?? false,
      isAdmin: json['isAdmin'] ?? false,
    );
  }
}

/// Service to handle GitHub OAuth authentication using Firebase Cloud Functions
class GitHubAuthService extends BaseOAuthService {
  @override
  String get providerName => 'GITHUB';

  @override
  String get initFunctionName => 'githubOAuthInit';

  @override
  String get callbackFunctionName => 'githubOAuthCallback';

  @override
  bool get includeCodeVerifierInCallback => false; // GitHub doesn't need codeVerifier

  /// Initiates the GitHub OAuth flow
  /// Returns the authentication result with user data and Firebase custom token
  Future<GitHubAuthResult> authenticate() async {
    final result = await performOAuthFlow();
    return GitHubAuthResult.fromOAuthResult(result);
  }
}
