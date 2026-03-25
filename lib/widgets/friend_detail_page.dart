import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/network/web_client.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendDetailPage extends StatefulWidget {
  const FriendDetailPage({
    super.key,
    this.dio,
    required this.userId,
    this.displayName = '',
    this.avatarUrl,
    this.imageUrl,
    this.location,
    this.isFriend,
    this.bio,
    this.nameColor,
    this.status = UserStatus.offline,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
    this.rawApi,
  });

  static final Dio _fallbackDio = WebClient.publicDio;

  final Dio? dio;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final String? location;
  final bool? isFriend;
  final String? bio;
  final Color? nameColor;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;
  final VrchatDartGenerated? rawApi;

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  late Future<_DetailEnrichment> _enrichmentFuture;
  bool _menuActionLoading = false;

  @override
  void initState() {
    super.initState();
    _enrichmentFuture = _fetchDetailEnrichment();
  }

  Future<_DetailEnrichment> _fetchDetailEnrichment() async {
    final api = widget.rawApi;
    User? user;
    FriendStatus? friendStatus;
    final needsUserFetch =
        api != null &&
        (widget.pronouns == null ||
            widget.dateJoined == null ||
            widget.location == null);

    if (needsUserFetch) {
      try {
        final (success, _) = await api
            .getUsersApi()
            .getUser(userId: widget.userId)
            .validateVrc();
        user = success?.data;
      } catch (e) {
        debugPrint('Failed to fetch user details: $e');
      }
    }

    if (api != null) {
      try {
        final (success, _) = await api
            .getFriendsApi()
            .getFriendStatus(userId: widget.userId)
            .validateVrc();
        friendStatus = success?.data;
      } catch (e) {
        debugPrint('Failed to fetch friend status: $e');
      }
    }

    final isFriend = friendStatus?.isFriend ?? widget.isFriend ?? false;

    final locationText = await _resolveLocationText(
      status: widget.status,
      rawLocation: user?.location ?? widget.location,
      api: api,
    );

    final favoriteGroups = <FavoriteGroup>[];
    final selectedGroupNames = <String>{};
    if (api != null && isFriend) {
      try {
        final (groupsSuccess, _) = await api
            .getFavoritesApi()
            .getFavoriteGroups(n: 100)
            .validateVrc();
        final groups = groupsSuccess?.data ?? const <FavoriteGroup>[];
        favoriteGroups.addAll(groups.where((g) => g.type == FavoriteType.friend));
      } catch (e) {
        debugPrint('Failed to fetch favorite groups: $e');
      }

      try {
        var offset = 0;
        const pageSize = 100;
        while (true) {
          final (favoritesSuccess, _) = await api
              .getFavoritesApi()
              .getFavorites(type: 'friend', n: pageSize, offset: offset)
              .validateVrc();
          final page = favoritesSuccess?.data ?? const <Favorite>[];
          for (final item in page) {
            if (item.favoriteId == widget.userId) {
              selectedGroupNames.addAll(item.tags);
            }
          }
          if (page.length < pageSize) break;
          offset += page.length;
        }
      } catch (e) {
        debugPrint('Failed to fetch favorite tags: $e');
      }
    }

    return _DetailEnrichment(
      user: user,
      locationText: locationText,
      isFriend: isFriend,
      favoriteGroups: favoriteGroups,
      selectedGroupNames: selectedGroupNames,
    );
  }

  Future<String?> _resolveLocationText({
    required UserStatus status,
    required String? rawLocation,
    required VrchatDartGenerated? api,
  }) async {
    if (status == UserStatus.offline) return null;

    final location = rawLocation?.trim() ?? '';
    if (location.isEmpty) return null;
    final lower = location.toLowerCase();

    if (lower == 'offline') return '在网页或其他端登录';
    if (lower.contains('private')) return '在私人房间';

    final parsed = _parseLocation(location);
    if (parsed == null || api == null) return location;

    String base = location;
    try {
      final (worldSuccess, _) = await api
          .getWorldsApi()
          .getWorld(worldId: parsed.worldId)
          .validateVrc();
      final worldName = worldSuccess?.data.name.trim() ?? '';
      if (worldName.isNotEmpty) {
        base = worldName;
      }
    } catch (e) {
      debugPrint('Failed to resolve world name: $e');
    }

    try {
      final (instanceSuccess, _) = await api
          .getWorldsApi()
          .getWorldInstance(worldId: parsed.worldId, instanceId: parsed.instanceId)
          .validateVrc();
      final instance = instanceSuccess?.data;
      if (instance == null) return base;

      final typeLabel = _instanceTypeLabel(
        instance.type,
        canRequestInvite: instance.canRequestInvite ?? false,
      );
      if (typeLabel.isEmpty) return base;
      return '$base - $typeLabel';
    } catch (e) {
      debugPrint('Failed to resolve world instance type: $e');
      return base;
    }
  }

  _ParsedLocation? _parseLocation(String location) {
    final value = location.trim();
    if (value.isEmpty || !value.contains(':')) return null;

    final firstColon = value.indexOf(':');
    final worldId = value.substring(0, firstColon);
    if (!worldId.startsWith('wrld_')) return null;

    final instanceId = value.substring(firstColon + 1);
    if (instanceId.isEmpty) return null;
    return _ParsedLocation(
      worldId: worldId,
      instanceId: instanceId,
    );
  }

  String _instanceTypeLabel(
    InstanceType type, {
    required bool canRequestInvite,
  }) {
    switch (type) {
      case InstanceType.friends:
        return 'Friends';
      case InstanceType.hidden:
        return 'Friends+';
      case InstanceType.private:
        return canRequestInvite ? 'Invite+' : 'Invite';
      case InstanceType.public:
        return 'Public';
      case InstanceType.group:
        return 'Group';
    }
  }

  Future<void> _onMoreAction(_DetailMoreAction action, _DetailEnrichment enriched) async {
    if (_menuActionLoading) return;
    switch (action) {
      case _DetailMoreAction.friendAction:
        if (enriched.isFriend) {
          await _deleteFriend();
        } else {
          await _sendFriendRequest();
        }
        break;
      case _DetailMoreAction.adjustFavorite:
        await _adjustFavoriteGroup(enriched);
        break;
    }
  }

  Future<void> _deleteFriend() async {
    final api = widget.rawApi;
    if (api == null) {
      _showSnack('当前不可用：缺少 API 上下文');
      return;
    }
    final targetName = widget.displayName.trim().isEmpty
        ? widget.userId
        : widget.displayName.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('高危操作提醒'),
        content: Text('您确定要删除$targetName吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _menuActionLoading = true;
    });
    try {
      final (success, failure) = await api
          .getFriendsApi()
          .unfriend(userId: widget.userId)
          .validateVrc();
      if (!mounted) return;
      if (success == null) {
        _showSnack('删除好友失败: ${failure?.error ?? '未知错误'}');
      } else {
        _showSnack('已删除好友');
        setState(() {
          _enrichmentFuture = _fetchDetailEnrichment();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _menuActionLoading = false;
        });
      }
    }
  }

  Future<void> _sendFriendRequest() async {
    final api = widget.rawApi;
    if (api == null) {
      _showSnack('当前不可用：缺少 API 上下文');
      return;
    }

    setState(() {
      _menuActionLoading = true;
    });
    try {
      final (success, failure) = await api
          .getFriendsApi()
          .friend(userId: widget.userId)
          .validateVrc();
      if (!mounted) return;
      if (success == null) {
        _showSnack('申请好友失败: ${failure?.error ?? '未知错误'}');
      } else {
        _showSnack('好友申请已发送');
        setState(() {
          _enrichmentFuture = _fetchDetailEnrichment();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _menuActionLoading = false;
        });
      }
    }
  }

  Future<void> _adjustFavoriteGroup(_DetailEnrichment enriched) async {
    final api = widget.rawApi;
    if (api == null) {
      _showSnack('当前不可用：缺少 API 上下文');
      return;
    }
    if (!enriched.isFriend) {
      _showSnack('非好友无法调整星标');
      return;
    }

    final friendGroups = enriched.favoriteGroups;
    if (friendGroups.isEmpty) {
      _showSnack('暂无可用的好友星标分组');
      return;
    }

    final sortedGroups = [...friendGroups]
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    String? selected = enriched.selectedGroupNames.isEmpty
        ? null
        : enriched.selectedGroupNames.first;

    final selectedResult = await showDialog<_FavoriteDialogResult>(
      context: context,
      builder: (context) {
        String? tempValue = selected;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('调整星标'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('不星标'),
                    trailing: tempValue == null ? const Icon(Icons.check) : null,
                    onTap: () => setDialogState(() => tempValue = null),
                  ),
                  for (final group in sortedGroups)
                    ListTile(
                      title: Text(group.displayName),
                      subtitle: Text(group.name),
                      trailing: tempValue == group.name
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => setDialogState(() => tempValue = group.name),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _FavoriteDialogResult.cancel()),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_FavoriteDialogResult.submit(tempValue)),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedResult == null || !selectedResult.submitted) return;
    final selectedGroup = selectedResult.groupName;

    setState(() {
      _menuActionLoading = true;
    });
    try {
      final existingFavoriteIds = await _loadFriendFavoriteRecordIds(api);
      for (final favoriteId in existingFavoriteIds) {
        await api.getFavoritesApi().removeFavorite(favoriteId: favoriteId).validateVrc();
      }

      if (selectedGroup != null) {
        await api
            .getFavoritesApi()
            .addFavorite(
              addFavoriteRequest: AddFavoriteRequest(
                favoriteId: widget.userId,
                tags: [selectedGroup],
                type: FavoriteType.friend,
              ),
            )
            .validateVrc();
      }

      if (!mounted) return;
      _showSnack('星标已更新');
      setState(() {
        _enrichmentFuture = _fetchDetailEnrichment();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('调整星标失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _menuActionLoading = false;
        });
      }
    }
  }

  Future<List<String>> _loadFriendFavoriteRecordIds(VrchatDartGenerated api) async {
    final ids = <String>[];
    var offset = 0;
    const pageSize = 100;
    while (true) {
      final (success, _) = await api
          .getFavoritesApi()
          .getFavorites(type: 'friend', n: pageSize, offset: offset)
          .validateVrc();
      final page = success?.data ?? const <Favorite>[];
      for (final item in page) {
        if (item.favoriteId == widget.userId) {
          ids.add(item.id);
        }
      }
      if (page.length < pageSize) break;
      offset += page.length;
    }
    return ids;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DetailEnrichment>(
      future: _enrichmentFuture,
      builder: (context, snapshot) {
        final enriched = snapshot.data;
        final enrichedUser = enriched?.user;
        return _FriendDetailPageContent(
          dio: widget.dio ?? FriendDetailPage._fallbackDio,
          displayName: widget.displayName,
          avatarUrl: widget.avatarUrl,
          imageUrl: widget.imageUrl,
          locationText: snapshot.data?.locationText,
          bio: widget.bio,
          nameColor: widget.nameColor,
          status: widget.status,
          statusDescription: widget.statusDescription,
          pronouns: enrichedUser?.pronouns ?? widget.pronouns,
          bioLinks: enrichedUser?.bioLinks ?? widget.bioLinks,
          dateJoined: enrichedUser?.dateJoined ?? widget.dateJoined,
          lastActivity:
              (enrichedUser?.lastActivity != null
                  ? DateTime.tryParse(enrichedUser!.lastActivity)
                  : null) ??
              widget.lastActivity,
          appBarActions: [
            PopupMenuButton<_DetailMoreAction>(
              enabled: !_menuActionLoading,
              onSelected: (action) => _onMoreAction(action, enriched ?? const _DetailEnrichment()),
              itemBuilder: (_) => [
                PopupMenuItem<_DetailMoreAction>(
                  value: _DetailMoreAction.friendAction,
                  child: Text((enriched?.isFriend ?? false) ? '删除好友' : '申请好友'),
                ),
                if (enriched?.isFriend ?? false)
                  const PopupMenuItem<_DetailMoreAction>(
                    value: _DetailMoreAction.adjustFavorite,
                    child: Text('调整星标'),
                  ),
              ],
              icon: _menuActionLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_vert),
            ),
          ],
        );
      },
    );
  }
}

