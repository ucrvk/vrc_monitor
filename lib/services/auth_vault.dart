import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrc_monitor/services/token_pool.dart';

class AuthVault {
  AuthVault._();

  static final AuthVault instance = AuthVault._();

  static const _kRememberPassword = 'remember_password';
  static const _kAutoLogin = 'auto_login';
  static const _kSavedUsername = 'saved_username';
  static const _kSavedPassword = 'saved_password';
  static const _kSessionToken = 'session_token';
  static const _kSessionTokenPool = 'session_token_pool';
  static const _kActiveSessionToken = 'active_session_token';
  static const _kForceAutoLogin = 'force_auto_login';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<bool> readRememberPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kRememberPassword) ?? false;
  }

  Future<void> writeRememberPassword(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberPassword, value);
    if (!value) {
      await prefs.setBool(_kForceAutoLogin, false);
    }
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kForceAutoLogin, false);
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

  Future<List<String>> readSessionTokenPool() async {
    final raw = (await _secureStorage.read(key: _kSessionTokenPool)) ?? '';
    if (raw.isEmpty) return const [];
    return TokenPool.normalize(raw.split('\n'));
  }

  Future<void> writeSessionTokenPool(List<String> tokens) async {
    final normalized = TokenPool.normalize(tokens);
    if (normalized.isEmpty) {
      await _secureStorage.delete(key: _kSessionTokenPool);
      return;
    }
    await _secureStorage.write(
      key: _kSessionTokenPool,
      value: normalized.join('\n'),
    );
  }

  Future<String> readActiveSessionToken() async {
    return (await _secureStorage.read(key: _kActiveSessionToken)) ?? '';
  }

  Future<void> writeActiveSessionToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      await _secureStorage.delete(key: _kActiveSessionToken);
      return;
    }
    await _secureStorage.write(key: _kActiveSessionToken, value: normalized);
  }

  Future<void> removeSessionToken(String token) async {
    final nextPool = TokenPool.remove(await readSessionTokenPool(), token);
    await writeSessionTokenPool(nextPool);
    final active = await readActiveSessionToken();
    if (active.trim() == token.trim()) {
      await writeActiveSessionToken(nextPool.isEmpty ? '' : nextPool.first);
    }
  }

  Future<void> clearSessionTokens() async {
    await _secureStorage.delete(key: _kSessionTokenPool);
    await _secureStorage.delete(key: _kActiveSessionToken);
    await _secureStorage.delete(key: _kSessionToken);
  }

  Future<bool> readForceAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kForceAutoLogin) ?? false;
  }

  Future<void> writeForceAutoLogin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_kRememberPassword, true);
    }
    await prefs.setBool(_kForceAutoLogin, value);
  }
}
