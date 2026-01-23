import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/app_state.dart';

class StorageService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Unlock status
  bool get isUnlocked => _prefs?.getBool(StorageKeys.isUnlocked) ?? false;

  Future<void> setUnlocked(bool value) async {
    await _prefs?.setBool(StorageKeys.isUnlocked, value);
  }

  // Sign up status
  bool get hasCompletedSignUp => _prefs?.getBool(StorageKeys.hasCompletedSignUp) ?? false;

  Future<void> setHasCompletedSignUp(bool value) async {
    await _prefs?.setBool(StorageKeys.hasCompletedSignUp, value);
  }

  // Pending approval status
  bool get isPendingApproval => _prefs?.getBool(StorageKeys.isPendingApproval) ?? false;

  Future<void> setIsPendingApproval(bool value) async {
    await _prefs?.setBool(StorageKeys.isPendingApproval, value);
  }

  // User data
  UserData get userData => UserData(
    email: _prefs?.getString(StorageKeys.userEmail),
    username: _prefs?.getString(StorageKeys.username),
    twitterHandle: _prefs?.getString(StorageKeys.twitterHandle),
    isAdmin: _prefs?.getBool(StorageKeys.isAdmin) ?? false,
  );

  Future<void> saveUserData(UserData data) async {
    if (data.email != null) {
      await _prefs?.setString(StorageKeys.userEmail, data.email!);
    }
    if (data.username != null) {
      await _prefs?.setString(StorageKeys.username, data.username!);
    }
    if (data.twitterHandle != null) {
      await _prefs?.setString(StorageKeys.twitterHandle, data.twitterHandle!);
    }
    await _prefs?.setBool(StorageKeys.isAdmin, data.isAdmin);
  }

  // User ID persistence
  String? get userId => _prefs?.getString(StorageKeys.userId);

  Future<void> setUserId(String? id) async {
    if (id != null) {
      await _prefs?.setString(StorageKeys.userId, id);
    } else {
      await _prefs?.remove(StorageKeys.userId);
    }
  }

  // Clear all data (for testing/reset)
  Future<void> clearAll() async {
    await _prefs?.clear();
  }
}
