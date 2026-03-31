import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;
import 'package:vrc_monitor/services/auth_vault.dart';
import 'package:vrc_monitor/services/session_guard.dart';
import 'package:vrc_monitor/services/token_pool.dart';
import 'package:vrc_monitor/services/user_store.dart';

class AuthManager {
  AuthManager._();

  static final AuthManager instance = AuthManager._();

  static const _cookieHeader = 'Cookie';
  static const _skipRecoveryKey = 'skipAuthRecovery';
  static const _retryAttemptedKey = 'authRetryAttempted';
  static const _credentialRetryAttemptedKey = 'credentialRetryAttempted';
  static const _rotationNotice = '检测到会话失效，已自动切换到其他登录会话';

  final Expando<bool> _registeredApis = Expando<bool>(
    'auth-manager-registered',
  );
  Completer<bool>? _recoveryCompleter;
  bool _loginRequiredIssued = false;

  bool get isLoginRequiredIssued => _loginRequiredIssued;

  void resetRecoveryState() {
    _loginRequiredIssued = false;
  }

  Future<void> registerApi(VrchatDart api) async {
    await _migrateLegacyTokenIfNeeded();
    await _applyActiveToken(api);
    if (_registeredApis[api] == true) return;

    api.rawApi.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra[_skipRecoveryKey] == true) {
            handler.next(options);
            return;
          }

