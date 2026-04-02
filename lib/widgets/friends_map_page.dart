import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/app_settings.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/utils/location_utils.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';
import 'package:vrc_monitor/widgets/me_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';
import 'package:vrc_monitor/widgets/world_detail_page.dart';

class FriendsMapPage extends StatefulWidget {
  const FriendsMapPage({
    super.key,
    required this.api,
    required this.currentUser,
  });

  final VrchatDart api;
  final CurrentUser currentUser;

  @override
  State<FriendsMapPage> createState() => _FriendsMapPageState();
}

class _FriendsMapPageState extends State<FriendsMapPage> {
  final UserStore _userStore = UserStore.instance;
  final WorldStore _worldStore = WorldStore.instance;
  final cache.CacheManager _cacheManager = cache.CacheManager.instance;

  final Map<String, String> _worldNameById = <String, String>{};
  final Map<String, String> _instanceTypeByRoomKey = <String, String>{};
  final Set<String> _worldIdsInFlight = <String>{};
  final Set<String> _roomKeysInFlight = <String>{};
  final Set<String> _ownerIdsInFlight = <String>{};
  final Set<String> _worldImageIdsInFlight = <String>{};
  Timer? _refreshCooldownTimer;
  int _refreshCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _userStore.addListener(_handleStoreChanged);
    _worldStore.addListener(_handleStoreChanged);
    unawaited(_hydrateFromCache());
  }

  @override
  void dispose() {
    _refreshCooldownTimer?.cancel();
    _userStore.removeListener(_handleStoreChanged);
    _worldStore.removeListener(_handleStoreChanged);
    super.dispose();
  }

  Future<void> _hydrateFromCache() async {
    await _worldStore.initialize();
    if (!mounted) return;

    setState(() {
      _worldNameById
        ..clear()
        ..addAll(_worldStore.worldNameById);
    });
    unawaited(_resolveRoomData());
  }

  void _handleStoreChanged() {
    unawaited(_resolveRoomData());
  }

  Future<void> _onRefreshPressed() async {
    _startRefreshCooldown();
    await _userStore.refreshForForeground(widget.api);
    await _resolveRoomData();
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

  Future<void> _resolveRoomData() async {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    final worldsToFetch = <String>{};
    final instancesToFetch = <_InstanceLookupTask>[];
    final ownersToFetch = <String>{};
    final worldImagesToCache = <String>{};
    var hasImmediateUpdate = false;

    for (final friend in onlineFriends) {
      final location =
          (_userStore.getEventLocation(friend.id) ?? friend.location)?.trim();
      final roomRef = _parseRoomRef(location);
      if (roomRef == null) continue;

      _collectRoomResolveTasks(
        roomRef: roomRef,
        worldsToFetch: worldsToFetch,
        instancesToFetch: instancesToFetch,
        ownersToFetch: ownersToFetch,
        worldImagesToCache: worldImagesToCache,
        onImmediateUpdate: () {
          hasImmediateUpdate = true;
        },
      );
    }

    final selfState = _buildSelfLocationState();
    if (selfState?.roomRef != null) {
      _collectRoomResolveTasks(
        roomRef: selfState!.roomRef!,
        worldsToFetch: worldsToFetch,
        instancesToFetch: instancesToFetch,
        ownersToFetch: ownersToFetch,
        worldImagesToCache: worldImagesToCache,
        onImmediateUpdate: () {
          hasImmediateUpdate = true;
        },
      );
    }

    final selfTravelingWorldId = selfState?.travelingWorldId;
    if (selfTravelingWorldId != null && selfTravelingWorldId.isNotEmpty) {
      final cached = _worldStore.getWorldName(selfTravelingWorldId);
      if (cached != null && cached.isNotEmpty) {
        if (_worldNameById[selfTravelingWorldId] != cached) {
          _worldNameById[selfTravelingWorldId] = cached;
          hasImmediateUpdate = true;
        }
      } else if (!_worldIdsInFlight.contains(selfTravelingWorldId)) {
        worldsToFetch.add(selfTravelingWorldId);
        _worldIdsInFlight.add(selfTravelingWorldId);
      }
    }

    if (hasImmediateUpdate && mounted) {
      setState(() {});
    }

    if (worldsToFetch.isEmpty &&
        instancesToFetch.isEmpty &&
        ownersToFetch.isEmpty &&
        worldImagesToCache.isEmpty) {
      return;
    }

    final tasks = <Future<void>>[];

    for (final worldId in worldsToFetch) {
      tasks.add(() async {
        try {
          final world = await _worldStore.getOrFetch(
            worldId,
            widget.api.rawApi,
          );
          final nextName = world?.name.trim();
          if (nextName != null &&
              nextName.isNotEmpty &&
              _worldNameById[worldId] != nextName) {
            _worldNameById[worldId] = nextName;
            if (mounted) setState(() {});
          }

          if (world != null) {
            final imageUrl = world.thumbnailImageUrl.trim();
            if (imageUrl.isNotEmpty) {
              await _cacheManager.imageCache.cacheWorldImage(
                dio: widget.api.rawApi.dio,
                imageUrl: imageUrl,
              );
            }
          }
        } finally {
          _worldIdsInFlight.remove(worldId);
          _worldImageIdsInFlight.remove(worldId);
        }
      }());
    }

    for (final lookup in instancesToFetch) {
      tasks.add(() async {
        try {
          final (success, _) = await widget.api.rawApi
              .getWorldsApi()
              .getWorldInstance(
                worldId: lookup.worldId,
                instanceId: lookup.instanceIdWithFlags,
              )
              .validateVrc();
          if (success == null) return;

          final typeLabel = cache.CacheManager.instanceTypeLabel(
            success.data.type,
            canRequestInvite: success.data.canRequestInvite ?? false,
          );
          if (_instanceTypeByRoomKey[lookup.roomKey] != typeLabel) {
            _instanceTypeByRoomKey[lookup.roomKey] = typeLabel;
            _cacheManager.memoryCache.putInstanceType(
              lookup.rawLocation,
              typeLabel,
            );
            if (mounted) setState(() {});
          }
        } finally {
          _roomKeysInFlight.remove(lookup.roomKey);
        }
      }());
    }

    for (final ownerId in ownersToFetch) {
      tasks.add(() async {
        try {
          await _userStore.loadUser(ownerId, widget.api.rawApi);
          if (mounted) setState(() {});
        } finally {
          _ownerIdsInFlight.remove(ownerId);
        }
      }());
    }

    for (final worldId in worldImagesToCache) {
      tasks.add(() async {
        try {
          final world = _worldStore.getWorld(worldId);
          final imageUrl = world?.thumbnailImageUrl.trim() ?? '';
          if (imageUrl.isEmpty) return;
          await _cacheManager.imageCache.cacheWorldImage(
            dio: widget.api.rawApi.dio,
            imageUrl: imageUrl,
          );
        } finally {
          _worldImageIdsInFlight.remove(worldId);
        }
      }());
    }

    await Future.wait(tasks);
  }

  void _collectRoomResolveTasks({
    required _RoomLocationRef roomRef,
    required Set<String> worldsToFetch,
    required List<_InstanceLookupTask> instancesToFetch,
    required Set<String> ownersToFetch,
    required Set<String> worldImagesToCache,
    required VoidCallback onImmediateUpdate,
  }) {
    final roomKey = roomRef.roomKey;

    final cachedName = _worldStore.getWorldName(roomRef.worldId);
    if (cachedName != null && cachedName.isNotEmpty) {
      if (_worldNameById[roomRef.worldId] != cachedName) {
        _worldNameById[roomRef.worldId] = cachedName;
        onImmediateUpdate();
      }
    } else if (!_worldIdsInFlight.contains(roomRef.worldId)) {
      worldsToFetch.add(roomRef.worldId);
      _worldIdsInFlight.add(roomRef.worldId);
    }

    final world = _worldStore.getWorld(roomRef.worldId);
    final imageUrl = world?.thumbnailImageUrl.trim() ?? '';
    if (imageUrl.isNotEmpty &&
        !_worldImageIdsInFlight.contains(roomRef.worldId)) {
      worldImagesToCache.add(roomRef.worldId);
      _worldImageIdsInFlight.add(roomRef.worldId);
    }

    final instanceLabel = _instanceTypeByRoomKey[roomKey];
    final cachedInstanceType = _cacheManager.memoryCache.instanceType(
      roomRef.rawLocation,
    );
    if ((instanceLabel == null || instanceLabel.isEmpty) &&
        cachedInstanceType != null &&
        cachedInstanceType.isNotEmpty) {
      _instanceTypeByRoomKey[roomKey] = cachedInstanceType;
      onImmediateUpdate();
    } else if ((instanceLabel == null || instanceLabel.isEmpty) &&
        !_roomKeysInFlight.contains(roomKey)) {
      instancesToFetch.add(
        _InstanceLookupTask(
          roomKey: roomKey,
          worldId: roomRef.worldId,
          instanceIdWithFlags: roomRef.instanceIdWithFlags,
          rawLocation: roomRef.rawLocation,
        ),
      );
      _roomKeysInFlight.add(roomKey);
    }

    final ownerId = roomRef.ownerUserId;
    if (ownerId != null &&
        _userStore.getUser(ownerId) == null &&
        !_ownerIdsInFlight.contains(ownerId)) {
      ownersToFetch.add(ownerId);
      _ownerIdsInFlight.add(ownerId);
    }
  }

  Future<void> _openFriendDetailPage(String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FriendDetailPage(userId: userId, api: widget.api.rawApi),
      ),
    );
  }

  Future<void> _openMePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MePage(api: widget.api, currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _openWorldDetailPage(_RoomGroupViewModel room) async {
    if (room.isSelfTraveling) return;
    if (!room.worldId.startsWith('wrld_')) return;
    if (room.instanceId.trim().isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorldDetailPage(
          api: widget.api.rawApi,
          worldId: room.worldId,
          instanceId: room.instanceId,
        ),
      ),
    );
  }

  String _displayInstanceId(String fullInstanceId) {
    final full = fullInstanceId.trim();
    if (full.isEmpty) return full;
    final short = full.split('~').first.trim();
    if (short.isEmpty) return full;
    return short;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间排序'),
        actions: [
          IconButton(
            onPressed: _refreshCooldownSeconds > 0 ? null : _onRefreshPressed,
            tooltip: _refreshCooldownSeconds > 0
                ? '刷新 (${_refreshCooldownSeconds}s)'
                : '刷新',
            icon: const Icon(Icons.refresh),
          ),
          ValueListenableBuilder<MapRoomSortMode>(
            valueListenable: AppMapSettings.roomSortModeNotifier,
            builder: (context, mode, child) {
              return PopupMenuButton<MapRoomSortMode>(
                tooltip: '星标优先',
                icon: const Icon(Icons.sort),
                onSelected: AppMapSettings.setRoomSortMode,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem<MapRoomSortMode>(
                    value: MapRoomSortMode.starFirst,
                    checked: mode == MapRoomSortMode.starFirst,
                    child: const Text('星标好友优先'),
                  ),
                  CheckedPopupMenuItem<MapRoomSortMode>(
                    value: MapRoomSortMode.countFirst,
                    checked: mode == MapRoomSortMode.countFirst,
                    child: const Text('总好友数优先'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _userStore,
          _worldStore,
          AppMapSettings.roomSortModeNotifier,
        ]),
        builder: (context, child) {
          final rooms = _buildRooms();
          final privateRoomFriendCount = _countPrivateRoomFriends();
          if (rooms.isEmpty) {
            return Center(
              child: Text('暂无可显示的在线房间\n您还有$privateRoomFriendCount个好友在私人房间'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (var i = 0; i < rooms.length; i++) ...[
                _RoomCard(
                  room: rooms[i],
                  dio: widget.api.rawApi.dio,
                  onTapFriend: _openFriendDetailPage,
                  onTapRoom: rooms[i].isSelfTraveling
                      ? null
                      : () => _openWorldDetailPage(rooms[i]),
                  showSelfTile: rooms[i].isSelfRoom || rooms[i].isSelfTraveling,
                  selfAvatarUrl: _currentUserAvatarUrl(),
                  selfAvatarFileId: _userStore.getAvatarFileId(
                    widget.currentUser.id,
                  ),
                  onTapSelf: _openMePage,
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Center(
                  child: Text('您还有$privateRoomFriendCount个好友在私人房间'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_RoomGroupViewModel> _buildRooms() {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    final favoriteIds = _userStore.getFavoriteFriendIds();
    final grouped = <String, _RoomGroupBuilder>{};

    for (final friend in onlineFriends) {
      final location =
          (_userStore.getEventLocation(friend.id) ?? friend.location)?.trim();
      final roomRef = _parseRoomRef(location);
      if (roomRef == null) continue;

      final roomKey = roomRef.roomKey;
      final existing = grouped[roomKey];
      if (existing == null) {
        grouped[roomKey] = _RoomGroupBuilder(
          roomKey: roomKey,
          worldId: roomRef.worldId,
          instanceId: roomRef.instanceId,
          rawLocation: roomRef.rawLocation,
          ownerUserId: roomRef.ownerUserId,
          regionEmoji: LocationUtils.getRegionEmoji(roomRef.rawLocation),
          isSelfRoom: false,
        )..members.add(friend);
      } else {
        existing.members.add(friend);
      }
    }

    _RoomGroupViewModel? selfTravelingCard;
    final selfState = _buildSelfLocationState();
    if (selfState != null) {
      if (selfState.isTraveling) {
        selfTravelingCard = _RoomGroupViewModel(
          roomKey: '__self_traveling__',
          worldId: selfState.travelingWorldId ?? '',
          instanceId: '',
          displayInstanceId: '',
          worldName: '',
          worldImageUrl: null,
          roomTypeLabel: null,
          ownerUserId: null,
          ownerName: 'Unknown',
          regionEmoji: null,
          members: const <User>[],
          favoriteMemberCount: 0,
          isSelfRoom: false,
          isSelfTraveling: true,
          selfTravelingText: selfState.travelingText,
        );
      } else if (selfState.roomRef != null) {
        final roomRef = selfState.roomRef!;
        final roomKey = roomRef.roomKey;
        final existing = grouped[roomKey];
        if (existing == null) {
          grouped[roomKey] = _RoomGroupBuilder(
            roomKey: roomKey,
            worldId: roomRef.worldId,
            instanceId: roomRef.instanceId,
            rawLocation: roomRef.rawLocation,
            ownerUserId: roomRef.ownerUserId,
            regionEmoji: LocationUtils.getRegionEmoji(roomRef.rawLocation),
            isSelfRoom: true,
          );
        } else {
          existing.isSelfRoom = true;
        }
      }
    }

    final rooms = grouped.values.map((builder) {
      final normalizedWorldId = _normalizeWorldId(
        worldId: builder.worldId,
        rawLocation: builder.rawLocation,
      );
      final worldName =
          _worldStore.getWorldName(normalizedWorldId) ??
          _worldNameById[normalizedWorldId] ??
          normalizedWorldId;
      final world = _worldStore.getWorld(normalizedWorldId);
      final ownerName = _resolveOwnerName(builder.ownerUserId);
      final favoriteCount = builder.members
          .where((u) => favoriteIds.contains(u.id))
          .length;

      return _RoomGroupViewModel(
        roomKey: builder.roomKey,
        worldId: normalizedWorldId,
        instanceId: builder.instanceId,
        displayInstanceId: _displayInstanceId(builder.instanceId),
        worldName: worldName,
        worldImageUrl: world?.thumbnailImageUrl,
        roomTypeLabel: _instanceTypeByRoomKey[builder.roomKey],
        ownerUserId: builder.ownerUserId,
        ownerName: ownerName,
        regionEmoji: builder.regionEmoji,
        members: builder.members
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          ),
        favoriteMemberCount: favoriteCount,
        isSelfRoom: builder.isSelfRoom,
        isSelfTraveling: false,
        selfTravelingText: null,
      );
    }).toList();

    if (selfTravelingCard != null) {
      rooms.add(selfTravelingCard);
    }

    final mode = AppMapSettings.roomSortModeNotifier.value;
    rooms.sort((a, b) {
      final aSelf = a.isSelfRoom || a.isSelfTraveling;
      final bSelf = b.isSelfRoom || b.isSelfTraveling;
      if (aSelf != bSelf) return aSelf ? -1 : 1;

      final first = mode == MapRoomSortMode.starFirst
          ? b.favoriteMemberCount.compareTo(a.favoriteMemberCount)
          : b.members.length.compareTo(a.members.length);
      if (first != 0) return first;

      final second = mode == MapRoomSortMode.starFirst
          ? b.members.length.compareTo(a.members.length)
          : b.favoriteMemberCount.compareTo(a.favoriteMemberCount);
      if (second != 0) return second;

      return a.worldName.toLowerCase().compareTo(b.worldName.toLowerCase());
    });

    return rooms;
  }

  _SelfLocationState? _buildSelfLocationState() {
    var selfLocation = _userStore.getSelfLocation()?.trim() ?? '';
    var selfInstance = _userStore.getSelfInstance()?.trim() ?? '';
    var selfEventWorldName = _userStore.getSelfEventWorldName()?.trim() ?? '';
    var selfWorldId = _userStore.getSelfWorldId()?.trim() ?? '';
    final presence = widget.currentUser.presence;

    final travelingTarget = presence?.travelingToWorld?.trim() ?? '';

    if (selfLocation.isEmpty) {
      final presenceWorld = presence?.world?.trim() ?? '';
      final presenceInstance = presence?.instance?.trim() ?? '';
      if (presenceWorld.isNotEmpty &&
          presenceWorld.toLowerCase() != 'offline' &&
          presenceInstance.isNotEmpty) {
        selfLocation = '$presenceWorld:$presenceInstance';
        selfInstance = presenceInstance;
        if (selfWorldId.isEmpty && presenceWorld.startsWith('wrld_')) {
          selfWorldId = presenceWorld;
        }
      } else if (LocationUtils.isTraveling(presenceWorld)) {
        selfLocation = 'traveling';
      }
    }

    final lower = selfLocation.toLowerCase();
    if (selfLocation.isEmpty || lower == 'offline') {
      return null;
    }

    if (LocationUtils.isTraveling(selfLocation)) {
      String? travelingWorldId;
      String? travelingText;
      final parsedTarget = cache.CacheManager.parseLocation(travelingTarget);
      if (parsedTarget != null) {
        travelingWorldId = parsedTarget.worldId;
      } else if (travelingTarget.startsWith('wrld_')) {
        travelingWorldId = travelingTarget;
      }

      final worldName = (() {
        if (selfEventWorldName.isNotEmpty) return selfEventWorldName;
        if (travelingWorldId == null || travelingWorldId.isEmpty) return null;
        return _worldStore.getWorldName(travelingWorldId) ??
            _worldNameById[travelingWorldId];
      })();

      if (worldName != null && worldName.trim().isNotEmpty) {
        travelingText = '正在前往 $worldName';
      } else if (travelingWorldId != null && travelingWorldId.isNotEmpty) {
        travelingText = '正在前往 $travelingWorldId';
      } else {
        travelingText = '正在前往...';
      }

      return _SelfLocationState(
        isTraveling: true,
        roomRef: null,
        travelingText: travelingText,
        travelingWorldId: travelingWorldId,
      );
    }

    var roomRef = _parseRoomRef(selfLocation, allowPrivate: true);
    if (roomRef == null && selfWorldId.isNotEmpty && selfInstance.isNotEmpty) {
      roomRef = _parseRoomRef('$selfWorldId:$selfInstance', allowPrivate: true);
    }
    if (roomRef == null) {
      return null;
    }

    return _SelfLocationState(
      isTraveling: false,
      roomRef: roomRef,
      travelingText: null,
      travelingWorldId: null,
    );
  }

  String _resolveOwnerName(String? ownerUserId) {
    if (ownerUserId == null || ownerUserId.isEmpty) return 'Unknown';
    final user = _userStore.getUser(ownerUserId);
    if (user != null) return user.displayName;
    final limited = _userStore.getLimitedUser(ownerUserId);
    if (limited != null) return limited.displayName;
    return ownerUserId;
  }

  String _normalizeWorldId({
    required String worldId,
    required String rawLocation,
  }) {
    final trimmed = worldId.trim();
    if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'null') {
      return trimmed;
    }

    final parsed = cache.CacheManager.parseLocation(rawLocation);
    final parsedWorldId = parsed?.worldId.trim() ?? '';
    if (parsedWorldId.isNotEmpty && parsedWorldId.toLowerCase() != 'null') {
      return parsedWorldId;
    }

    return 'unknown_world';
  }

  int _countPrivateRoomFriends() {
    final onlineFriends = _userStore.getSortedOnlineFriends();
    var count = 0;
    for (final friend in onlineFriends) {
      final location =
          ((_userStore.getEventLocation(friend.id) ?? friend.location)
              ?.trim()
              .toLowerCase()) ??
          '';
      if (location.isEmpty || location == 'offline') continue;
      if (location.contains('private')) {
        count += 1;
      }
    }
    return count;
  }

  String? _currentUserAvatarUrl() {
    final avatarInfo = _userStore.getAvatarInfo(widget.currentUser.id);
    final cached = avatarInfo?.avatarSmallUrl?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    final profilePic = widget.currentUser.profilePicOverride.trim();
    if (profilePic.isNotEmpty) {
      return cache.ImageCache.toSmallUrl(profilePic, isCustom: true);
    }

    final avatarImage = widget.currentUser.currentAvatarImageUrl.trim();
    if (avatarImage.isNotEmpty) {
      return cache.ImageCache.toSmallUrl(avatarImage, isCustom: false);
    }
    return null;
  }

  _RoomLocationRef? _parseRoomRef(
    String? location, {
    bool allowPrivate = false,
  }) {
    final raw = location?.trim() ?? '';
    if (raw.isEmpty || LocationUtils.isTraveling(raw)) return null;
    final lower = raw.toLowerCase();
    if (lower == 'offline') return null;
    if (!allowPrivate && lower.contains('private')) return null;

    final parsed = cache.CacheManager.parseLocation(raw);
    if (parsed == null) return null;

    final instanceIdWithFlags = parsed.instanceId.trim();
    final instanceId = instanceIdWithFlags;
    if (instanceId.isEmpty) return null;
    final ownerUserId = _extractHiddenOwnerUserId(raw);
    return _RoomLocationRef(
      rawLocation: raw,
      worldId: parsed.worldId,
      instanceId: instanceId,
      instanceIdWithFlags: instanceIdWithFlags,
      ownerUserId: ownerUserId,
    );
  }

  String? _extractHiddenOwnerUserId(String location) {
    final match = RegExp(
      r'~(?:hidden|friends|private|group|groupaccess)\((usr_[^)]+)\)',
      caseSensitive: false,
    ).firstMatch(location);
    final generic =
        match ??
        RegExp(
          r'~[^~()]+\((usr_[^)]+)\)',
          caseSensitive: false,
        ).firstMatch(location);
    final userId = generic?.group(1)?.trim() ?? '';
    if (userId.isEmpty) return null;
    return userId;
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.dio,
    required this.onTapFriend,
    required this.onTapRoom,
    required this.showSelfTile,
    required this.selfAvatarUrl,
    required this.selfAvatarFileId,
    required this.onTapSelf,
  });

  final _RoomGroupViewModel room;
  final Dio dio;
  final Future<void> Function(String userId) onTapFriend;
  final VoidCallback? onTapRoom;
  final bool showSelfTile;
  final String? selfAvatarUrl;
  final String? selfAvatarFileId;
  final Future<void> Function() onTapSelf;

  @override
  Widget build(BuildContext context) {
    final roomType = room.roomTypeLabel?.trim();
    final isPublicRoom = (roomType ?? '').toLowerCase() == 'public';
    final ownerLabel = room.ownerName.isEmpty ? 'Unknown' : room.ownerName;
    final ownerUserId = room.ownerUserId;
    final ownerClickable =
        ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        ownerLabel.toLowerCase() != 'unknown';

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTapRoom,
            child: _WorldImageBanner(imageUrl: room.worldImageUrl, dio: dio),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (room.isSelfTraveling)
                  Text(
                    room.selfTravelingText ?? '正在前往...',
                    style: Theme.of(context).textTheme.titleMedium,
                  )
                else ...[
                  Text(
                    '${room.regionEmoji ?? '🌍'} ${room.worldName} #${room.displayInstanceId}'
                    '${roomType == null || roomType.isEmpty ? '' : ' $roomType'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!isPublicRoom) ...[
                    const SizedBox(height: 6),
                    if (ownerClickable)
                      InkWell(
                        onTap: () => unawaited(onTapFriend(ownerUserId)),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(
                            TextSpan(
                              text: '房主: ',
                              children: [
                                TextSpan(
                                  text: ownerLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      Text.rich(
                        TextSpan(
                          text: '房主: ',
                          children: [
                            TextSpan(
                              text: ownerLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ],
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: room.members.length + (showSelfTile ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (showSelfTile && index == 0) {
                      return _SelfMemberTile(
                        dio: dio,
                        imageUrl: selfAvatarUrl,
                        fileId: selfAvatarFileId,
                        onTap: onTapSelf,
                      );
                    }
                    final member =
                        room.members[showSelfTile ? index - 1 : index];
                    return _MemberTile(
                      user: member,
                      dio: dio,
                      onTap: () => onTapFriend(member.id),
                    );
                  },
                ),
                if (room.members.isEmpty && showSelfTile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '当前没有好友在此房间',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
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

class _SelfMemberTile extends StatelessWidget {
  const _SelfMemberTile({
    required this.dio,
    required this.imageUrl,
    required this.fileId,
    required this.onTap,
  });

  final Dio dio;
  final String? imageUrl;
  final String? fileId;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        unawaited(onTap());
      },
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VrcAvatar(dio: dio, imageUrl: imageUrl, fileId: fileId, size: 42),
          const SizedBox(height: 6),
          Text(
            '您',
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

class _WorldImageBanner extends StatelessWidget {
  const _WorldImageBanner({required this.imageUrl, required this.dio});

  final String? imageUrl;
  final Dio dio;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim() ?? '';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: normalizedUrl.isEmpty
              ? const Center(child: Icon(Icons.public, size: 44))
              : VrcNetworkImage(
                  dio: dio,
                  imageUrl: normalizedUrl,
                  fit: BoxFit.cover,
                  placeholder: const Center(child: CircularProgressIndicator()),
                  errorWidget: const Center(
                    child: Icon(Icons.broken_image_outlined, size: 32),
                  ),
                ),
        ),
      ),
    );
  }
}

class _RoomGroupBuilder {
  _RoomGroupBuilder({
    required this.roomKey,
    required this.worldId,
    required this.instanceId,
    required this.rawLocation,
    required this.ownerUserId,
    required this.regionEmoji,
    required this.isSelfRoom,
  });

  final String roomKey;
  final String worldId;
  final String instanceId;
  final String rawLocation;
  final String? ownerUserId;
  final String? regionEmoji;
  final List<User> members = <User>[];
  bool isSelfRoom;
}

class _RoomGroupViewModel {
  const _RoomGroupViewModel({
    required this.roomKey,
    required this.worldId,
    required this.instanceId,
    required this.displayInstanceId,
    required this.worldName,
    required this.worldImageUrl,
    required this.roomTypeLabel,
    required this.ownerUserId,
    required this.ownerName,
    required this.regionEmoji,
    required this.members,
    required this.favoriteMemberCount,
    required this.isSelfRoom,
    required this.isSelfTraveling,
    required this.selfTravelingText,
  });

  final String roomKey;
  final String worldId;
  final String instanceId;
  final String displayInstanceId;
  final String worldName;
  final String? worldImageUrl;
  final String? roomTypeLabel;
  final String? ownerUserId;
  final String ownerName;
  final String? regionEmoji;
  final List<User> members;
  final int favoriteMemberCount;
  final bool isSelfRoom;
  final bool isSelfTraveling;
  final String? selfTravelingText;
}

class _RoomLocationRef {
  const _RoomLocationRef({
    required this.rawLocation,
    required this.worldId,
    required this.instanceId,
    required this.instanceIdWithFlags,
    required this.ownerUserId,
  });

  final String rawLocation;
  final String worldId;
  final String instanceId;
  final String instanceIdWithFlags;
  final String? ownerUserId;

  String get roomKey => '$worldId:$instanceId';
}

class _InstanceLookupTask {
  const _InstanceLookupTask({
    required this.roomKey,
    required this.worldId,
    required this.instanceIdWithFlags,
    required this.rawLocation,
  });

  final String roomKey;
  final String worldId;
  final String instanceIdWithFlags;
  final String rawLocation;
}

class _SelfLocationState {
  const _SelfLocationState({
    required this.isTraveling,
    required this.roomRef,
    required this.travelingText,
    required this.travelingWorldId,
  });

  final bool isTraveling;
  final _RoomLocationRef? roomRef;
  final String? travelingText;
  final String? travelingWorldId;
}
