import 'dart:async';

import 'package:dio/dio.dart';

class WebClient {
  const WebClient._();

  static const String userAgent = 'vrc-monitor/1.0.0 contact@vrc-monitor.app';

  static final Dio _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      headers: const {'User-Agent': userAgent},
    ),
  );

  static Dio get publicDio => _publicDio;

  static Future<Response<dynamic>> getPublic(
    String url, {
    Duration timeout = const Duration(seconds: 5),
    int maxAttempts = 2,
  }) {
    return getWithUserAgent<dynamic>(
      dio: _publicDio,
      url: url,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }

  static Future<Response<T>> getWithUserAgent<T>({
    required Dio dio,
    required String url,
    Options? options,
    Duration timeout = const Duration(seconds: 5),
    int maxAttempts = 2,
  }) async {
    final mergedOptions = _mergeUserAgentOptions(options);
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        return await dio.get<T>(url, options: mergedOptions).timeout(timeout);
      } on TimeoutException {
        if (attempt >= maxAttempts) rethrow;
      } on DioException catch (error) {
        if (attempt >= maxAttempts || !_isRetryableDioError(error)) {
          rethrow;
        }
      }

      await Future<void>.delayed(_retryDelay(attempt));
    }
  }

  static Options withUserAgent({
    ResponseType? responseType,
    ValidateStatus? validateStatus,
    Map<String, dynamic>? headers,
  }) {
    return Options(
      responseType: responseType,
      validateStatus: validateStatus,
      headers: {'User-Agent': userAgent, ...?headers},
    );
  }

  static Options _mergeUserAgentOptions(Options? options) {
    if (options == null) {
      return withUserAgent();
    }

    return options.copyWith(
      headers: {'User-Agent': userAgent, ...?options.headers},
    );
  }

  static bool _isRetryableDioError(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.connectionError) {
      return true;
    }

    final status = error.response?.statusCode;
    if (status == null) return false;
    return status == 429 || status >= 500;
  }

  static Duration _retryDelay(int attempt) {
    return Duration(milliseconds: attempt * 300);
  }
}
