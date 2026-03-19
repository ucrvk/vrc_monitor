import 'package:dio/dio.dart';

class WebClient {
  const WebClient._();

  static const String userAgent = 'vrc-monitor/1.0.0 contact@vrc-monitor.app';

  static final Dio _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      headers: const {
        'User-Agent': userAgent,
      },
    ),
  );

  static Future<Response<dynamic>> getPublic(
    String url, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _publicDio.get(url).timeout(timeout);
  }

  static Options withUserAgent({
    ResponseType? responseType,
    ValidateStatus? validateStatus,
    Map<String, dynamic>? headers,
  }) {
    return Options(
      responseType: responseType,
      validateStatus: validateStatus,
      headers: {
        'User-Agent': userAgent,
        ...?headers,
      },
    );
  }
}
