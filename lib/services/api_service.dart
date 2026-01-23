import 'dart:convert';
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
      final response = await http.post(
        Uri.parse('$baseUrl/admin/approve/$userId'),
        headers: {
          'Authorization': 'Bearer ${ApiConfig.adminSecretKey}',
        },
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
    required String userId,
    required String message,
    DateTime? startsAt,
    DateTime? expiresAt,
  }) async {
    try {
      final body = {
        'userId': userId,
        'message': message,
      };

      if (startsAt != null) {
        body['startsAt'] = startsAt.toIso8601String();
      }
      if (expiresAt != null) {
        body['expiresAt'] = expiresAt.toIso8601String();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/announcements'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${ApiConfig.adminSecretKey}',
        },
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
      final response = await http.post(
        Uri.parse('$baseUrl/admin/set-admin/$userId'),
        headers: {
          'Authorization': 'Bearer ${ApiConfig.adminSecretKey}',
        },
      );

      final data = jsonDecode(response.body);
      return data['success'] ?? false;
    } catch (e) {
      return false;
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

  Announcement({
    required this.id,
    required this.message,
    required this.createdAt,
    this.startsAt,
    this.expiresAt,
    this.createdBy,
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
    );
  }
}
