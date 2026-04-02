import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppConfig {
  const AppConfig({
    required this.githubPage,
    required this.branch,
    this.updateManagerBaseUrl,
  });

  static const AppConfig fallback = AppConfig(
    githubPage: 'https://github.com/ucrvk/vrc_monitor',
    branch: 'beta',
    updateManagerBaseUrl: null,
  );

  final String githubPage;
  final String branch;
  final String? updateManagerBaseUrl;

  Uri get githubPageUri => Uri.parse(githubPage);

  bool get hasUpdateManager =>
      (updateManagerBaseUrl?.trim().isNotEmpty ?? false);

  Uri? get updateManagerConfigUri {
    final base = updateManagerBaseUrl?.trim() ?? '';
    if (base.isEmpty) return null;
    final normalized = base.replaceFirst(RegExp(r'/+$'), '');
    return Uri.tryParse(normalized);
  }

  Uri releaseUrlForVersion(String version) {
    final base = githubPage.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/releases/tag/$version');
  }

  Uri get versionJsonRawUri {
    return versionJsonRawUriForBranch(branch);
  }

  Uri versionJsonRawUriForBranch(String targetBranch) {
    final parsed = Uri.tryParse(githubPage);
    if (parsed == null) {
      return Uri.parse(
        'https://raw.githubusercontent.com/ucrvk/vrc_monitor/main/version.json',
      );
    }

    final host = parsed.host.toLowerCase();
    final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
    if (host == 'github.com' && segments.length >= 2) {
      final owner = segments[0];
      final repo = segments[1];
      return Uri.parse(
        'https://raw.githubusercontent.com/$owner/$repo/$targetBranch/version.json',
      );
    }

    return Uri.parse(
      'https://raw.githubusercontent.com/ucrvk/vrc_monitor/main/version.json',
    );
  }
}

class AppConfigLoader {
  static const String _branchKey = 'app_release_branch';

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBranch = prefs.getString(_branchKey);
    final branch =
        _normalizeBranch(savedBranch) ?? await _defaultBranchByCurrentVersion();
    return AppConfig(
      githubPage: AppConfig.fallback.githubPage,
      branch: branch,
      updateManagerBaseUrl: AppConfig.fallback.updateManagerBaseUrl,
    );
  }

  static Future<void> setBranch(String branch) async {
    final normalized = _normalizeBranch(branch) ?? AppConfig.fallback.branch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_branchKey, normalized);
  }

  static String? _normalizeBranch(String? value) {
    final v = value?.trim().toLowerCase();
    if (v == 'main' || v == 'beta') return v;
    return null;
  }

  static Future<String> _defaultBranchByCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.toLowerCase();
      if (version.contains('-beta') || version.contains('.beta')) {
        return 'beta';
      }
      return 'main';
    } catch (_) {
      return 'main';
    }
  }
}
