class AppConfig {
  const AppConfig({
    required this.githubPage,
    required this.branch,
  });

  static const AppConfig fallback = AppConfig(
    githubPage: 'https://github.com/ucrvk/vrc_monitor',
    branch: 'main',
  );

  final String githubPage;
  final String branch;

  Uri get githubPageUri => Uri.parse(githubPage);

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
  static const AppConfig _config = AppConfig.fallback;

  static Future<AppConfig> load() {
    return Future<AppConfig>.value(_config);
  }
}
