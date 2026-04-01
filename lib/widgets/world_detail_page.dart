import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class WorldDetailPage extends StatefulWidget {
  const WorldDetailPage({
    super.key,
    required this.api,
    required this.worldId,
    required this.instanceId,
  });

  final VrchatDartGenerated api;
  final String worldId;
  final String instanceId;

  @override
  State<WorldDetailPage> createState() => _WorldDetailPageState();
}

class _WorldDetailPageState extends State<WorldDetailPage> {
  final UserStore _userStore = UserStore.instance;
  final WorldStore _worldStore = WorldStore.instance;
  final cache.CacheManager _cacheManager = cache.CacheManager.instance;

  late Future<_WorldDetailData> _detailFuture;
  bool _inviteLoading = false;

  String get _fullInstanceId => widget.instanceId.trim();
  String get _roomKey => '${widget.worldId}:$_fullInstanceId';

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<_WorldDetailData> _loadDetail() async {
    await _worldStore.initialize();

    World? world =
        _worldStore.getWorld(widget.worldId) ??
        await _worldStore.getOrFetch(widget.worldId, widget.api);

    final imageUrl = world?.imageUrl.trim() ?? '';
    if (imageUrl.isNotEmpty) {
      unawaited(
        _cacheManager.imageCache.cacheWorldImage(
          dio: widget.api.dio,
          imageUrl: imageUrl,
        ),
      );
    }

    Instance? instance;
    String? errorMessage;
    try {
      final (success, failure) = await widget.api
          .getInstancesApi()
          .getInstance(worldId: widget.worldId, instanceId: _fullInstanceId)
          .validateVrc();
      instance = success?.data;
      final ownerUserId = _instanceOwnerUserId(instance);
      if (ownerUserId != null && _userStore.getUser(ownerUserId) == null) {
        unawaited(_userStore.loadUser(ownerUserId, widget.api));
      }
      if (instance == null && failure != null) {
        errorMessage = failure.error.toString();
      }
    } catch (e) {
      errorMessage = e.toString();
    }

    return _WorldDetailData(
      world: world,
      instance: instance,
      errorMessage: errorMessage,
    );
  }

  Future<void> _retryLoad() async {
    setState(() {
      _detailFuture = _loadDetail();
    });
  }

