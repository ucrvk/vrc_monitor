import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
// ignore: implementation_imports, depend_on_referenced_packages, unnecessary_import
import 'package:vrchat_dart_generated/src/model/mutual_friend.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/network/web_client.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/utils/location_utils.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendDetailPage extends StatefulWidget {
  const FriendDetailPage({super.key, required this.userId, this.api});

  static final Dio _fallbackDio = WebClient.publicDio;

  final String userId;
  final VrchatDartGenerated? api;

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
    try {
      final userStore = UserStore.instance;
      final imageCache = cache.CacheManager.instance.imageCache;
      final api = widget.api;

      User? user = userStore.getUser(widget.userId);
      FriendStatus? friendStatus;
      List<MutualFriend>? mutualFriends;

      if (user == null && api != null) {
        user = await userStore.loadUser(widget.userId, api);
      }

      friendStatus = userStore.getFriendStatus(widget.userId);
      if (friendStatus == null && api != null) {
        friendStatus = await userStore.loadFriendStatus(widget.userId, api);
      }

      mutualFriends = userStore.getMutualFriends(widget.userId);
      if (mutualFriends == null &&
          api != null &&
          (friendStatus?.isFriend ?? false)) {
        mutualFriends = await userStore.loadMutualFriends(widget.userId, api);
      }

      final isFriend = friendStatus?.isFriend ?? false;

      final eventLocation = userStore.getEventLocation(widget.userId);
      final locationText = await _resolveLocationText(
        status: user?.status ?? UserStatus.offline,
        eventLocation: eventLocation ?? user?.location,
        travelingToLocation: user?.travelingToLocation,
        api: api,
      );

      final favoriteGroups = userStore.getFavoriteGroups();
      final selectedGroupName = userStore.getFavoriteGroupForUser(
        widget.userId,
      );

      final dio = FriendDetailPage._fallbackDio;

      final avatarInfo = UserStore.instance.getAvatarInfo(widget.userId);
      final avatarFileId = UserStore.instance.getAvatarFileId(widget.userId);
      final cacheTasks = <Future<void>>[];

      if (avatarInfo != null) {
        final avatarSmall = avatarInfo.avatarSmallUrl;
        final headerSmall = avatarInfo.headerSmallUrl;

        if (avatarSmall != null && avatarSmall.isNotEmpty) {
          final fileId =
              avatarFileId ??
              cache.ImageCache.extractFileIdFromUrl(avatarSmall);
          if (fileId != null) {
            cacheTasks.add(
              imageCache.cacheByFileId(
                dio: dio,
                fileId: fileId,
                imageUrl: avatarSmall,
              ),
            );
          }
        }

        if (headerSmall != null &&
            headerSmall.isNotEmpty &&
            headerSmall != avatarInfo.avatarSmallUrl) {
          final fileId = cache.ImageCache.extractFileIdFromUrl(headerSmall);
          if (fileId != null) {
            cacheTasks.add(
              imageCache.cacheByFileId(
                dio: dio,
                fileId: fileId,
                imageUrl: headerSmall,
              ),
            );
          }
        }
      }

      await Future.wait(cacheTasks);

      return _DetailEnrichment(
        user: user,
        locationText: locationText,
        isFriend: isFriend,
        favoriteGroups: favoriteGroups
            .map(
              (g) =>
                  _FavoriteGroupView(name: g.name, displayName: g.displayName),
            )
            .toList(),
        selectedGroupName: selectedGroupName,
        mutualFriends: mutualFriends,
      );
    } catch (e) {
      debugPrint('Failed to enrich friend detail page: $e');
      return const _DetailEnrichment();
    }
  }

  Future<String?> _resolveLocationText({
    required UserStatus status,
    required String? eventLocation,
    String? travelingToLocation,
    required VrchatDartGenerated? api,
  }) async {
    if (status == UserStatus.offline) return null;

    final location = eventLocation?.trim() ?? '';
    if (location.isEmpty) return null;
    final lower = location.toLowerCase();

    if (lower == 'offline') return '在网页或其他端登录';
    if (lower.contains('private')) return '在私人房间';

    final eventWorldName = (() {
      final parsedTravelingTo = _parseLocation(
        travelingToLocation?.trim() ?? '',
      );
      final worldId = parsedTravelingTo?.worldId;
      if (worldId == null) return null;
      final worldName = WorldStore.instance.getWorldName(worldId);
      if (worldName == null || worldName.trim().isEmpty) return null;
      return worldName.trim();
    })();

    if (LocationUtils.isTraveling(location)) {
      if (eventWorldName != null && eventWorldName.isNotEmpty) {
        return '⟳ 正在前往 $eventWorldName';
      }
      return '⟳ 正在前往...';
    }

    final parsed = _parseLocation(location);
    if (parsed == null) return location;

    var base = location;
    final cachedWorldName = WorldStore.instance.getWorldName(parsed.worldId);
    if (cachedWorldName != null && cachedWorldName.trim().isNotEmpty) {
      base = cachedWorldName.trim();
    } else if (api != null) {
      try {
        final world = await WorldStore.instance.getOrFetch(parsed.worldId, api);
        final worldName = world?.name.trim() ?? '';
        if (worldName.isNotEmpty) {
          base = worldName;
        }
      } catch (e) {
        debugPrint('Failed to resolve world name: $e');
      }
    }

    final cachedType = cache
        .CacheManager
        .instance
        .memoryCache
        .instanceTypeByLocation[location];

    final locationWithLabel =
        (cachedType != null && cachedType.trim().isNotEmpty)
        ? '$base - ${cachedType.trim()}'
        : base;

    try {
      if (api != null && (cachedType == null || cachedType.trim().isEmpty)) {
        final (instanceSuccess, _) = await api
            .getWorldsApi()
            .getWorldInstance(
              worldId: parsed.worldId,
              instanceId: parsed.instanceId,
            )
            .validateVrc();
        final instance = instanceSuccess?.data;
        if (instance != null) {
          final typeLabel = _instanceTypeLabel(
            instance.type,
            canRequestInvite: instance.canRequestInvite ?? false,
          );
          if (typeLabel.isNotEmpty) {
            cache.CacheManager.instance.memoryCache.putInstanceType(
              location,
              typeLabel,
            );
            final result = '$base - $typeLabel';
            final regionEmoji = LocationUtils.getRegionEmoji(location);
            return regionEmoji != null ? '$regionEmoji $result' : result;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve world instance type: $e');
    }

    final regionEmoji = LocationUtils.getRegionEmoji(location);
    return regionEmoji != null
        ? '$regionEmoji $locationWithLabel'
        : locationWithLabel;
  }

  _ParsedLocation? _parseLocation(String location) {
    final value = location.trim();
    if (value.isEmpty || !value.contains(':')) return null;

    final firstColon = value.indexOf(':');
    final worldId = value.substring(0, firstColon);
    if (!worldId.startsWith('wrld_')) return null;

    final instanceId = value.substring(firstColon + 1);
    if (instanceId.isEmpty) return null;
    return _ParsedLocation(worldId: worldId, instanceId: instanceId);
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

  Future<void> _onMoreAction(
    _DetailMoreAction action,
    _DetailEnrichment enriched,
  ) async {
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
    final api = widget.api;
    if (api == null) {
      _showSnack('当前不可用：缺少 API 上下文');
      return;
    }
    final enriched = await _enrichmentFuture;
    final targetName = enriched.user?.displayName ?? widget.userId;

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
    final api = widget.api;
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
    final api = widget.api;
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
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    String? selected = enriched.selectedGroupName;

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
                    trailing: tempValue == null
                        ? const Icon(Icons.check)
                        : null,
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
        await api
            .getFavoritesApi()
            .removeFavorite(favoriteId: favoriteId)
            .validateVrc();
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
      UserStore.instance.setUserFavoriteGroup(widget.userId, selectedGroup);
      _showSnack('星标已更新');
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

  Future<List<String>> _loadFriendFavoriteRecordIds(
    VrchatDartGenerated api,
  ) async {
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DetailEnrichment>(
      future: _enrichmentFuture,
      builder: (context, snapshot) {
        final enriched = snapshot.data;
        final enrichedUser = enriched?.user;
        final isDetailReady = snapshot.connectionState == ConnectionState.done;

        final avatarInfo = UserStore.instance.getAvatarInfo(widget.userId);
        final resolvedAvatarUrl = avatarInfo?.avatarSmallUrl;
        final resolvedHeaderImageUrl = avatarInfo?.headerSmallUrl;
        final avatarFileId = UserStore.instance.getAvatarFileId(widget.userId);
        final headerFileId = UserStore.instance.getHeaderFileId(widget.userId);

        final userIcon = enrichedUser?.userIcon.trim();
        final profilePicOverride = enrichedUser?.profilePicOverride.trim();
        final currentAvatarImageUrl = enrichedUser?.currentAvatarImageUrl
            .trim();

        final resolvedDisplayName = enrichedUser?.displayName ?? widget.userId;
        final nameColor = UserStore.instance.trustColorForTags(
          enrichedUser?.tags ?? const [],
        );

        return _FriendDetailPageContent(
          userId: widget.userId,
          dio: FriendDetailPage._fallbackDio,
          displayName: resolvedDisplayName,
          avatarUrl: resolvedAvatarUrl,
          avatarFileId: avatarFileId,
          imageUrl: resolvedHeaderImageUrl,
          headerFileId: headerFileId,
          userIcon: userIcon?.isNotEmpty == true ? userIcon : null,
          profilePicOverride: profilePicOverride?.isNotEmpty == true
              ? profilePicOverride
              : null,
          currentAvatarImageUrl: currentAvatarImageUrl?.isNotEmpty == true
              ? currentAvatarImageUrl
              : null,
          locationText: snapshot.data?.locationText,
          bio: enrichedUser?.bio,
          nameColor: nameColor,
          status: enrichedUser?.status ?? UserStatus.offline,
          statusDescription: enrichedUser?.statusDescription,
          pronouns: enrichedUser?.pronouns,
          bioLinks: enrichedUser?.bioLinks ?? const [],
          dateJoined: enrichedUser?.dateJoined,
          lastActivity: enrichedUser?.lastActivity != null
              ? DateTime.tryParse(enrichedUser!.lastActivity)
              : null,
          mutualFriends: enriched?.mutualFriends,
          api: widget.api,
          appBarActions: [
            PopupMenuButton<_DetailMoreAction>(
              enabled: !_menuActionLoading && isDetailReady && enriched != null,
              onSelected: (action) =>
                  _onMoreAction(action, enriched ?? const _DetailEnrichment()),
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
    this.selectedGroupName,
    this.mutualFriends,
  });

  final User? user;
  final String? locationText;
  final bool isFriend;
  final List<_FavoriteGroupView> favoriteGroups;
  final String? selectedGroupName;
  final List<MutualFriend>? mutualFriends;
}

class _FavoriteGroupView {
  const _FavoriteGroupView({required this.name, required this.displayName});

  final String name;
  final String displayName;
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
  const _ParsedLocation({required this.worldId, required this.instanceId});

  final String worldId;
  final String instanceId;
}

class _FriendDetailPageContent extends StatelessWidget {
  const _FriendDetailPageContent({
    required this.userId,
    required this.dio,
    required this.displayName,
    this.avatarUrl,
    this.avatarFileId,
    this.imageUrl,
    this.headerFileId,
    this.userIcon,
    this.profilePicOverride,
    this.currentAvatarImageUrl,
    this.locationText,
    this.bio,
    this.nameColor,
    this.status = UserStatus.offline,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
    this.mutualFriends,
    this.api,
    this.appBarActions = const [],
  });

  final String userId;
  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? avatarFileId;
  final String? imageUrl;
  final String? headerFileId;
  final String? userIcon;
  final String? profilePicOverride;
  final String? currentAvatarImageUrl;
  final String? locationText;
  final String? bio;
  final Color? nameColor;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;
  final List<MutualFriend>? mutualFriends;
  final VrchatDartGenerated? api;
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
    final filteredMutualFriends = _visibleMutualFriends;
    final hiddenMutualCount = _hiddenMutualCount;
    final mutualTitle = hiddenMutualCount > 0
        ? '共同好友 (${filteredMutualFriends.length}) ($hiddenMutualCount个隐藏)'
        : '共同好友 (${filteredMutualFriends.length})';

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
              userId: userId,
              dio: dio,
              displayName: displayName,
              avatarUrl: avatarUrl,
              avatarFileId: avatarFileId,
              imageUrl: imageUrl,
              headerFileId: headerFileId,
              userIcon: userIcon,
              profilePicOverride: profilePicOverride,
              currentAvatarImageUrl: currentAvatarImageUrl,
              nameColor: nameColor,
              expandedHeight: expandedHeaderHeight,
              status: status,
              statusDescription: statusDescription,
              pronouns: pronouns,
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
                              await Clipboard.setData(
                                ClipboardData(text: bioText),
                              );
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
                                for (
                                  var i = 0;
                                  i < visibleLinks.length;
                                  i++
                                ) ...[
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
          if (filteredMutualFriends.isNotEmpty || hiddenMutualCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: Text(
                      mutualTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    childrenPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    children: [_buildMutualFriendsList(context)],
                  ),
                ),
              ),
            ),
        ],
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

  Widget _buildMutualFriendsList(BuildContext context) {
    final visibleMutualFriends = _visibleMutualFriends;
    if (visibleMutualFriends.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedFriends = [...visibleMutualFriends]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.75,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final friend in sortedFriends)
          GestureDetector(
            onTap: () => _openMutualFriendDetail(context, friend),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (_) {
                    final avatar = _resolveMutualFriendAvatar(friend);
                    return VrcAvatar(
                      dio: dio,
                      imageUrl: avatar.imageUrl,
                      fileId: avatar.fileId,
                      size: 44,
                    );
                  },
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    friend.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  ({String? imageUrl, String? fileId}) _resolveMutualFriendAvatar(
    MutualFriend friend,
  ) {
    final storeInfo = UserStore.instance.getAvatarInfo(friend.id);
    final storeUrl = storeInfo?.avatarSmallUrl;
    final storeFileId = UserStore.instance.getAvatarFileId(friend.id);
    if (storeUrl != null && storeUrl.trim().isNotEmpty) {
      return (imageUrl: storeUrl.trim(), fileId: storeFileId);
    }

    final profilePic = friend.profilePicOverride?.trim() ?? '';
    if (profilePic.isNotEmpty) {
      final imageUrl = cache.ImageCache.toSmallUrl(profilePic, isCustom: true);
      return (
        imageUrl: imageUrl,
        fileId: cache.ImageCache.extractFileIdFromUrl(imageUrl),
      );
    }

    final avatarThumb = friend.currentAvatarThumbnailImageUrl?.trim() ?? '';
    if (avatarThumb.isNotEmpty) {
      final imageUrl = cache.ImageCache.toSmallUrl(
        avatarThumb,
        isCustom: false,
      );
      return (
        imageUrl: imageUrl,
        fileId: cache.ImageCache.extractFileIdFromUrl(imageUrl),
      );
    }

    final fallbackThumb = friend.avatarThumbnail?.trim() ?? '';
    if (fallbackThumb.isNotEmpty) {
      final imageUrl = cache.ImageCache.toSmallUrl(
        fallbackThumb,
        isCustom: false,
      );
      return (
        imageUrl: imageUrl,
        fileId: cache.ImageCache.extractFileIdFromUrl(imageUrl),
      );
    }

    final avatarImg = friend.currentAvatarImageUrl.trim();
    if (avatarImg.isNotEmpty) {
      var fullUrl = avatarImg;
      if (fullUrl.contains('/image/') &&
          !fullUrl.endsWith('/file') &&
          !fullUrl.endsWith('/256')) {
        fullUrl = '$fullUrl/file';
      }
      final imageUrl = cache.ImageCache.toSmallUrl(fullUrl, isCustom: false);
      return (
        imageUrl: imageUrl,
        fileId: cache.ImageCache.extractFileIdFromUrl(imageUrl),
      );
    }

    final imageUrl = friend.imageUrl.trim();
    if (imageUrl.isNotEmpty) {
      return (
        imageUrl: imageUrl,
        fileId: cache.ImageCache.extractFileIdFromUrl(imageUrl),
      );
    }

    return (imageUrl: null, fileId: null);
  }

  List<MutualFriend> get _visibleMutualFriends {
    final list = mutualFriends;
    if (list == null || list.isEmpty) return const [];
    return list.where((friend) {
      final name = friend.displayName.trim().toLowerCase();
      return name != 'hidden mutual';
    }).toList();
  }

  int get _hiddenMutualCount {
    final list = mutualFriends;
    if (list == null || list.isEmpty) return 0;
    return list.where((friend) {
      final name = friend.displayName.trim().toLowerCase();
      return name == 'hidden mutual';
    }).length;
  }

  Future<void> _openMutualFriendDetail(
    BuildContext context,
    MutualFriend friend,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendDetailPage(userId: friend.id, api: api),
      ),
    );
  }
}

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({
    required this.userId,
    required this.dio,
    required this.displayName,
    required this.avatarUrl,
    this.avatarFileId,
    required this.imageUrl,
    this.headerFileId,
    this.userIcon,
    this.profilePicOverride,
    this.currentAvatarImageUrl,
    required this.nameColor,
    required this.expandedHeight,
    required this.status,
    required this.statusDescription,
    required this.pronouns,
  });

  final String userId;
  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? avatarFileId;
  final String? imageUrl;
  final String? headerFileId;
  final String? userIcon;
  final String? profilePicOverride;
  final String? currentAvatarImageUrl;
  final Color? nameColor;
  final double expandedHeight;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;

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
                    userId: userId,
                    dio: dio,
                    imageUrl: imageUrl,
                    fileId: headerFileId,
                    onTap: () => _openHeaderPreview(context),
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
                    onTap: () => _openAvatarPreview(context),
                    child: _TrustLevelAvatar(
                      userId: userId,
                      dio: dio,
                      imageUrl: avatarUrl,
                      fileId: avatarFileId,
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

  Future<void> _openAvatarPreview(BuildContext context) async {
    final hasUserIcon = userIcon != null && userIcon!.trim().isNotEmpty;
    final previewUrl = hasUserIcon
        ? userIcon!.trim()
        : (currentAvatarImageUrl?.trim() ?? '');

    if (previewUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有可预览的图片')));
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImagePreviewPage(
          dio: dio,
          imageUrl: previewUrl,
          title: '头像',
          useCache: hasUserIcon,
          fileId: hasUserIcon ? avatarFileId : null,
        ),
      ),
    );
  }

  Future<void> _openHeaderPreview(BuildContext context) async {
    final hasProfilePic =
        profilePicOverride != null && profilePicOverride!.trim().isNotEmpty;
    final previewUrl = hasProfilePic
        ? profilePicOverride!.trim()
        : (currentAvatarImageUrl?.trim() ?? '');

    if (previewUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有可预览的图片')));
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImagePreviewPage(
          dio: dio,
          imageUrl: previewUrl,
          title: '背景图',
          useCache: false,
        ),
      ),
    );
  }
}

class _TrustLevelAvatar extends StatelessWidget {
  const _TrustLevelAvatar({
    required this.userId,
    required this.dio,
    required this.imageUrl,
    this.fileId,
    required this.size,
  });

  final String userId;
  final Dio dio;
  final String? imageUrl;
  final String? fileId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    final resolvedFileId = fileId?.trim().isNotEmpty == true
        ? fileId!.trim()
        : cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (resolvedFileId == null || resolvedFileId.isEmpty) {
      return VrcAvatar(dio: dio, imageUrl: normalizedUrl, size: size);
    }

    Future.microtask(
      () => cache.CacheManager.instance.imageCache.cacheByFileId(
        dio: dio,
        fileId: resolvedFileId,
        imageUrl: normalizedUrl,
      ),
    );

    return FutureBuilder<Uint8List?>(
      future: cache.CacheManager.instance.imageCache.getByFileId(
        resolvedFileId,
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
          );
        }
        return VrcAvatar(dio: dio, imageUrl: normalizedUrl, size: size);
      },
    );
  }
}

class _HeaderImage extends StatefulWidget {
  const _HeaderImage({
    required this.userId,
    required this.dio,
    this.imageUrl,
    this.fileId,
    this.onTap,
  });

  final String userId;
  final Dio dio;
  final String? imageUrl;
  final String? fileId;
  final VoidCallback? onTap;

  @override
  State<_HeaderImage> createState() => _HeaderImageState();
}

class _HeaderImageState extends State<_HeaderImage> {
  Uint8List? _cachedBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_HeaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fileId != widget.fileId) {
      setState(() {
        _cachedBytes = null;
        _isLoading = true;
      });
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final normalizedUrl = widget.imageUrl?.trim();
    final resolvedFileId = widget.fileId?.trim().isNotEmpty == true
        ? widget.fileId!.trim()
        : cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (resolvedFileId == null ||
        resolvedFileId.isEmpty ||
        normalizedUrl == null ||
        normalizedUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _cachedBytes = null;
          _isLoading = false;
        });
      }
      return;
    }

    var bytes = await cache.CacheManager.instance.imageCache.getByFileId(
      resolvedFileId,
    );

    if (bytes != null && bytes.isNotEmpty) {
      if (mounted) {
        setState(() {
          _cachedBytes = bytes;
          _isLoading = false;
        });
      }
      return;
    }

    await cache.CacheManager.instance.imageCache.cacheByFileId(
      dio: widget.dio,
      fileId: resolvedFileId,
      imageUrl: normalizedUrl,
    );

    bytes = await cache.CacheManager.instance.imageCache.getByFileId(
      resolvedFileId,
    );

    if (mounted) {
      setState(() {
        _cachedBytes = bytes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = widget.imageUrl?.trim();
    final resolvedFileId = widget.fileId?.trim().isNotEmpty == true
        ? widget.fileId!.trim()
        : cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (_cachedBytes != null && _cachedBytes!.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Image.memory(_cachedBytes!, fit: BoxFit.cover),
      );
    }

    if (resolvedFileId == null ||
        resolvedFileId.isEmpty ||
        normalizedUrl == null ||
        normalizedUrl.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 40),
        ),
      );
    }

    if (_isLoading) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: VrcNetworkImage(
        dio: widget.dio,
        imageUrl: normalizedUrl,
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
    this.useCache = false,
    this.fileId,
  });

  final Dio dio;
  final String imageUrl;
  final String title;
  final bool useCache;
  final String? fileId;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late Future<Uint8List?> _imageFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadFullImage();
  }

  Future<Uint8List?> _loadFullImage() async {
    if (widget.useCache) {
      final imageCache = cache.CacheManager.instance.imageCache;
      final fileId =
          widget.fileId ??
          cache.ImageCache.extractFileIdFromUrl(widget.imageUrl);

      if (fileId != null && fileId.isNotEmpty) {
        final cached = await imageCache.getByFileId(fileId);
        if (cached != null && cached.isNotEmpty) return cached;
      }
    }

    return VrcNetworkImage.loadBytes(
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
      final bytes = await _imageFuture;
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
      ScaffoldMessenger.of(context).showSnackBar(
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
