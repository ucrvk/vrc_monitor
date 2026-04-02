import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrc_monitor/network/web_client.dart';

class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel(
    'top.wenwen12305.monitor/update_installer',
  );

  Future<bool> downloadAndInstallApk(
    String url, {
    int? expectedTotalBytes,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (!Platform.isAndroid) return false;

    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return false;

    final tempDir = await getTemporaryDirectory();
    final apkPath = '${tempDir.path}/vrc_monitor_update.apk';

    await WebClient.publicDio.download(
      trimmedUrl,
      apkPath,
      options: WebClient.withUserAgent(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) {
        final resolvedTotal = total > 0 ? total : (expectedTotalBytes ?? total);
        onProgress?.call(received, resolvedTotal);
      },
    );

    final installed = await _channel.invokeMethod<bool>(
      'installApk',
      <String, dynamic>{'apkPath': apkPath},
    );
    return installed == true;
  }
}
