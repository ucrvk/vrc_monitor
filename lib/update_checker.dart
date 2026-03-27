import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrc_monitor/app_config.dart';
import 'package:vrc_monitor/network/web_client.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.force,
  });

  final String latestVersion;
  final bool force;
}

class AppUpdateChecker {
  static const String _ignoredVersionKey = 'ignored_update_version';

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final localVersion = packageInfo.version.trim();
      final config = await AppConfigLoader.load();
      final targetBranch = config.branch;

      final response = await WebClient.getPublic(
        config.versionJsonRawUriForBranch(targetBranch).toString(),
      );

      final payload = _toMap(response.data);
      if (payload == null) return null;

      final latestVersion = payload['version']?.toString().trim() ?? '';
      if (latestVersion.isEmpty) return null;

      final force = _toBool(payload['force']);
      if (!_isRemoteVersionNewer(remote: latestVersion, local: localVersion)) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final ignoredVersion = prefs.getString(_ignoredVersionKey);
      if (!force && ignoredVersion == latestVersion) return null;

      return AppUpdateInfo(latestVersion: latestVersion, force: force);
    } catch (_) {
      // Ignore update check errors to avoid blocking app startup.
      return null;
    }
  }

  Future<void> ignoreVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ignoredVersionKey, version);
  }

  Future<Uri> releaseUrlForVersion(String version) async {
    final config = await AppConfigLoader.load();
    return config.releaseUrlForVersion(version);
  }

  Map<String, dynamic>? _toMap(dynamic data) {
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

  bool _isRemoteVersionNewer({
    required String remote,
    required String local,
  }) {
    return _compareSemVer(remote, local) > 0;
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
  const _ParsedSemVer({
    required this.core,
    required this.preRelease,
  });

  final List<int> core;
  final List<String> preRelease;

  static _ParsedSemVer? tryParse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final withoutBuild = value.split('+').first;
    final dashIndex = withoutBuild.indexOf('-');
    final coreText = dashIndex == -1 ? withoutBuild : withoutBuild.substring(0, dashIndex);
    final preReleaseText = dashIndex == -1 ? '' : withoutBuild.substring(dashIndex + 1);

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
    final maxLen = core.length > other.core.length ? core.length : other.core.length;
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

    final preLen =
        preRelease.length < other.preRelease.length ? preRelease.length : other.preRelease.length;
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
