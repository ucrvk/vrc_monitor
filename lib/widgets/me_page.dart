import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/settings_page.dart';

class MePage extends StatefulWidget {
  const MePage({super.key, required this.currentUser});

  final CurrentUser currentUser;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  static final Uri _projectGithubUri =
      Uri.parse('https://github.com/ucrvk/vrc_monitor');

  String _appVersion = '读取中...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _MeAvatar(imageUrl: _currentUserAvatarUrl(widget.currentUser)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.currentUser.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('设置'),
                onTap: _openSettingsPage,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于'),
                onTap: _showAboutDialog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = '未知版本';
      });
    }
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('关于'),
          content: Text('当前版本: $_appVersion'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () async {
                final launched = await _openProjectGithub();
                if (dialogContext.mounted && launched) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('访问项目 GitHub'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _openProjectGithub() async {
    try {
      final launched = await launchUrl(
        _projectGithubUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return true;
      _showLaunchFailedMessage();
      return false;
    } on PlatformException {
      _showLaunchFailedMessage();
      return false;
    } catch (_) {
      _showLaunchFailedMessage();
      return false;
    }
  }

  void _showLaunchFailedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开链接，请重启应用后重试。')),
    );
  }

  String? _currentUserAvatarUrl(CurrentUser user) {
    final candidates = [
      user.profilePicOverrideThumbnail,
      user.profilePicOverride,
      user.currentAvatarThumbnailImageUrl,
      user.userIcon,
      user.currentAvatarImageUrl,
    ];

    for (final url in candidates) {
      if (url.isNotEmpty) return url;
    }
    return null;
  }
}

class _MeAvatar extends StatelessWidget {
  const _MeAvatar({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return const CircleAvatar(child: Icon(Icons.person));
    }

    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundImage: NetworkImage(imageUrl!),
      child: const Icon(Icons.person),
    );
  }
}
