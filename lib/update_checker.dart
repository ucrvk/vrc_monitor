import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrc_monitor/app_config.dart';
import 'package:vrc_monitor/network/web_client.dart';

enum UpdateSourceType { github, updateManager }

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.force,
    required this.message,
    required this.downloadLink,
    required this.sourceType,
  });

  final String latestVersion;
  final bool force;
  final String message;
  final String downloadLink;
  final UpdateSourceType sourceType;
}

class AppUpdateChecker {
  static const String _ignoredVersionKey = 'ignored_update_version';
  static const MethodChannel _installerChannel = MethodChannel(
    'top.wenwen12305.monitor/update_installer',
  );

  AppUpdateChecker({
    Future<String> Function()? localVersionLoader,
    Future<AppConfig> Function()? configLoader,
    Future<Map<String, dynamic>?> Function(String url)? publicJsonFetcher,
    Future<SharedPreferences> Function()? prefsProvider,
    Future<String?> Function()? abiResolver,
  }) : _localVersionLoader = localVersionLoader ?? _defaultLocalVersionLoader,
       _configLoader = configLoader ?? AppConfigLoader.load,
       _publicJsonFetcher = publicJsonFetcher ?? _defaultPublicJsonFetcher,
       _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
       _abiResolver = abiResolver ?? _defaultAbiResolver;

  final Future<String> Function() _localVersionLoader;
  final Future<AppConfig> Function() _configLoader;
  final Future<Map<String, dynamic>?> Function(String url) _publicJsonFetcher;
  final Future<SharedPreferences> Function() _prefsProvider;
  final Future<String?> Function() _abiResolver;

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final localVersion = await _localVersionLoader();
      final config = await _configLoader();

      final sourceType = config.hasUpdateManager
          ? UpdateSourceType.updateManager
          : UpdateSourceType.github;
      final baseRequestUri = sourceType == UpdateSourceType.updateManager
          ? config.updateManagerConfigUri
          : config.versionJsonRawUriForBranch(config.branch);
      if (baseRequestUri == null) return null;
      final abi = await _abiResolver();
      final requestUri = _withQuery(
        baseRequestUri,
        branch: config.branch,
        abi: abi,
      );

      final payload = await _publicJsonFetcher(requestUri.toString());
      if (payload == null) return null;

      final latestVersion = payload['version']?.toString().trim() ?? '';
      if (latestVersion.isEmpty) return null;

      final force = _toBool(payload['force']);
      final message = payload['msg']?.toString().trim() ?? '';
      final downloadLink = payload['downloadLink']?.toString().trim() ?? '';
      if (!_isRemoteVersionNewer(remote: latestVersion, local: localVersion)) {
        return null;
      }

      final prefs = await _prefsProvider();
      final ignoredVersion = prefs.getString(_ignoredVersionKey);
      if (!force && ignoredVersion == latestVersion) return null;

      return AppUpdateInfo(
        latestVersion: latestVersion,
        force: force,
        message: message,
        downloadLink: downloadLink,
        sourceType: sourceType,
      );
    } catch (_) {
      // Ignore update check errors to avoid blocking app startup.
      return null;
    }
  }

  Future<void> ignoreVersion(String version) async {
    final prefs = await _prefsProvider();
    await prefs.setString(_ignoredVersionKey, version);
  }

  Future<Uri> releaseUrlForVersion(String version) async {
    final config = await _configLoader();
    return config.releaseUrlForVersion(version);
  }

  static Future<String> _defaultLocalVersionLoader() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version.trim();
  }

  static Future<Map<String, dynamic>?> _defaultPublicJsonFetcher(
    String url,
  ) async {
    final response = await WebClient.getPublic(url);
    return _toMapStatic(response.data);
  }

  static Map<String, dynamic>? _toMapStatic(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    return null;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  bool _isRemoteVersionNewer({required String remote, required String local}) {
    return _compareSemVer(remote, local) > 0;
  }

  Uri _withQuery(Uri uri, {required String branch, required String? abi}) {
    final trimmedBranch = branch.trim();
    final nextQuery = Map<String, String>.from(uri.queryParameters);
    if (trimmedBranch.isNotEmpty) {
      nextQuery['branch'] = trimmedBranch;
    }
    final normalizedAbi = _normalizeAbi(abi);
    if (normalizedAbi != null) {
      nextQuery['abi'] = normalizedAbi;
    }
    if (nextQuery.isEmpty) return uri;
    return uri.replace(queryParameters: nextQuery);
  }

  static Future<String?> _defaultAbiResolver() async {
    if (Platform.isAndroid) {
      try {
        final abi = await _installerChannel.invokeMethod<String>('getAbi');
        return _normalizeAbi(abi);
      } catch (_) {
        return null;
      }
    }

    final version = Platform.version.toLowerCase();
    if (version.contains('x64') || version.contains('x86_64')) {
      return 'x86_64';
    }
    if (version.contains('arm64') || version.contains('aarch64')) {
      return 'arm64-v8a';
    }
    if (version.contains('arm')) {
      return 'armeabi-v7a';
    }
    return null;
  }

  static String? _normalizeAbi(String? abi) {
    final value = abi?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    switch (value) {
      case 'arm64-v8a':
      case 'armeabi-v7a':
      case 'x86_64':
        return value;
      default:
        return null;
    }
  }

  int _compareSemVer(String a, String b) {
    final left = _ParsedSemVer.tryParse(a);
    final right = _ParsedSemVer.tryParse(b);
    if (left == null || right == null) {
      return 0;
    }
    return left.compareTo(right);
  }
}

class _ParsedSemVer {
  const _ParsedSemVer({required this.core, required this.preRelease});

  final List<int> core;
  final List<String> preRelease;

  static _ParsedSemVer? tryParse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final withoutBuild = value.split('+').first;
    final dashIndex = withoutBuild.indexOf('-');
    final coreText = dashIndex == -1
        ? withoutBuild
        : withoutBuild.substring(0, dashIndex);
    final preReleaseText = dashIndex == -1
        ? ''
        : withoutBuild.substring(dashIndex + 1);

    final coreParts = coreText
        .split('.')
        .map((part) => int.tryParse(part))
        .toList();
    if (coreParts.any((part) => part == null)) return null;

    final normalizedCore = coreParts.map((e) => e!).toList();
    while (normalizedCore.length < 3) {
      normalizedCore.add(0);
    }

    final preRelease = preReleaseText.isEmpty
        ? <String>[]
        : preReleaseText.split('.').where((p) => p.isNotEmpty).toList();

    return _ParsedSemVer(core: normalizedCore, preRelease: preRelease);
  }

  int compareTo(_ParsedSemVer other) {
    final maxLen = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var i = 0; i < maxLen; i++) {
      final a = i < core.length ? core[i] : 0;
      final b = i < other.core.length ? other.core[i] : 0;
      if (a != b) return a.compareTo(b);
    }

    final thisHasPre = preRelease.isNotEmpty;
    final otherHasPre = other.preRelease.isNotEmpty;
    if (!thisHasPre && !otherHasPre) return 0;
    if (!thisHasPre) return 1;
    if (!otherHasPre) return -1;

    final preLen = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < preLen; i++) {
      final partA = preRelease[i];
      final partB = other.preRelease[i];
      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);
      if (numA != null && numB != null) {
        if (numA != numB) return numA.compareTo(numB);
        continue;
      }
      if (numA != null && numB == null) return -1;
      if (numA == null && numB != null) return 1;
      final textCompare = partA.compareTo(partB);
      if (textCompare != 0) return textCompare;
    }

    return preRelease.length.compareTo(other.preRelease.length);
  }
}