class _DetailEnrichment {
  const _DetailEnrichment({
    this.user,
    this.locationText,
    this.isFriend = false,
    this.favoriteGroups = const [],
    this.selectedGroupNames = const <String>{},
  });

  final User? user;
  final String? locationText;
  final bool isFriend;
  final List<FavoriteGroup> favoriteGroups;
  final Set<String> selectedGroupNames;
}

enum _DetailMoreAction { friendAction, adjustFavorite }

class _FavoriteDialogResult {
  const _FavoriteDialogResult._({required this.submitted, this.groupName});

  const _FavoriteDialogResult.cancel() : this._(submitted: false);

  const _FavoriteDialogResult.submit(String? groupName)
    : this._(submitted: true, groupName: groupName);

  final bool submitted;
  final String? groupName;
}

class _ParsedLocation {
  const _ParsedLocation({
    required this.worldId,
    required this.instanceId,
  });

  final String worldId;
  final String instanceId;
}

class _FriendDetailPageContent extends StatelessWidget {
  const _FriendDetailPageContent({
    required this.dio,
    required this.displayName,
    this.avatarUrl,
    this.imageUrl,
    this.locationText,
    this.bio,
    this.nameColor,
    this.status = UserStatus.offline,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
    this.appBarActions = const [],
  });

  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final String? locationText;
  final String? bio;
  final Color? nameColor;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;
  final List<Widget> appBarActions;

