import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/auth_vault.dart';

class AuthManager {
  AuthManager._();

  static final AuthManager instance = AuthManager._();

  static const _cookieHeader = 'Cookie';

  Future<CurrentUser?> tryAutoLogin(VrchatDart api) async {
    final token = await AuthVault.instance.readSessionToken();
    if (token.isNotEmpty) {
      final user = await _validateWithToken(api, token);
      if (user != null) return user;
      await clearSession(api);
    }

    return _validateWithPersistedCookieSession(api);
  }

  Future<void> captureSessionTokenFromResponses(
    VrchatDart api, {
    ValidResponse<dynamic, dynamic>? primary,
    ValidResponse<dynamic, dynamic>? secondary,
  }) async {
    final token =
        _extractTokenFromValidatedResponse(primary) ??
        _extractTokenFromValidatedResponse(secondary);
    if (token == null || token.isEmpty) return;
    await AuthVault.instance.writeSessionToken(token);
    _applySessionCookie(api, token);
  }

  Future<void> captureSessionTokenFromCurrentSession(VrchatDart api) async {
    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser()
        .validateVrc();
    final token = _extractTokenFromValidatedResponse(success);
    if (token == null || token.isEmpty) return;
    await AuthVault.instance.writeSessionToken(token);
    _applySessionCookie(api, token);
  }

  Future<void> clearSession(VrchatDart api) async {
    await AuthVault.instance.clearSessionToken();
    _clearSessionCookie(api);
  }

  Future<CurrentUser?> _validateWithToken(VrchatDart api, String token) async {
    _applySessionCookie(api, token);
    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser(headers: {_cookieHeader: 'auth=$token'})
        .validateVrc();
    if (success == null) return null;

    final latestToken = _extractTokenFromValidatedResponse(success);
    if (latestToken != null && latestToken.isNotEmpty && latestToken != token) {
      await AuthVault.instance.writeSessionToken(latestToken);
      _applySessionCookie(api, latestToken);
    }
    return success.data;
  }

  Future<CurrentUser?> _validateWithPersistedCookieSession(
    VrchatDart api,
  ) async {
    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser()
        .validateVrc();
    if (success == null) return null;

    final token = _extractTokenFromValidatedResponse(success);
    if (token != null && token.isNotEmpty) {
      await AuthVault.instance.writeSessionToken(token);
      _applySessionCookie(api, token);
    }
    return success.data;
  }

  void _applySessionCookie(VrchatDart api, String token) {
    api.rawApi.dio.options.headers[_cookieHeader] = 'auth=$token';
  }

  void _clearSessionCookie(VrchatDart api) {
    api.rawApi.dio.options.headers.remove(_cookieHeader);
  }

  String? _extractTokenFromValidatedResponse(
    ValidResponse<dynamic, dynamic>? response,
  ) {
    if (response == null) return null;
    return _extractAuthTokenFromHeaders(response.response.headers) ??
        _extractAuthTokenFromRequestHeaders(
          response.response.requestOptions.headers,
        );
  }

  String? _extractAuthTokenFromHeaders(Headers? headers) {
    if (headers == null) return null;

    final setCookies = <String>[
      ...?headers.map['set-cookie'],
      ...?headers.map['Set-Cookie'],
    ];

    for (final cookie in setCookies) {
      final match = RegExp(r'(^|;\s*)auth=([^;]+)').firstMatch(cookie);
      if (match != null) {
        return match.group(2);
      }
    }
    return null;
  }

  String? _extractAuthTokenFromRequestHeaders(Map<String, dynamic>? headers) {
    if (headers == null) return null;

    final cookieHeader = headers[_cookieHeader] ?? headers['cookie'];
    if (cookieHeader == null) return null;

    final cookieText = switch (cookieHeader) {
      String value => value,
      List value => value.join('; '),
      _ => cookieHeader.toString(),
    };
    final match = RegExp(r'(^|;\s*)auth=([^;]+)').firstMatch(cookieText);
    return match?.group(2);
  }
}
