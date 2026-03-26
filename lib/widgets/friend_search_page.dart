import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendSearchUser {
  const FriendSearchUser({
    required this.id,
    required this.displayName,
    required this.status,
    required this.location,
    required this.locationText,
    required this.lastPlatform,
    required this.tags,
    required this.isFriend,
    this.bio,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
    this.profilePicOverrideThumbnail,
    this.profilePicOverride,
    this.currentAvatarThumbnailImageUrl,
    this.userIcon,
    this.imageUrl,
  });

  factory FriendSearchUser.fromLimitedUserSearch(
    LimitedUserSearch user, {
    required String locationText,
  }) {
    final normalizedBioLinks = user.bioLinks
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return FriendSearchUser(
      id: user.id,
      displayName: user.displayName,
      status: user.status,
      location: 'offline',
      locationText: locationText,
      lastPlatform: user.lastPlatform,
      tags: user.tags,
      bio: user.bio,
      statusDescription: _normalizeText(user.statusDescription),
      pronouns: _normalizeText(user.pronouns),
      bioLinks: normalizedBioLinks ?? const [],
      profilePicOverrideThumbnail: user.profilePicOverride,
      profilePicOverride: user.profilePicOverride,
      currentAvatarThumbnailImageUrl: user.currentAvatarThumbnailImageUrl,
      userIcon: user.userIcon,
      imageUrl: user.currentAvatarImageUrl,
      isFriend: user.isFriend,
    );
  }

  static String? _normalizeText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  final String id;
  final String displayName;
  final UserStatus status;
  final String location;
  final String locationText;
  final String lastPlatform;
  final List<String> tags;
  final bool isFriend;
  final String? bio;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;
  final String? profilePicOverrideThumbnail;
  final String? profilePicOverride;
  final String? currentAvatarThumbnailImageUrl;
  final String? userIcon;
  final String? imageUrl;

  String? get avatarUrl {
    final candidates = [
      profilePicOverrideThumbnail,
      profilePicOverride,
      currentAvatarThumbnailImageUrl,
      userIcon,
      imageUrl,
    ];
    for (final url in candidates) {
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  String? get smallAvatarUrl {
    if (userIcon != null && userIcon!.isNotEmpty) return userIcon;
    return avatarUrl;
  }

  Color get trustColor {
    final trustTags = tags.map((e) => e.toLowerCase()).toSet();
    if (trustTags.contains('system_trust_veteran')) {
      return const Color(0xFF8E44AD);
    }
    if (trustTags.contains('system_trust_trusted')) {
      return const Color(0xFFFF9800);
    }
    if (trustTags.contains('system_trust_known')) {
      return const Color(0xFF4CAF50);
    }
    if (trustTags.contains('system_trust_basic')) {
      return const Color(0xFF64B5F6);
    }
    return Colors.grey;
  }
}

class FriendSearchPage extends StatefulWidget {
  const FriendSearchPage({
    super.key,
    required this.friends,
    required this.dio,
    required this.rawApi,
    required this.onOpenDetail,
  });

  final List<FriendSearchUser> friends;
  final Dio dio;
  final VrchatDartGenerated rawApi;
  final Future<void> Function(FriendSearchUser friend) onOpenDetail;

  @override
  State<FriendSearchPage> createState() => _FriendSearchPageState();
}

class _FriendSearchPageState extends State<FriendSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  bool _searchingAll = false;
  bool _loadingAll = false;
  String? _searchError;
  List<FriendSearchUser> _allSearchMatches = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.trim().toLowerCase();
    final friendMatches = widget.friends.where((friend) {
      if (keyword.isEmpty) return true;
      return friend.displayName.toLowerCase().contains(keyword);
    }).toList();
    final showFriendMatches = keyword.isNotEmpty && !_searchingAll;
    final showAllMatches = keyword.isNotEmpty && _searchingAll;
    final hasAnyResult =
        (showFriendMatches && friendMatches.isNotEmpty) ||
        (showAllMatches && _allSearchMatches.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索好友')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '默认仅搜索好友，按回车搜索全部',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _query = '';
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                  _searchingAll = false;
                  _loadingAll = false;
                  _searchError = null;
                  _allSearchMatches = const [];
                });
              },
              onSubmitted: (_) => _searchAllUsersByName(),
            ),
          ),
          Expanded(
            child: keyword.isEmpty
                ? const SizedBox.shrink()
                : _loadingAll
                ? const Center(child: CircularProgressIndicator())
                : _searchError != null
                ? Center(child: Text('搜索失败: $_searchError'))
                : !hasAnyResult
                ? const Center(child: Text('没有匹配的目标'))
                : ListView.separated(
                    itemCount: showAllMatches
                        ? _allSearchMatches.length
                        : friendMatches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final friend = showAllMatches
                          ? _allSearchMatches[index]
                          : friendMatches[index];
                      return _SearchFriendRow(
                        friend: friend,
                        dio: widget.dio,
                        onTap: () => widget.onOpenDetail(friend),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _searchAllUsersByName() async {
    final keyword = _query.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searchingAll = false;
        _loadingAll = false;
        _searchError = null;
        _allSearchMatches = const [];
      });
      return;
    }

    setState(() {
      _searchingAll = true;
      _loadingAll = true;
      _searchError = null;
      _allSearchMatches = const [];
    });

    try {
      final (success, failure) = await widget.rawApi
          .getUsersApi()
          .searchUsers(search: keyword, n: 100)
          .validateVrc();
      if (!mounted) return;
      if (_query.trim() != keyword) return;

      if (success == null) {
        setState(() {
          _loadingAll = false;
          _searchError = failure?.error.toString() ?? '未知错误';
          _allSearchMatches = const [];
        });
        return;
      }

      final friendById = {
        for (final friend in widget.friends) friend.id: friend,
      };
      final ordered = <FriendSearchUser>[];
      final seenIds = <String>{};

      for (final user in success.data) {
        if (!user.displayName.toLowerCase().contains(keyword.toLowerCase())) {
          continue;
        }

        final existingFriend = friendById[user.id];
        final entry =
            existingFriend ??
            FriendSearchUser.fromLimitedUserSearch(user, locationText: '搜索结果');
        if (seenIds.add(entry.id)) {
          ordered.add(entry);
        }
      }

      ordered.sort((a, b) {
        if (a.isFriend != b.isFriend) return a.isFriend ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

      setState(() {
        _loadingAll = false;
        _allSearchMatches = ordered;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAll = false;
        _searchError = e.toString();
        _allSearchMatches = const [];
      });
    }
  }
}

class _SearchFriendRow extends StatelessWidget {
  const _SearchFriendRow({
    required this.friend,
    required this.dio,
    required this.onTap,
  });

  final FriendSearchUser friend;
  final Dio dio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusMeta = _statusMeta(friend.status);
    return ListTile(
      onTap: onTap,
      leading: _SearchAvatarWithStatusDot(
        dio: dio,
        userId: friend.id,
        imageUrl: friend.smallAvatarUrl,
        statusColor: statusMeta.color,
      ),
      title: Text(
        friend.displayName,
        style: TextStyle(color: friend.trustColor, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(friend.locationText),
      ),
    );
  }

  _StatusMeta _statusMeta(UserStatus status) {
    switch (status) {
      case UserStatus.joinMe:
        return const _StatusMeta(color: Colors.blue);
      case UserStatus.active:
        return const _StatusMeta(color: Colors.green);
      case UserStatus.askMe:
        return const _StatusMeta(color: Colors.orange);
      case UserStatus.busy:
        return const _StatusMeta(color: Colors.red);
      case UserStatus.offline:
        return const _StatusMeta(color: Colors.grey);
    }
  }
}

class _SearchAvatarWithStatusDot extends StatelessWidget {
  const _SearchAvatarWithStatusDot({
    required this.dio,
    this.userId,
    required this.imageUrl,
    required this.statusColor,
  });

  final Dio dio;
  final String? userId;
  final String? imageUrl;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          VrcAvatar(imageUrl: imageUrl, dio: dio),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMeta {
  const _StatusMeta({required this.color});
  final Color color;
}
