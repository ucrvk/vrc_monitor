import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthVault {
  AuthVault._();

  static final AuthVault instance = AuthVault._();

  static const _kRememberPassword = 'remember_password';
  static const _kAutoLogin = 'auto_login';
  static const _kSavedUsername = 'saved_username';
  static const _kSavedPassword = 'saved_password';
  static const _kSessionToken = 'session_token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<bool> readRememberPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRememberPassword) ?? false;
  }

  Future<void> writeRememberPassword(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberPassword, value);
  }

  Future<bool> readAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoLogin) ?? true;
  }

  Future<void> writeAutoLogin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLogin, value);
  }

  Future<String> readUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSavedUsername) ?? '';
  }

  Future<void> writeUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSavedUsername, username);
  }

  Future<String> readPassword() async {
    return (await _secureStorage.read(key: _kSavedPassword)) ?? '';
  }

  Future<void> writePassword(String password) async {
    await _secureStorage.write(key: _kSavedPassword, value: password);
  }

  Future<void> clearPassword() async {
    await _secureStorage.delete(key: _kSavedPassword);
  }

  Future<String> readSessionToken() async {
    return (await _secureStorage.read(key: _kSessionToken)) ?? '';
  }

  Future<void> writeSessionToken(String token) async {
    await _secureStorage.write(key: _kSessionToken, value: token);
  }

  Future<void> clearSessionToken() async {
    await _secureStorage.delete(key: _kSessionToken);
  }
}