          final token = await AuthVault.instance.readActiveSessionToken();
          if (token.isNotEmpty) {
            options.headers[_cookieHeader] = 'auth=$token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          await _captureTokenFromHeaders(
            api,
            response.headers,
            response.requestOptions.headers,
          );
          handler.next(response);
        },
        onError: (error, handler) async {
          if (!_shouldHandleUnauthorized(error)) {
            handler.next(error);
            return;
          }

          final recoveredResponse = await _recoverUnauthorized(api, error);
          if (recoveredResponse != null) {
            handler.resolve(recoveredResponse);
            return;
          }

          handler.next(error);
        },
      ),
    );
    _registeredApis[api] = true;
  }

  Future<CurrentUser?> tryAutoLogin(VrchatDart api) async {
    await registerApi(api);
    final user = await _restoreWithTokenPool(
      api,
      allowForcedLogin: true,
      emitRotationNotice: false,
      navigateOnFailure: false,
    );
    return user;
  }

  Future<bool> ensureAuthenticatedSession(
    VrchatDart api, {
    bool allowForcedLogin = true,
    bool emitRotationNotice = false,
    bool navigateOnFailure = true,
  }) async {
    await registerApi(api);
    final user = await _restoreWithTokenPool(
      api,
      allowForcedLogin: allowForcedLogin,
      emitRotationNotice: emitRotationNotice,
      navigateOnFailure: navigateOnFailure,
    );
    return user != null;
  }

  Future<void> captureSessionTokenFromResponses(
    VrchatDart api, {
    ValidResponse<dynamic, dynamic>? primary,
    ValidResponse<dynamic, dynamic>? secondary,
  }) async {
    await registerApi(api);
    final token =
        _extractTokenFromValidatedResponse(primary) ??
        _extractTokenFromValidatedResponse(secondary);
    if (token == null || token.isEmpty) return;
    await _persistAndActivateToken(api, token);
  }

  Future<void> captureSessionTokenFromCurrentSession(VrchatDart api) async {
    await registerApi(api);
    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser(extra: {_skipRecoveryKey: true})
        .validateVrc();
    final token = _extractTokenFromValidatedResponse(success);
    if (token == null || token.isEmpty) return;
    await _persistAndActivateToken(api, token);
  }

  Future<void> clearSession(VrchatDart api) async {
    await AuthVault.instance.clearSessionTokens();
    _clearSessionCookie(api);
  }

  Future<void> _migrateLegacyTokenIfNeeded() async {
    final vault = AuthVault.instance;
    final activeToken = await vault.readActiveSessionToken();
    final pool = await vault.readSessionTokenPool();
    final legacyToken = await vault.readSessionToken();

    if (legacyToken.isEmpty) return;
    if (activeToken.isNotEmpty && pool.contains(legacyToken)) {
      await vault.clearSessionToken();
      return;
    }

    final nextPool = TokenPool.promote(pool, legacyToken);
    await vault.writeSessionTokenPool(nextPool);
    await vault.writeActiveSessionToken(legacyToken);
    await vault.clearSessionToken();
  }

  Future<void> _applyActiveToken(VrchatDart api) async {
    final token = await AuthVault.instance.readActiveSessionToken();
    if (token.isEmpty) {
      _clearSessionCookie(api);
      return;
    }
    _applySessionCookie(api, token);
  }

  Future<CurrentUser?> _restoreWithTokenPool(
    VrchatDart api, {
    required bool allowForcedLogin,
    required bool emitRotationNotice,
    required bool navigateOnFailure,
  }) async {
    final vault = AuthVault.instance;
    final active = await vault.readActiveSessionToken();
    final pool = await vault.readSessionTokenPool();

    final candidates = <String>[
      if (active.isNotEmpty) active,
      ...pool.where((token) => token != active),
    ];

    for (var i = 0; i < candidates.length; i++) {
      final token = candidates[i];
      final user = await _validateWithToken(api, token);
      if (user == null) continue;
      if (i > 0 && emitRotationNotice) {
        SessionGuard.instance.showRotationNotice(_rotationNotice);
      }
      return user;
    }

    final forcedUser = allowForcedLogin
        ? await _reLoginWithStoredCredentials(api)
        : null;
    if (forcedUser != null) {
      return forcedUser;
    }

    if (navigateOnFailure) {
      await _handleLoginRequired();
    }
    return null;
  }

  Future<CurrentUser?> _validateWithToken(VrchatDart api, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return null;

    final valid = await _verifyToken(api, normalized);
    if (!valid) return null;

    _applySessionCookie(api, normalized);
    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser(
          headers: {_cookieHeader: 'auth=$normalized'},
          extra: {_skipRecoveryKey: true},
        )
        .validateVrc();
    if (success == null) return null;

    await _persistAndActivateToken(
      api,
      _extractTokenFromValidatedResponse(success) ?? normalized,
    );
    return success.data;
  }

  Future<bool> _verifyToken(VrchatDart api, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return false;

    final (success, _) = await api.rawApi
        .getAuthenticationApi()
        .verifyAuthToken(
          headers: {_cookieHeader: 'auth=$normalized'},
          extra: {_skipRecoveryKey: true},
        )
        .validateVrc();
    return success != null;
  }

  Future<CurrentUser?> _reLoginWithStoredCredentials(VrchatDart api) async {
    final vault = AuthVault.instance;
    final forceAutoLogin = await vault.readForceAutoLogin();
    if (!forceAutoLogin) return null;

    final username = (await vault.readUsername()).trim();
    final password = await vault.readPassword();
    if (username.isEmpty || password.isEmpty) return null;

    final (loginSuccess, _) = await api.auth.login(
      username: username,
      password: password,
    );
    if (loginSuccess == null || loginSuccess.data.requiresTwoFactorAuth) {
      return null;
    }

    await captureSessionTokenFromResponses(api, primary: loginSuccess);
    await captureSessionTokenFromCurrentSession(api);
    final user = api.auth.currentUser;
    if (user != null) {
      return user;
    }

    final activeToken = await AuthVault.instance.readActiveSessionToken();
    if (activeToken.isEmpty) return null;
    return _validateWithToken(api, activeToken);
  }

  Future<void> _persistAndActivateToken(VrchatDart api, String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;

    final vault = AuthVault.instance;
    final nextPool = TokenPool.promote(
      await vault.readSessionTokenPool(),
      normalized,
    );
    await vault.writeSessionTokenPool(nextPool);
    await vault.writeActiveSessionToken(normalized);
    await vault.writeSessionToken(normalized);
    _applySessionCookie(api, normalized);
  }

  Future<void> _captureTokenFromHeaders(
    VrchatDart api,
    Headers? headers,
    Map<String, dynamic>? requestHeaders,
  ) async {
    final token =
        _extractAuthTokenFromHeaders(headers) ??
        _extractAuthTokenFromRequestHeaders(requestHeaders);
    if (token == null || token.isEmpty) return;
    await _persistAndActivateToken(api, token);
  }

  bool _shouldHandleUnauthorized(DioException error) {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401) return false;
    if (request.extra[_skipRecoveryKey] == true) return false;
    if (request.extra[_retryAttemptedKey] == true) return false;
    if (_loginRequiredIssued) return false;
    return request.extra[_credentialRetryAttemptedKey] != true;
  }

  Future<Response<dynamic>?> _recoverUnauthorized(
    VrchatDart api,
    DioException error,
  ) async {
    final request = error.requestOptions;
    final inFlightRecovery = _recoveryCompleter;
    if (inFlightRecovery != null) {
      final recovered = await inFlightRecovery.future;
      if (!recovered) return null;
      return _retryRequest(api.rawApi.dio, request);
    }

    final completer = Completer<bool>();
    _recoveryCompleter = completer;
    try {
      final currentToken =
          _extractAuthTokenFromRequestHeaders(request.headers) ??
          await AuthVault.instance.readActiveSessionToken();

      if (currentToken.isNotEmpty && await _verifyToken(api, currentToken)) {
        completer.complete(false);
        return null;
      }

      final pool = await AuthVault.instance.readSessionTokenPool();
      for (final token in pool) {
        if (token == currentToken) continue;
        if (!await _verifyToken(api, token)) continue;

        await _persistAndActivateToken(api, token);
        final response = await _retryRequest(api.rawApi.dio, request);
        if (response != null) {
          completer.complete(true);
          SessionGuard.instance.showRotationNotice(_rotationNotice);
          return response;
        }
      }

      final forceAutoLogin = await AuthVault.instance.readForceAutoLogin();
      if (forceAutoLogin) {
        final user = await _reLoginWithStoredCredentials(api);
        if (user != null) {
          final response = await _retryRequest(
            api.rawApi.dio,
            request,
            markCredentialRetry: true,
          );
          if (response != null) {
            completer.complete(true);
            return response;
          }
        }
      }

      completer.complete(false);
      await _handleLoginRequired();
      return null;
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return null;
    } finally {
      if (identical(_recoveryCompleter, completer)) {
        _recoveryCompleter = null;
      }
    }
  }

  Future<Response<dynamic>?> _retryRequest(
    Dio dio,
    RequestOptions request, {
    bool markCredentialRetry = false,
  }) async {
    final nextExtra = <String, dynamic>{
      ...request.extra,
      _retryAttemptedKey: true,
      if (markCredentialRetry) _credentialRetryAttemptedKey: true,
    };

    final nextRequest = request.copyWith(
      headers: <String, dynamic>{
        ...request.headers,
        if (await AuthVault.instance.readActiveSessionToken() case final token
            when token.isNotEmpty)
          _cookieHeader: 'auth=$token',
      },
      extra: nextExtra,
    );

    try {
      return await dio.fetch<dynamic>(nextRequest);
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _handleLoginRequired() async {
    if (_loginRequiredIssued) return;
    _loginRequiredIssued = true;
    await UserStore.instance.stopRealtimeSync();
    UserStore.instance.clearAll();
    SessionGuard.instance.requireLogin(skipTokenAutoLogin: true);
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
