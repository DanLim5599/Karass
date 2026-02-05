import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Firebase-based API service using Cloud Functions
class ApiService {
  // Firebase instances
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Get the current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Get the current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Check if user is authenticated
  bool get isAuthenticated => _auth.currentUser != null;

  /// Sign out the current user
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Listen to auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
      debugPrint('Function $name error: ${e.code} - ${e.message}');
      return {
        'success': false,
        'message': e.message ?? 'Function call failed',
      };
    } catch (e) {
      debugPrint('Function $name exception: $e');
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================
  // Authentication
  // ============================================

  Future<ApiResponse> register({
    required String email,
    required String username,
    required String password,
    String? twitterHandle,
  }) async {
    try {
      final result = await _callFunction('register', {
        'email': email,
        'username': username,
        'password': password,
        'twitterHandle': twitterHandle,
      });

      if (result['success'] == true && result['token'] != null) {
        // Sign in with custom token
        await _auth.signInWithCustomToken(result['token']);
      }

      return ApiResponse(
        success: result['success'] ?? false,
        message: result['message'] ?? 'Unknown error',
        token: result['token'],
        user: result['user'] != null
            ? UserResponse.fromJson(Map<String, dynamic>.from(result['user']))
            : null,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Registration error: $e',
      );
    }
  }

  Future<ApiResponse> login({
    required String emailOrUsername,
    required String password,
  }) async {
    try {
      final result = await _callFunction('login', {
        'emailOrUsername': emailOrUsername,
        'password': password,
      });

      if (result['success'] == true && result['token'] != null) {
        // Sign in with custom token
        await _auth.signInWithCustomToken(result['token']);
      }

      return ApiResponse(
        success: result['success'] ?? false,
        message: result['message'] ?? 'Unknown error',
        token: result['token'],
        user: result['user'] != null
            ? UserResponse.fromJson(Map<String, dynamic>.from(result['user']))
            : null,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Login error: $e',
      );
    }
  }

  Future<bool> checkApprovalStatus(String userId) async {
    try {
      final result = await _callFunction('getUserStatus', {
        'userId': userId,
      });
      return result['isApproved'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // Twitter OAuth
  // ============================================

  Future<OAuthInitResult?> initTwitterOAuth() async {
    try {
      final result = await _callFunction('twitterOAuthInit', {});

      if (result['success'] == true) {
        return OAuthInitResult(
          authUrl: result['authUrl'],
          state: result['state'],
          codeVerifier: result['codeVerifier'],
        );
      }
      return null;
    } catch (e) {
      debugPrint('Twitter OAuth init error: $e');
      return null;
    }
  }

  Future<ApiResponse> twitterOAuthCallback({
    required String code,
    required String state,
    required String codeVerifier,
  }) async {
    try {
      final result = await _callFunction('twitterOAuthCallback', {
        'code': code,
        'state': state,
        'codeVerifier': codeVerifier,
      });

      if (result['success'] == true && result['token'] != null) {
        // Sign in with custom token
        await _auth.signInWithCustomToken(result['token']);
      }

      return ApiResponse(
        success: result['success'] ?? false,
        message: result['message'] ?? 'Unknown error',
        token: result['token'],
        user: result['user'] != null
            ? UserResponse.fromJson(Map<String, dynamic>.from(result['user']))
            : null,
        isNewUser: result['isNewUser'] ?? false,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Twitter callback error: $e',
      );
    }
  }

  // ============================================
  // GitHub OAuth
  // ============================================

  Future<OAuthInitResult?> initGitHubOAuth() async {
    try {
      final result = await _callFunction('githubOAuthInit', {});

      if (result['success'] == true) {
        return OAuthInitResult(
          authUrl: result['authUrl'],
          state: result['state'],
          codeVerifier: result['codeVerifier'],
        );
      }
      return null;
    } catch (e) {
      debugPrint('GitHub OAuth init error: $e');
      return null;
    }
  }

  Future<ApiResponse> githubOAuthCallback({
    required String code,
    required String state,
  }) async {
    try {
      final result = await _callFunction('githubOAuthCallback', {
        'code': code,
        'state': state,
      });

      if (result['success'] == true && result['token'] != null) {
        // Sign in with custom token
        await _auth.signInWithCustomToken(result['token']);
      }

      return ApiResponse(
        success: result['success'] ?? false,
        message: result['message'] ?? 'Unknown error',
        token: result['token'],
        user: result['user'] != null
            ? UserResponse.fromJson(Map<String, dynamic>.from(result['user']))
            : null,
        isNewUser: result['isNewUser'] ?? false,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'GitHub callback error: $e',
      );
    }
  }

  // ============================================
  // Admin Functions
  // ============================================

  Future<bool> approveUser(String userId) async {
    try {
      final result = await _callFunction('approveUser', {
        'userId': userId,
      });
      return result['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setUserAsAdmin(String userId) async {
    try {
      final result = await _callFunction('setUserAsAdmin', {
        'userId': userId,
        'isAdmin': true,
      });
      return result['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // Announcements
  // ============================================

  Future<List<Announcement>> getAnnouncements({int limit = 20}) async {
    try {
      final result = await _callFunction('getAnnouncements', {});

      if (result['success'] == true && result['announcements'] != null) {
        final List<dynamic> announcementsList = result['announcements'];
        return announcementsList
            .map((a) => Announcement.fromJson(Map<String, dynamic>.from(a)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get announcements error: $e');
      return [];
    }
  }

  Future<bool> createAnnouncement({
    required String message,
    String? title,
    DateTime? startsAt,
    DateTime? expiresAt,
    String? imageUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'message': message,
      };

      if (title != null) data['title'] = title;
      if (startsAt != null) data['startsAt'] = startsAt.toIso8601String();
      if (expiresAt != null) data['expiresAt'] = expiresAt.toIso8601String();
      if (imageUrl != null) data['imageUrl'] = imageUrl;

      final result = await _callFunction('createAnnouncement', data);
      return result['success'] ?? false;
    } catch (e) {
      debugPrint('Create announcement error: $e');
      return false;
    }
  }

  // ============================================
  // Beacon Management
  // ============================================

  Future<bool> getBeaconStatus() async {
    try {
      final result = await _callFunction('amITheBeacon', {});
      return result['isBeacon'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<BeaconUser?> getCurrentBeacon() async {
    try {
      final result = await _callFunction('getBeaconStatus', {});

      if (result['success'] == true && result['hasBeacon'] == true) {
        final beacon = result['beacon'];
        if (beacon != null) {
          return BeaconUser(
            id: beacon['userId'] ?? '',
            username: beacon['username'] ?? '',
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Get current beacon error: $e');
      return null;
    }
  }

  Future<bool> setBeaconUser(String userId) async {
    try {
      final result = await _callFunction('setBeacon', {
        'userId': userId,
      });
      return result['success'] ?? false;
    } catch (e) {
      debugPrint('Set beacon error: $e');
      return false;
    }
  }

  Future<bool> clearBeacon() async {
    try {
      final result = await _callFunction('clearBeacon', {});
      return result['success'] ?? false;
    } catch (e) {
      debugPrint('Clear beacon error: $e');
      return false;
    }
  }

  // ============================================
  // FCM Token
  // ============================================

  Future<bool> updateFcmToken(String userId, String fcmToken) async {
    try {
      final result = await _callFunction('updateFcmToken', {
        'fcmToken': fcmToken,
      });
      return result['success'] ?? false;
    } catch (e) {
      debugPrint('Update FCM token error: $e');
      return false;
    }
  }

  // ============================================
  // Image Upload
  // ============================================

  Future<String?> uploadImage(List<int> imageBytes, String contentType) async {
    try {
      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = currentUserId ?? 'anonymous';
      final extension = contentType.split('/').last;
      final filename = 'announcements/$userId/$timestamp.$extension';

      // Upload to Firebase Storage
      final ref = _storage.ref().child(filename);
      final metadata = SettableMetadata(contentType: contentType);

      await ref.putData(Uint8List.fromList(imageBytes), metadata);

      // Get download URL
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Upload image error: $e');
      return null;
    }
  }

  // ============================================
  // Health Check (not needed with Firebase, but kept for compatibility)
  // ============================================

  Future<bool> healthCheck() async {
    // Firebase is always "healthy" if we can reach it
    return _auth.currentUser != null || true;
  }

  // ============================================
  // Legacy Token Methods (deprecated, use Firebase Auth)
  // ============================================

  @Deprecated('Use Firebase Auth instead')
  Future<String?> getToken() async => null;

  @Deprecated('Use Firebase Auth instead')
  Future<void> setToken(String? token) async {}

  @Deprecated('Use signOut() instead')
  Future<void> clearToken() async {
    await signOut();
  }
}

// ============================================
// Response Models
// ============================================

class ApiResponse {
  final bool success;
  final String message;
  final String? token;
  final UserResponse? user;
  final bool isNewUser;

  ApiResponse({
    required this.success,
    required this.message,
    this.token,
    this.user,
    this.isNewUser = false,
  });
}

class UserResponse {
  final String id;
  final String? email;
  final String username;
  final String? twitterHandle;
  final String? twitterId;
  final String? githubHandle;
  final String? githubId;
  final bool isApproved;
  final bool isAdmin;

  UserResponse({
    required this.id,
    this.email,
    required this.username,
    this.twitterHandle,
    this.twitterId,
    this.githubHandle,
    this.githubId,
    required this.isApproved,
    required this.isAdmin,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      id: json['id'] ?? '',
      email: json['email'],
      username: json['username'] ?? '',
      twitterHandle: json['twitterHandle'],
      twitterId: json['twitterId'],
      githubHandle: json['githubHandle'],
      githubId: json['githubId'],
      isApproved: json['isApproved'] ?? false,
      isAdmin: json['isAdmin'] ?? false,
    );
  }
}

class OAuthInitResult {
  final String authUrl;
  final String state;
  final String codeVerifier;

  OAuthInitResult({
    required this.authUrl,
    required this.state,
    required this.codeVerifier,
  });
}

class Announcement {
  final String id;
  final String? title;
  final String message;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String? createdBy;
  final String? imageUrl;

  Announcement({
    required this.id,
    this.title,
    required this.message,
    required this.createdAt,
    this.startsAt,
    this.expiresAt,
    this.createdBy,
    this.imageUrl,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] ?? '',
      title: json['title'],
      message: json['message'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      startsAt:
          json['startsAt'] != null ? DateTime.parse(json['startsAt']) : null,
      expiresAt:
          json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      createdBy: json['createdBy'],
      imageUrl: json['imageUrl'],
    );
  }
}

class BeaconUser {
  final String id;
  final String username;

  BeaconUser({
    required this.id,
    required this.username,
  });

  factory BeaconUser.fromJson(Map<String, dynamic> json) {
    return BeaconUser(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
    );
  }
}
