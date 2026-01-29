import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class ApiService {
  // Use centralized API config from constants.dart
  static const String baseUrl = ApiConfig.baseUrl;

  // Secure storage for JWT token
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'karass_jwt_token';

  // Current JWT token (cached in memory)
  String? _token;

  /// Get the stored JWT token
  Future<String?> getToken() async {
    _token ??= await _storage.read(key: _tokenKey);
    return _token;
  }

  /// Store JWT token securely
  Future<void> setToken(String? token) async {
    _token = token;
    if (token != null) {
      await _storage.write(key: _tokenKey, value: token);
    } else {
      await _storage.delete(key: _tokenKey);
    }
  }

  /// Clear stored token (logout)
  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  /// Get headers with optional JWT authorization
  Future<Map<String, String>> _getHeaders({bool includeAuth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (includeAuth) {
      final token = await getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<ApiResponse> register({
    required String email,
    required String username,
    required String password,
    String? twitterHandle,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          'twitterHandle': twitterHandle,
        }),
      );

      final data = jsonDecode(response.body);

      // Store JWT token if provided
      if (data['success'] == true && data['token'] != null) {
        await setToken(data['token']);
      }

      return ApiResponse(
        success: data['success'] ?? false,
        message: data['message'] ?? 'Unknown error',
        token: data['token'],
        user: data['user'] != null ? UserResponse.fromJson(data['user']) : null,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Connection error: $e',
      );
    }
  }

  Future<ApiResponse> login({
    required String emailOrUsername,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'emailOrUsername': emailOrUsername,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      // Store JWT token if provided
      if (data['success'] == true && data['token'] != null) {
        await setToken(data['token']);
      }

      return ApiResponse(
        success: data['success'] ?? false,
        message: data['message'] ?? 'Unknown error',
        token: data['token'],
        user: data['user'] != null ? UserResponse.fromJson(data['user']) : null,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Connection error: $e',
      );
    }
  }

  Future<bool> checkApprovalStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/status/$userId'),
      );

      final data = jsonDecode(response.body);
      return data['isApproved'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> approveUser(String userId) async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      final response = await http.post(
        Uri.parse('$baseUrl/admin/approve/$userId'),
        headers: headers,
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      final data = jsonDecode(response.body);
      return data['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  Future<List<Announcement>> getAnnouncements({int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/announcements?limit=$limit'),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true && data['announcements'] != null) {
        return (data['announcements'] as List)
            .map((a) => Announcement.fromJson(a))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> createAnnouncement({
    required String message,
    DateTime? startsAt,
    DateTime? expiresAt,
    String? imageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        'message': message,
      };

      if (startsAt != null) {
        body['startsAt'] = startsAt.toIso8601String();
      }
      if (expiresAt != null) {
        body['expiresAt'] = expiresAt.toIso8601String();
      }
      if (imageUrl != null) {
        body['imageUrl'] = imageUrl;
      }

      final headers = await _getHeaders(includeAuth: true);
      final response = await http.post(
        Uri.parse('$baseUrl/announcements'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setUserAsAdmin(String userId) async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      final response = await http.post(
        Uri.parse('$baseUrl/admin/set-admin/$userId'),
        headers: headers,
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateFcmToken(String userId, String fcmToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/$userId/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fcmToken': fcmToken}),
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // Beacon Management
  // ============================================

  /// Get current beacon status for authenticated user
  Future<bool> getBeaconStatus() async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      final response = await http.get(
        Uri.parse('$baseUrl/beacon/status'),
        headers: headers,
      );

      final data = jsonDecode(response.body);
      return data['isCurrentBeacon'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get the current beacon user (public)
  Future<BeaconUser?> getCurrentBeacon() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/beacon/current'),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true && data['beaconUser'] != null) {
        return BeaconUser.fromJson(data['beaconUser']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Set a user as the current beacon (admin only)
  Future<bool> setBeaconUser(String userId) async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      final url = '$baseUrl/beacon/set/$userId';
      debugPrint('Setting beacon user: POST $url');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
      );

      debugPrint('Beacon response status: ${response.statusCode}');
      debugPrint('Beacon response body: ${response.body}');

      if (response.statusCode != 200) {
        debugPrint('Beacon API error: status ${response.statusCode}');
        return false;
      }

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      debugPrint('Beacon API exception: $e');
      return false;
    }
  }

  /// Clear the current beacon (admin only)
  Future<bool> clearBeacon() async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      final response = await http.post(
        Uri.parse('$baseUrl/beacon/clear'),
        headers: headers,
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // Image Upload
  // ============================================

  /// Upload an image and get its data URL (admin only)
  Future<String?> uploadImage(List<int> imageBytes, String contentType) async {
    try {
      final headers = await _getHeaders(includeAuth: true);
      headers['Content-Type'] = contentType;

      final response = await http.post(
        Uri.parse('$baseUrl/upload/image'),
        headers: headers,
        body: imageBytes,
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['imageUrl'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class ApiResponse {
  final bool success;
  final String message;
  final String? token;
  final UserResponse? user;

  ApiResponse({
    required this.success,
    required this.message,
    this.token,
    this.user,
  });
}

class UserResponse {
  final String id;
  final String? email;
  final String username;
  final String? twitterHandle;
  final String? twitterId;
  final bool isApproved;
  final bool isAdmin;

  UserResponse({
    required this.id,
    this.email,
    required this.username,
    this.twitterHandle,
    this.twitterId,
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
      isApproved: json['isApproved'] ?? false,
      isAdmin: json['isAdmin'] ?? false,
    );
  }
}

class Announcement {
  final String id;
  final String message;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final String? createdBy;
  final String? imageUrl;

  Announcement({
    required this.id,
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
      message: json['message'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      startsAt: json['startsAt'] != null
          ? DateTime.parse(json['startsAt'])
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null,
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