  Future<void> _inviteMyself() async {
    if (_inviteLoading) return;
    setState(() {
      _inviteLoading = true;
    });

    try {
      final (success, failure) = await widget.api
          .getInviteApi()
          .inviteMyselfTo(worldId: widget.worldId, instanceId: _fullInstanceId)
          .validateVrc();
      if (!mounted) return;
      if (success == null) {
        final message = failure?.error ?? '鏈煡閿欒';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('閭€璇峰け璐? $message')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('邀请已发送')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('閭€璇峰け璐? $e')));
    } finally {
      if (mounted) {
        setState(() {
          _inviteLoading = false;
        });
      }
    }
  }

  List<User> _buildRoomFriends() {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    final friends = <User>[];
    for (final friend in onlineFriends) {
      final location =
          (_userStore.getEventLocation(friend.id) ?? friend.location)?.trim();
      final parsed = cache.CacheManager.parseLocation(location);
      if (parsed == null) continue;
      final key = '${parsed.worldId}:${parsed.instanceId.trim()}';
      if (key != _roomKey) continue;
      friends.add(friend);
    }

    friends.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return friends;
  }

  Future<void> _openFriendDetailPage(String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendDetailPage(userId: userId, api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_userStore, _worldStore]),
      builder: (context, child) {
        return FutureBuilder<_WorldDetailData>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final detail = snapshot.data ?? const _WorldDetailData();
            final world = detail.world ?? _worldStore.getWorld(widget.worldId);
            final instance = detail.instance;
            final roomFriends = _buildRoomFriends();

            final worldName = (world?.name.trim().isNotEmpty ?? false)
                ? world!.name.trim()
                : widget.worldId;
            final roomTypeLabel = _instanceTypeLabel(instance);
            final roomRegionEmoji = _instanceRegionEmoji(instance);
            final actualRoomId = (instance?.displayName?.isNotEmpty ?? false)
                ? instance!.displayName!
                : instance!.name;
            final ownerUserId = _instanceOwnerUserId(instance);
            final ownerName = _resolveOwnerName(ownerUserId);
            final description = world?.description.trim() ?? '';
            final currentUsers = instance.nUsers;
            final totalUsers = instance.capacity ?? world?.capacity;

            return Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 220,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      background: _WorldBanner(
                        dio: widget.api.dio,
                        imageUrl: world?.imageUrl,
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedHeaderDelegate(
                      minHeight: 82,
                      maxHeight: 82,
                      child: Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      worldName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$roomRegionEmoji $roomTypeLabel  #$actualRoomId',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    if (ownerName != null) ...[
                                      const SizedBox(height: 2),
                                      if (ownerUserId != null)
                                        InkWell(
                                          onTap: () => _openFriendDetailPage(
                                            ownerUserId,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Text.rich(
                                              TextSpan(
                                                text: '房主: ',
                                                children: [
                                                  TextSpan(
                                                    text: ownerName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ),
                                        )
                                      else
                                        Text.rich(
                                          TextSpan(
                                            text: '房主: ',
                                            children: [
                                              TextSpan(
                                                text: ownerName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (detail.errorMessage != null &&
                              detail.errorMessage!.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Instance load failed: ${detail.errorMessage}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _retryLoad,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '房间人数: ${currentUsers.toString()}/${totalUsers?.toString() ?? '--'} (${roomFriends.length})',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _inviteLoading
                                    ? null
                                    : _inviteMyself,
                                icon: _inviteLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send, size: 16),
                                label: const Text('邀请自己'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Card(
                            margin: EdgeInsets.zero,
                            child: ExpansionTile(
                              title: const Text('房间介绍'),
                              initiallyExpanded: false,
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    description.isEmpty
                                        ? 'No description'
                                        : description,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '房间内好友',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          if (roomFriends.isEmpty)
                            Text(
                              'No friends in this room right now',
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.78,
                                  ),
                              itemCount: roomFriends.length,
                              itemBuilder: (context, index) {
                                final friend = roomFriends[index];
                                return _RoomFriendTile(
                                  user: friend,
                                  dio: widget.api.dio,
                                  onTap: () => _openFriendDetailPage(friend.id),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _instanceTypeLabel(Instance? instance) {
    if (instance == null) return '--';
    return cache.CacheManager.instanceTypeLabel(
      instance.type,
      canRequestInvite: instance.canRequestInvite ?? false,
    );
  }

  String _instanceRegionEmoji(Instance? instance) {
  final regionCode =
      (instance?.region.name ?? instance?.photonRegion.name ?? '')
          .toLowerCase();

  switch (regionCode) {
    case 'jp':
      return '🇯🇵';
    case 'eu':
      return '🇪🇺'; // 或者用 🇪🇺（欧盟）
    case 'us':
    case 'use': // US East
    case 'usw': // US West
    case 'usx': // 其他 US
      return '🇺🇸';
    default:
      return '🌍';
  }
}

  String? _instanceOwnerUserId(Instance? instance) {
    final ownerId = instance?.ownerId?.trim() ?? '';
    if (ownerId.startsWith('usr_')) {
      return ownerId;
    }
    return null;
  }

  String? _resolveOwnerName(String? ownerUserId) {
    if (ownerUserId == null || ownerUserId.isEmpty) return null;
    final user = _userStore.getUser(ownerUserId);
    if (user != null) return user.displayName;
    final limited = _userStore.getLimitedUser(ownerUserId);
    if (limited != null) return limited.displayName;
    return ownerUserId;
  }
}

class _WorldBanner extends StatelessWidget {
  const _WorldBanner({required this.dio, required this.imageUrl});

  final Dio dio;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final normalized = imageUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.public, size: 52)),
      );
    }
    return VrcNetworkImage(
      dio: dio,
      imageUrl: normalized,
      fit: BoxFit.cover,
      placeholder: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 34)),
      ),
    );
  }
}

class _RoomFriendTile extends StatelessWidget {
  const _RoomFriendTile({
    required this.user,
    required this.dio,
    required this.onTap,
  });

  final User user;
  final Dio dio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarInfo = UserStore.instance.getAvatarInfo(user.id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VrcAvatar(
            dio: dio,
            imageUrl: avatarInfo?.avatarSmallUrl,
            fileId: UserStore.instance.getAvatarFileId(user.id),
            size: 42,
          ),
          const SizedBox(height: 6),
          Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.child != child;
  }
}

class _WorldDetailData {
  const _WorldDetailData({this.world, this.instance, this.errorMessage});

  final World? world;
  final Instance? instance;
  final String? errorMessage;
}
