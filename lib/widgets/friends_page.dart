import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/utils/location_utils.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';
import 'package:vrc_monitor/widgets/friend_search_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.api, required this.currentUser});

  final VrchatDart api;
  final CurrentUser currentUser;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final cache.CacheManager _cacheManager = cache.CacheManager.instance;
  final UserStore _userStore = UserStore.instance;

  final Map<String, String> _worldNameById = {};
  final Map<String, String> _instanceTypeByLocation = {};
  final Set<String> _worldIdsInFlight = <String>{};
  final Set<String> _instanceLocationsInFlight = <String>{};
  Timer? _refreshCooldownTimer;
  int _refreshCooldownSeconds = 0;
  bool _onlineExpanded = true;
  bool _webExpanded = true;
  bool _offlineExpanded = false;
  List<_FavoriteFriendGroupView> _favoriteFriendGroups = const [];
  final Map<String, bool> _favoriteGroupExpandedByName = {};

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateFromCache());
    _userStore.addListener(_handleUserStoreChanged);
    _buildFavoriteGroupsFromStore();
  }

  void _buildFavoriteGroupsFromStore() {
    final groups = _userStore.getFavoriteGroups();
    final userFavoriteGroup = <String, String>{};
    for (final entry in _userStore.getFavoriteFriendIds()) {
      final groupName = _userStore.getFavoriteGroupForUser(entry);
      if (groupName != null) {
        userFavoriteGroup[entry] = groupName;
      }
    }

    final friendIdsByGroupName = <String, Set<String>>{};
    for (final group in groups) {
      friendIdsByGroupName[group.name] = <String>{};
    }
    for (final entry in userFavoriteGroup.entries) {
      final set = friendIdsByGroupName[entry.value];
      if (set != null) {
        set.add(entry.key);
      }
    }

    setState(() {
      _favoriteFriendGroups = groups
          .map(
            (g) => _FavoriteFriendGroupView(
              name: g.name,
              displayName: g.displayName,
              friendIds: friendIdsByGroupName[g.name] ?? const {},
            ),
          )
          .toList();
    });
    _syncFavoriteGroupExpansionState(_favoriteFriendGroups);
  }

  @override
  void dispose() {
    _refreshCooldownTimer?.cancel();
    _userStore.removeListener(_handleUserStoreChanged);
    super.dispose();
  }

  Future<void> _hydrateFromCache() async {
    await _cacheManager.worldNameCache.load();
    if (!mounted) return;

    setState(() {
      _worldNameById
        ..clear()
        ..addAll(_cacheManager.worldNameCache.worldNameById);
      _instanceTypeByLocation
        ..clear()
        ..addAll(_cacheManager.memoryCache.instanceTypeByLocation);
    });

    unawaited(_resolveLocationsForOnlineFriends());
  }

  void _syncFavoriteGroupExpansionState(List<_FavoriteFriendGroupView> groups) {
    final nextKeys = groups.map((g) => g.name).toSet();
    _favoriteGroupExpandedByName.removeWhere(
      (key, _) => !nextKeys.contains(key),
    );
    for (final group in groups) {
      _favoriteGroupExpandedByName.putIfAbsent(group.name, () => true);
    }
  }

  Future<(T?, InvalidResponse?)> _runVrcRequest<T>(
    Future<(T?, InvalidResponse?)> Function() request, {
    int maxAttempts = 2,
  }) async {
    var attempt = 0;
    InvalidResponse? lastFailure;

    while (attempt < maxAttempts) {
      attempt += 1;
      final (success, failure) = await request();
      if (success != null) {
        return (success, null);
      }

      lastFailure = failure;
      if (failure == null || !_isRetryableFailure(failure)) {
        return (null, failure);
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: attempt * 300));
      }
    }

    return (null, lastFailure);
  }

  bool _isRetryableFailure(InvalidResponse failure) {
    final error = failure.error;
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return true;
      }
    }

    final status = failure.response?.statusCode;
    if (status == null) return false;
    return status == 429 || status >= 500;
  }

  void _handleUserStoreChanged() {
    unawaited(_resolveLocationsForOnlineFriends());
  }

  Future<void> _resolveLocationsForOnlineFriends() async {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    final Set<String> worldIdsToFetch = <String>{};
    final List<(String, String, String)> worldInstancesToFetch = [];
    var anyImmediateUiChange = false;

    for (final friend in onlineFriends) {
      final location = friend.location?.trim() ?? '';

      if (LocationUtils.isTraveling(location)) {
        final travelingTo = friend.travelingToLocation?.trim() ?? '';
        final parsed = cache.CacheManager.parseLocation(travelingTo);
        final worldId = parsed?.worldId;
        if (worldId != null) {
          final cached = _cacheManager.worldNameCache.worldName(worldId);
          if (cached != null && cached.isNotEmpty) {
            if (_worldNameById[worldId] != cached) {
              _worldNameById[worldId] = cached;
              anyImmediateUiChange = true;
            }
          } else if (!_worldNameById.containsKey(worldId) &&
              !_worldIdsInFlight.contains(worldId)) {
            worldIdsToFetch.add(worldId);
            _worldIdsInFlight.add(worldId);
          }
        }
        continue;
      }

      final parsed = cache.CacheManager.parseLocation(location);
      final worldId = parsed?.worldId;
      if (worldId != null) {
        final cached = _cacheManager.worldNameCache.worldName(worldId);
        if (cached != null && cached.isNotEmpty) {
          if (_worldNameById[worldId] != cached) {
            _worldNameById[worldId] = cached;
            anyImmediateUiChange = true;
          }
        } else if (!_worldNameById.containsKey(worldId)) {
          if (!_worldIdsInFlight.contains(worldId)) {
            worldIdsToFetch.add(worldId);
            _worldIdsInFlight.add(worldId);
          }
        }
      }
      if (parsed != null &&
          !_instanceTypeByLocation.containsKey(parsed.rawLocation) &&
          !_instanceLocationsInFlight.contains(parsed.rawLocation)) {
        worldInstancesToFetch.add((
          parsed.rawLocation,
          parsed.worldId,
          parsed.instanceId,
        ));
        _instanceLocationsInFlight.add(parsed.rawLocation);
      }
    }

    if (anyImmediateUiChange && mounted) {
      setState(() {});
    }

    if (worldIdsToFetch.isEmpty && worldInstancesToFetch.isEmpty) return;

    final tasks = <Future<void>>[];
    var instanceCacheDirty = false;

    for (final worldId in worldIdsToFetch) {
      tasks.add(() async {
        try {
          final (success, _) = await _runVrcRequest(
            () => widget.api.rawApi
                .getWorldsApi()
                .getWorld(worldId: worldId)
                .validateVrc(),
          );

          final next = success?.data.name ?? worldId;
          if (_worldNameById[worldId] != next) {
            _worldNameById[worldId] = next;
            if (mounted) {
              setState(() {});
            }
          }
          if (success != null && success.data.name.isNotEmpty) {
            unawaited(
              _cacheManager.worldNameCache.putWorldName(
                worldId,
                success.data.name,
              ),
            );
          }
        } finally {
          _worldIdsInFlight.remove(worldId);
        }
      }());
    }

    for (final (raw, worldId, instanceId) in worldInstancesToFetch) {
      tasks.add(() async {
        try {
          final (success, _) = await _runVrcRequest(
            () => widget.api.rawApi
                .getWorldsApi()
                .getWorldInstance(worldId: worldId, instanceId: instanceId)
                .validateVrc(),
          );
          if (success == null) return;

          final typeLabel = cache.CacheManager.instanceTypeLabel(
            success.data.type,
            canRequestInvite: success.data.canRequestInvite ?? false,
          );
          if (_instanceTypeByLocation[raw] != typeLabel) {
            _instanceTypeByLocation[raw] = typeLabel;
            instanceCacheDirty = true;
            if (mounted) {
              setState(() {});
            }
          }
        } finally {
          _instanceLocationsInFlight.remove(raw);
        }
      }());
    }

    await Future.wait(tasks);
    if (instanceCacheDirty) {
      _cacheManager.memoryCache.setInstanceTypeByLocation(
        _instanceTypeByLocation,
      );
    }
  }

  int _statusPriority(UserStatus status) {
    switch (status) {
      case UserStatus.joinMe:
        return 0;
      case UserStatus.active:
        return 1;
      case UserStatus.askMe:
        return 2;
      case UserStatus.busy:
        return 3;
      case UserStatus.offline:
        return 4;
    }
  }

  int _onlineFavoritePriority(String friendId) {
    for (var i = 0; i < _favoriteFriendGroups.length; i++) {
      if (_favoriteFriendGroups[i].friendIds.contains(friendId)) {
        return i;
      }
    }
    return _favoriteFriendGroups.length + 1;
  }

  String _locationTextFor(User friend) {
    final eventLocation = _userStore.getEventLocation(friend.id);
    final eventWorldName = (() {
      final travelingTo = friend.travelingToLocation?.trim() ?? '';
      final parsedTravelingTo = cache.CacheManager.parseLocation(travelingTo);
      final worldId = parsedTravelingTo?.worldId;
      if (worldId == null) return null;

      final worldName =
          _worldNameById[worldId] ??
          _cacheManager.worldNameCache.worldName(worldId);
      if (worldName != null && worldName.isNotEmpty) {
        _worldNameById[worldId] = worldName;
      }
      return worldName;
    })();
    final location = (eventLocation ?? friend.location)?.trim() ?? '';
    final lower = location.toLowerCase();
    if (friend.status != UserStatus.offline && lower == 'offline') {
      return '在网页或其他端登录';
    }
    if (lower.contains('private')) return '在私人房间';
    if (lower == 'offline') return '离线';

    if (LocationUtils.isTraveling(location)) {
      if (eventWorldName != null && eventWorldName.isNotEmpty) {
        return '⟳ 正在前往 $eventWorldName';
      }
      return '⟳ 正在前往...';
    }

    final parsed = cache.CacheManager.parseLocation(location);
    if (parsed == null) return location;

    final worldName = _worldNameById[parsed.worldId];
    final base = (worldName == null || worldName == parsed.worldId)
        ? location
        : worldName;

    final typeLabel = _instanceTypeByLocation[parsed.rawLocation];
    final regionEmoji = LocationUtils.getRegionEmoji(location);

    final locationWithLabel = (typeLabel == null || typeLabel.isEmpty)
        ? base
        : '$base - $typeLabel';

    if (regionEmoji != null) {
      return '$regionEmoji $locationWithLabel';
    }
    return locationWithLabel;
  }

  bool _isTravelingFor(User friend) {
    final eventLocation = _userStore.getEventLocation(friend.id);
    final location = (eventLocation ?? friend.location)?.trim() ?? '';
    return LocationUtils.isTraveling(location);
  }

  String? _pickAvatarUrl(User user) {
    final avatarInfo = _userStore.getAvatarInfo(user.id);
    return avatarInfo?.avatarSmallUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友位置'),
        actions: [
          IconButton(
            onPressed: _openFriendSearchPage,
            tooltip: '搜索好友',
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: _refreshCooldownSeconds > 0 ? null : _onRefreshPressed,
            tooltip: _refreshCooldownSeconds > 0
                ? '刷新 (${_refreshCooldownSeconds}s)'
                : '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _userStore,
        builder: (context, child) {
          return _buildFriendsBody();
        },
      ),
    );
  }

  Widget _buildFriendsBody() {
    final onlineFriends = _userStore.getSortedOnlineFriends(
      favoriteIds: _allFavoriteIds,
    );
    final offlineFriendIds = _userStore
        .getFriendIds()
        .where((id) => !_userStore.isUserOnline(id))
        .toList();
    final webOrOtherFriends = onlineFriends
        .where((u) => u.location?.trim().toLowerCase() == 'offline')
        .toList();
    final trueOnlineFriends = onlineFriends
        .where((u) => u.location?.trim().toLowerCase() != 'offline')
        .toList();

    if (onlineFriends.isEmpty && offlineFriendIds.isEmpty) {
      return const Center(child: Text('暂无好友数据'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildOnlineGroupSection(trueOnlineFriends),
        _buildOfflineLikeGroupSection(
          title: '在网页或其他端登录',
          friends: webOrOtherFriends,
          expanded: _webExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _webExpanded = value;
            });
          },
        ),
        _buildOfflineGroupSection(
          offlineFriendIds: offlineFriendIds,
          expanded: _offlineExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _offlineExpanded = value;
            });
          },
        ),
      ],
    );
  }

  Set<String> get _allFavoriteIds {
    final ids = <String>{};
    for (final group in _favoriteFriendGroups) {
      ids.addAll(group.friendIds);
    }
    return ids;
  }

  Widget _buildOnlineGroupSection(List<User> onlineFriends) {
    final favoriteSections = <Widget>[];
    final assignedFriendIds = <String>{};

    for (final favoriteGroup in _favoriteFriendGroups) {
      final members = onlineFriends
          .where((u) => favoriteGroup.friendIds.contains(u.id))
          .toList();
      assignedFriendIds.addAll(members.map((m) => m.id));

      favoriteSections.add(
        ExpansionTile(
          initiallyExpanded:
              _favoriteGroupExpandedByName[favoriteGroup.name] ?? true,
          onExpansionChanged: (value) {
            setState(() {
              _favoriteGroupExpandedByName[favoriteGroup.name] = value;
            });
          },
          title: Text('${favoriteGroup.displayName} (${members.length})'),
          children: _buildUserRows(members),
        ),
      );
    }

    final others = onlineFriends
        .where((u) => !assignedFriendIds.contains(u.id))
        .toList();

    if (favoriteSections.isNotEmpty) {
      favoriteSections.add(
        ExpansionTile(
          initiallyExpanded: true,
          title: Text('其他在线 (${others.length})'),
          children: _buildUserRows(others),
        ),
      );
    } else {
      favoriteSections.addAll(_buildUserRows(onlineFriends));
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: _onlineExpanded,
        onExpansionChanged: (value) {
          setState(() {
            _onlineExpanded = value;
          });
        },
        title: Text('在线 (${onlineFriends.length})'),
        children: favoriteSections,
      ),
    );
  }

  Widget _buildOfflineLikeGroupSection({
    required String title,
    required List<User> friends,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text('$title (${friends.length})'),
        children: _buildUserRows(friends),
      ),
    );
  }

  Widget _buildOfflineGroupSection({
    required List<String> offlineFriendIds,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
  }) {
    final limitedUsers = offlineFriendIds
        .map((id) => _userStore.getLimitedUser(id))
        .whereType<LimitedUserFriend>()
        .toList();

    limitedUsers.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text('离线 (${offlineFriendIds.length})'),
        children: _buildLimitedUserRows(limitedUsers),
      ),
    );
  }

  List<Widget> _buildUserRows(List<User> friends) {
    if (friends.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(alignment: Alignment.centerLeft, child: Text('暂无数据')),
        ),
      ];
    }

    return [
      for (var i = 0; i < friends.length; i++) ...[
        _UserRow(
          user: friends[i],
          dio: widget.api.rawApi.dio,
          locationText: _locationTextFor(friends[i]),
          isTraveling: _isTravelingFor(friends[i]),
          avatarUrl: _pickAvatarUrl(friends[i]),
          avatarFileId: _userStore.getAvatarFileId(friends[i].id),
          trustColor: _userStore.trustColorForTags(friends[i].tags),
          onTap: () => _openFriendDetailPage(friends[i].id),
        ),
        if (i != friends.length - 1) const Divider(height: 1),
      ],
    ];
  }

  List<Widget> _buildLimitedUserRows(List<LimitedUserFriend> friends) {
    if (friends.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(alignment: Alignment.centerLeft, child: Text('暂无数据')),
        ),
      ];
    }

    return [
      for (var i = 0; i < friends.length; i++) ...[
        _LimitedUserRow(
          friend: friends[i],
          dio: widget.api.rawApi.dio,
          trustColor: _userStore.trustColorForTags(friends[i].tags),
          onTap: () => _openFriendDetailPage(friends[i].id),
        ),
        if (i != friends.length - 1) const Divider(height: 1),
      ],
    ];
  }

  Future<void> _onRefreshPressed() async {
    _startRefreshCooldown();
    await _userStore.initialize(widget.api);
    _buildFavoriteGroupsFromStore();
    await _resolveLocationsForOnlineFriends();
  }

  Future<void> _openFriendSearchPage() async {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    final offlineFriendIds = _userStore.getFriendIds().where(
      (id) => !_userStore.isUserOnline(id),
    );

    final searchUsers = <FriendSearchUser>[];

    for (final user in onlineFriends) {
      searchUsers.add(
        FriendSearchUser(
          id: user.id,
          displayName: user.displayName,
          status: user.status,
          location: user.location ?? 'offline',
          locationText: _locationTextFor(user),
          lastPlatform: user.lastPlatform,
          tags: user.tags,
          bio: user.bio,
          statusDescription: user.statusDescription,
          pronouns: user.pronouns,
          bioLinks: user.bioLinks ?? const [],
          dateJoined: user.dateJoined,
          lastActivity: DateTime.tryParse(user.lastActivity),
          profilePicOverrideThumbnail: user.profilePicOverrideThumbnail,
          profilePicOverride: user.profilePicOverride,
          currentAvatarThumbnailImageUrl: user.currentAvatarThumbnailImageUrl,
          userIcon: user.userIcon,
          imageUrl: user.currentAvatarImageUrl,
          isFriend: true,
        ),
      );
    }

    for (final id in offlineFriendIds) {
      final limited = _userStore.getLimitedUser(id);
      if (limited == null) continue;
      searchUsers.add(
        FriendSearchUser(
          id: limited.id,
          displayName: limited.displayName,
          status: UserStatus.offline,
          location: limited.location ?? 'offline',
          locationText: '离线',
          lastPlatform: limited.lastPlatform,
          tags: limited.tags,
          bio: limited.bio,
          statusDescription: limited.statusDescription,
          pronouns: null,
          bioLinks: limited.bioLinks ?? const [],
          dateJoined: null,
          lastActivity: limited.lastActivity,
          profilePicOverrideThumbnail: limited.profilePicOverrideThumbnail,
          profilePicOverride: limited.profilePicOverride,
          currentAvatarThumbnailImageUrl:
              limited.currentAvatarThumbnailImageUrl,
          userIcon: limited.userIcon,
          imageUrl: limited.currentAvatarImageUrl,
          isFriend: true,
        ),
      );
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendSearchPage(
          friends: searchUsers,
          dio: widget.api.rawApi.dio,
          rawApi: widget.api.rawApi,
          onOpenDetail: (user) => _openFriendDetailPage(user.id),
        ),
      ),
    );
  }

  Future<void> _openFriendDetailPage(String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FriendDetailPage(userId: userId, api: widget.api.rawApi),
      ),
    );
  }

  void _startRefreshCooldown() {
    _refreshCooldownTimer?.cancel();
    setState(() {
      _refreshCooldownSeconds = 5;
    });

    _refreshCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_refreshCooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _refreshCooldownSeconds = 0;
        });
        return;
      }

      setState(() {
        _refreshCooldownSeconds -= 1;
      });
    });
  }
}