  @override
  Widget build(BuildContext context) {
    const expandedHeaderHeight = 260.0;
    final bioText = (bio == null || bio!.trim().isEmpty)
        ? '暂无个人介绍'
        : bio!.trim();
    final normalizedLocationText = locationText?.trim() ?? '';
    final showLocation =
        status != UserStatus.offline && normalizedLocationText.isNotEmpty;
    final visibleLinks = _sanitizeBioLinks(bioLinks).take(3).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: expandedHeaderHeight,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            actions: appBarActions,
            flexibleSpace: _CollapsingHeader(
              dio: dio,
              displayName: displayName,
              avatarUrl: avatarUrl,
              imageUrl: imageUrl,
              nameColor: nameColor,
              expandedHeight: expandedHeaderHeight,
              status: status,
              statusDescription: statusDescription,
              pronouns: pronouns,
              onAvatarTap: () =>
                  _openImagePreview(context, imageUrl: avatarUrl, title: '头像'),
              onHeaderTap: () =>
                  _openImagePreview(context, imageUrl: imageUrl, title: '背景图'),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  if (showLocation)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('当前位置：$normalizedLocationText'),
                        ),
                      ),
                    ),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      title: Text(
                        '个人介绍',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () async {
                              await Clipboard.setData(ClipboardData(text: bioText));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('个人介绍已复制')),
                                );
                              }
                            },
                            child: Text(bioText),
                          ),
                        ),
                        if (visibleLinks.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '个人链接',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0; i < visibleLinks.length; i++) ...[
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _openBioLink(context, visibleLinks[i]),
                                    child: Text(_hostLabel(visibleLinks[i])),
                                  ),
                                  if (i != visibleLinks.length - 1)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('加入时间'),
                      trailing: Text(_formatJoinedDate(dateJoined)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('上次在线'),
                      trailing: Text(_formatLastActivity(lastActivity)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openImagePreview(
    BuildContext context, {
    required String? imageUrl,
    required String title,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可预览的图片')));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ImagePreviewPage(dio: dio, imageUrl: url, title: title),
      ),
    );
  }

  static List<String> _sanitizeBioLinks(List<String> rawLinks) {
    final unique = <String>{};
    for (final raw in rawLinks) {
      final uri = _normalizeUri(raw);
      if (uri != null) {
        unique.add(uri.toString());
      }
    }
    return unique.toList();
  }

  static Uri? _normalizeUri(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static String _hostLabel(String url) {
    final uri = _normalizeUri(url);
    if (uri == null) return url;
    final host = uri.host.toLowerCase();
    if (host.startsWith('www.')) return host.substring(4);
    return host;
  }

  static Future<void> _openBioLink(BuildContext context, String url) async {
    final uri = _normalizeUri(url);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开该链接')));
    }
  }

  static String _formatJoinedDate(DateTime? value) {
    if (value == null) return '未知';
    final local = value.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }

  static String _formatLastActivity(DateTime? value) {
    if (value == null) return '未知';

    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({
    required this.dio,
    required this.displayName,
    required this.avatarUrl,
    required this.imageUrl,
    required this.nameColor,
    required this.expandedHeight,
    required this.status,
    required this.statusDescription,
    required this.pronouns,
    required this.onAvatarTap,
    required this.onHeaderTap,
  });

  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final Color? nameColor;
  final double expandedHeight;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final VoidCallback onAvatarTap;
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final minHeight = topPadding + kToolbarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentHeight = constraints.biggest.height;
        final maxScrollExtent = expandedHeight - minHeight;
        final collapseRatio = maxScrollExtent <= 0
            ? 1.0
            : ((expandedHeight - currentHeight) / maxScrollExtent).clamp(
                0.0,
                1.0,
              );

        final avatarSize = lerpDouble(56, 30, collapseRatio)!;
        final left = lerpDouble(16, 56, collapseRatio)!;
        final expandedTop = currentHeight - avatarSize - 24;
        final collapsedTop = topPadding + (kToolbarHeight - avatarSize) / 2;
        final top = lerpDouble(expandedTop, collapsedTop, collapseRatio)!;
        final nameSize = lerpDouble(26, 18, collapseRatio)!;
        final imageOpacity = (1 - collapseRatio * 1.4).clamp(0.0, 1.0);

        final statusMeta = _statusMeta(status, statusDescription);
        final collapsedNameColor = Theme.of(context).colorScheme.onSurface;
        final collapsedSubColor = Theme.of(
          context,
        ).colorScheme.onSurfaceVariant;
        final mergedNameColor = Color.lerp(
          nameColor ?? Colors.white,
          collapsedNameColor,
          collapseRatio,
        );
        final mergedSubColor = Color.lerp(
          Colors.white70,
          collapsedSubColor,
          collapseRatio,
        );
        final pronounsText = pronouns?.trim();

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Theme.of(context).colorScheme.surface),
            if (imageOpacity > 0)
              Positioned.fill(
                top: minHeight,
                child: Opacity(
                  opacity: imageOpacity,
                  child: _HeaderImage(
                    dio: dio,
                    imageUrl: imageUrl,
                    onTap: onHeaderTap,
                  ),
                ),
              ),
            if (imageOpacity > 0)
              Positioned.fill(
                top: minHeight,
                child: Opacity(
                  opacity: imageOpacity,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: left,
              right: 16,
              top: top,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: VrcAvatar(
                      dio: dio,
                      imageUrl: avatarUrl,
                      size: avatarSize,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mergedNameColor,
                            fontSize: nameSize,
                            fontWeight: FontWeight.w700,
                            shadows: imageOpacity > 0
                                ? const [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : const [],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusMeta.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusMeta.color,
                            fontWeight: FontWeight.w600,
                            fontSize: lerpDouble(12, 13, collapseRatio),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pronounsText != null &&
                      pronounsText.isNotEmpty &&
                      imageOpacity > 0) ...[
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: imageOpacity,
                      child: Text(
                        pronounsText,
                        style: TextStyle(
                          color: mergedSubColor,
                          fontWeight: FontWeight.w500,
                          fontSize: lerpDouble(12, 13, collapseRatio),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  _StatusMeta _statusMeta(UserStatus status, String? description) {
    final desc = description?.trim();
    final label = (desc != null && desc.isNotEmpty)
        ? desc
        : _fallbackStatusLabel(status);
    final color = switch (status) {
      UserStatus.joinMe => Colors.blue,
      UserStatus.active => Colors.green,
      UserStatus.askMe => Colors.orange,
      UserStatus.busy => Colors.red,
      UserStatus.offline => Colors.grey,
    };
    return _StatusMeta(label: label, color: color);
  }

  String _fallbackStatusLabel(UserStatus status) {
    return switch (status) {
      UserStatus.active => 'online',
      UserStatus.joinMe => 'joinMe',
      UserStatus.askMe => 'askMe',
      UserStatus.busy => 'noDisturb',
      UserStatus.offline => 'offline',
    };
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage({required this.dio, this.imageUrl, this.onTap});

  final Dio dio;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 40),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: VrcNetworkImage(
        dio: dio,
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        errorWidget: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({
    required this.dio,
    required this.imageUrl,
    required this.title,
  });

  final Dio dio;
  final String imageUrl;
  final String title;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late Future<Uint8List?> _imageFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _imageFuture = VrcNetworkImage.loadBytes(
      dio: widget.dio,
      imageUrl: widget.imageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveImage,
            tooltip: '保存图片',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Center(child: Text('图片加载失败'));
          }

          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: Image.memory(bytes)),
          );
        },
      ),
    );
  }

  Future<void> _saveImage() async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await VrcNetworkImage.loadBytes(
        dio: widget.dio,
        imageUrl: widget.imageUrl,
      );
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败：图片为空')));
        return;
      }

      final ext = _guessExt(widget.imageUrl);
      final fileName = 'vrc_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
        name: fileName,
      );
      final map = (result is Map)
          ? result.map((key, value) => MapEntry('$key', value))
          : <String, dynamic>{};
      final isSuccess = map['isSuccess'] == true || map['success'] == true;
      final savedPath = (map['filePath'] ?? map['path'] ?? '').toString();
      if (!isSuccess) {
        throw Exception(map['errorMessage']?.toString() ?? '写入 Pictures 失败');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            savedPath.isEmpty ? '图片已保存到 Pictures' : '图片已保存到: $savedPath',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _guessExt(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpg';
  }
}

class _StatusMeta {
  const _StatusMeta({required this.label, required this.color});

  final String label;
  final Color color;
}
