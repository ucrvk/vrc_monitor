import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/settings_page.dart';

class MePage extends StatefulWidget {
  const MePage({super.key, required this.currentUser});

  final CurrentUser currentUser;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
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
          child: ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            onTap: _openSettingsPage,
          ),
        ),
      ],
    );
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
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