class _FavoriteFriendGroupView {
  const _FavoriteFriendGroupView({
    required this.name,
    required this.displayName,
    required this.friendIds,
  });

  final String name;
  final String displayName;
  final Set<String> friendIds;
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.dio,
    required this.locationText,
    required this.isTraveling,
    required this.avatarUrl,
    required this.avatarFileId,
    required this.trustColor,
    required this.onTap,
  });

  final User user;
  final Dio dio;
  final String locationText;
  final bool isTraveling;
  final String? avatarUrl;
  final String? avatarFileId;
  final Color trustColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusMeta = _statusMeta(user.status);

    return ListTile(
      onTap: onTap,
      leading: _AvatarWithStatusDot(
        dio: dio,
        imageUrl: avatarUrl,
        fileId: avatarFileId,
        statusColor: statusMeta.color,
      ),
      title: Text(
        user.displayName,
        style: TextStyle(color: trustColor, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: isTraveling
            ? Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(locationText),
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

class _LimitedUserRow extends StatelessWidget {
  const _LimitedUserRow({
    required this.friend,
    required this.dio,
    required this.trustColor,
    required this.onTap,
  });

  final LimitedUserFriend friend;
  final Dio dio;
  final Color trustColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarInfo = UserStore.instance.getAvatarInfo(friend.id);

    return ListTile(
      onTap: onTap,
      leading: _AvatarWithStatusDot(
        dio: dio,
        imageUrl: avatarInfo?.avatarSmallUrl,
        fileId: UserStore.instance.getAvatarFileId(friend.id),
        statusColor: Colors.grey,
      ),
      title: Text(
        friend.displayName,
        style: TextStyle(color: trustColor, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('离线'),
      ),
    );
  }
}

class _AvatarWithStatusDot extends StatelessWidget {
  const _AvatarWithStatusDot({
    required this.dio,
    required this.imageUrl,
    this.fileId,
    required this.statusColor,
  });

  final Dio dio;
  final String? imageUrl;
  final String? fileId;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          VrcAvatar(imageUrl: imageUrl, fileId: fileId, dio: dio),
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
