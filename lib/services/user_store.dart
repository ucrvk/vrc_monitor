import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/world_store.dart';

class FavoriteGroupData {
  const FavoriteGroupData({required this.name, required this.displayName});

  final String name;
  final String displayName;
}

enum WsConnectionStatus { connected, connecting, disconnected }

class UserAvatarInfo {
  const UserAvatarInfo({
    this.avatarSmallUrl,
    this.avatarFullUrl,
    this.headerSmallUrl,
    this.headerFullUrl,
    this.hasCustomIcon = false,
  });

  final String? avatarSmallUrl;
  final String? avatarFullUrl;
  final String? headerSmallUrl;
  final String? headerFullUrl;
  final bool hasCustomIcon;

  static UserAvatarInfo fromUser(User? user) {
    if (user == null) return const UserAvatarInfo();

    final userIcon = user.userIcon.trim();
    final hasUserIcon = userIcon.isNotEmpty;

    final profilePic = user.profilePicOverride.trim();
    final avatarImg = user.currentAvatarImageUrl.trim();

    String? avatarSmallUrl;
    String? avatarFullUrl;
    String? headerSmallUrl;
    String? headerFullUrl;

    if (hasUserIcon) {
      avatarFullUrl = userIcon;
      avatarSmallUrl = userIcon;
    } else if (profilePic.isNotEmpty) {
      avatarFullUrl = profilePic;
      avatarSmallUrl = _toSmallUrl(profilePic, isCustom: true);
    } else if (avatarImg.isNotEmpty) {
      avatarFullUrl = _ensureFileEnding(avatarImg);
      avatarSmallUrl = _toSmallUrl(avatarFullUrl, isCustom: false);
    }

    if (profilePic.isNotEmpty) {
      headerFullUrl = profilePic;
      headerSmallUrl = _toSmallUrl(profilePic, isCustom: true);
    } else if (avatarImg.isNotEmpty) {
      headerFullUrl = _ensureFileEnding(avatarImg);
      headerSmallUrl = _toSmallUrl(headerFullUrl, isCustom: false);
    }

    return UserAvatarInfo(
      avatarSmallUrl: avatarSmallUrl,
      avatarFullUrl: avatarFullUrl,
      headerSmallUrl: headerSmallUrl,
      headerFullUrl: headerFullUrl,
      hasCustomIcon: hasUserIcon,
    );
  }

  static UserAvatarInfo fromLimitedUser(LimitedUserFriend? user) {
    if (user == null) return const UserAvatarInfo();

    final userIcon = user.userIcon?.trim() ?? '';
    final hasUserIcon = userIcon.isNotEmpty;

    final profilePic = user.profilePicOverride?.trim() ?? '';
    final avatarImg = user.currentAvatarImageUrl?.trim() ?? '';

    String? avatarSmallUrl;
    String? avatarFullUrl;
    String? headerSmallUrl;
    String? headerFullUrl;

    if (hasUserIcon) {
      avatarFullUrl = userIcon;
      avatarSmallUrl = userIcon;
    } else if (profilePic.isNotEmpty) {
      avatarFullUrl = profilePic;
      avatarSmallUrl = _toSmallUrl(profilePic, isCustom: true);
    } else if (avatarImg.isNotEmpty) {
      avatarFullUrl = _ensureFileEnding(avatarImg);
      avatarSmallUrl = _toSmallUrl(avatarFullUrl, isCustom: false);
    }

    if (profilePic.isNotEmpty) {
      headerFullUrl = profilePic;
      headerSmallUrl = _toSmallUrl(profilePic, isCustom: true);
    } else if (avatarImg.isNotEmpty) {
      headerFullUrl = _ensureFileEnding(avatarImg);
      headerSmallUrl = _toSmallUrl(headerFullUrl, isCustom: false);
    }

    return UserAvatarInfo(
      avatarSmallUrl: avatarSmallUrl,
      avatarFullUrl: avatarFullUrl,
      headerSmallUrl: headerSmallUrl,
      headerFullUrl: headerFullUrl,
      hasCustomIcon: hasUserIcon,
    );
  }

  static String _toSmallUrl(String url, {required bool isCustom}) {
    return cache.ImageCache.toSmallUrl(url, isCustom: isCustom);
  }

  static String _ensureFileEnding(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return normalized;

    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    if (normalized.contains('/image/') &&
        !normalized.endsWith('/file') &&
        !normalized.endsWith('/256')) {
      return '$normalized/file';
    }
    return normalized;
  }
}

class UserStore extends ChangeNotifier {
  UserStore._();

  static final UserStore instance = UserStore._();

  static const int _pageSize = 100;
  static const Color _trustVeteranColor = Color(0xFFB18FFF);
  static const Color _trustTrustedColor = Color(0xFFFF7B42);
  static const Color _trustKnownColor = Color(0xFF2BCF5C);
  static const Color _trustBasicColor = Color(0xFF1778FF);
  static const Color _trustDefaultColor = Color(0xFFCCCCCC);

  final Set<String> _allFriendIds = <String>{};
  final Set<String> _onlineFriendIds = <String>{};
  final Map<String, User> _users = <String, User>{};
  final Map<String, String> _avatarFileIdByUserId = <String, String>{};
  final Map<String, String> _headerFileIdByUserId = <String, String>{};
  final Map<String, String> _locationByUserId = <String, String>{};
  final Map<String, String> _eventWorldNameByUserId = <String, String>{};
  String? _selfLocation;
  String? _selfInstance;
  String? _selfEventWorldName;
  String? _selfWorldId;
  final Map<String, LimitedUserFriend> _limitedUsers =
      <String, LimitedUserFriend>{};
  final Map<String, List<MutualFriend>> _mutualFriends =
      <String, List<MutualFriend>>{};
  final Map<String, FriendStatus> _friendStatuses = <String, FriendStatus>{};
  final Map<String, Future<User?>> _loadingUserById = <String, Future<User?>>{};
  final Map<String, Future<List<MutualFriend>?>> _loadingMutualFriendsById =
      <String, Future<List<MutualFriend>?>>{};
  final Map<String, Future<FriendStatus?>> _loadingFriendStatusById =
      <String, Future<FriendStatus?>>{};
  StreamSubscription<VrcStreamingEvent>? _wsSubscription;
  VrchatDart? _streamingApiRef;
  Timer? _reconnectTimer;
  bool _wsRunning = false;
  bool _wsConnecting = false;
  bool _stopRequested = false;
  int _reconnectAttempt = 0;
  WsConnectionStatus _wsStatus = WsConnectionStatus.disconnected;

  List<FavoriteGroupData> _favoriteGroups = const [];
  Map<String, String> _userFavoriteGroup = {}; // userId -> groupName

  Future<void>? _initializingFuture;

  Future<void> initialize(VrchatDart api) {
    final running = _initializingFuture;
    if (running != null) return running;

    final future = _doInitialize(api);
    _initializingFuture = future.whenComplete(() {
      _initializingFuture = null;
    });
    return _initializingFuture!;
  }

  Future<void> _doInitialize(VrchatDart api) async {
    clearAll(notify: false);
    await loadOnlineFriends(api);
    await loadOfflineFriendIds(api);
    await loadFavoriteData(api);
    notifyListeners();
  }

  Future<void> startRealtimeSync(VrchatDart api) async {
    _streamingApiRef = api;
    _stopRequested = false;
    if (_wsRunning || _wsConnecting) return;
    _updateWsStatus(notify: true);
    await _connectStreaming();
  }

  Future<void> ensureRealtimeSync(VrchatDart api) async {
    _streamingApiRef = api;
    if (_wsRunning || _wsConnecting) return;
    await startRealtimeSync(api);
  }

  Future<void> stopRealtimeSync() async {
    _stopRequested = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final sub = _wsSubscription;
    _wsSubscription = null;
    if (sub != null) {
      await sub.cancel();
    }

    try {
      _streamingApiRef?.streaming.stop();
    } catch (_) {
      // ignore
    }
    _wsRunning = false;
    _wsConnecting = false;
    _clearSelfLocationState();
    _updateWsStatus(notify: true);
  }

  Future<void> _connectStreaming() async {
    final api = _streamingApiRef;
    if (api == null ||
        _stopRequested ||
        _wsConnecting ||
        _wsSubscription != null) {
      return;
    }

    _wsConnecting = true;
    _updateWsStatus(notify: true);
    try {
      debugPrint('[WS] Connecting to VRChat WebSocket...');
      _wsSubscription = api.streaming.vrcEventStream.listen(
        (event) {
          _reconnectAttempt = 0;
          handleWebSocketEvent(event);
        },
        onError: (Object error) {
          debugPrint('[WS] Stream error: $error');
          _handleStreamingDisconnected();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _handleStreamingDisconnected();
        },
      );

      api.streaming.start();
      _wsRunning = true;
      _updateWsStatus(notify: true);
      debugPrint('[WS] Connection started');
    } catch (e) {
      debugPrint('[WS] Connection start failed: $e');
      _wsRunning = false;
      final sub = _wsSubscription;
      _wsSubscription = null;
      await sub?.cancel();
      _scheduleReconnect();
    } finally {
      _wsConnecting = false;
      _updateWsStatus(notify: true);
    }
  }

  void _handleStreamingDisconnected() {
    _wsRunning = false;
    final sub = _wsSubscription;
    _wsSubscription = null;
    unawaited(sub?.cancel());
    _updateWsStatus(notify: true);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopRequested || _reconnectTimer != null || _streamingApiRef == null) {
      return;
    }

    const delays = <int>[1, 2, 5, 5, 10];
    final index = _reconnectAttempt >= delays.length
        ? delays.length - 1
        : _reconnectAttempt;
    final seconds = delays[index];
    _reconnectAttempt += 1;

    debugPrint('[WS] Reconnecting in ${seconds}s...');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      _updateWsStatus(notify: true);
      unawaited(_connectStreaming());
    });
    _updateWsStatus(notify: true);
  }

  WsConnectionStatus get wsConnectionStatus => _wsStatus;

  void _updateWsStatus({required bool notify}) {
    final next = _wsRunning
        ? WsConnectionStatus.connected
        : (_wsConnecting || _reconnectTimer != null)
        ? WsConnectionStatus.connecting
        : WsConnectionStatus.disconnected;
    if (next == _wsStatus) return;
    _wsStatus = next;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> loadFavoriteData(VrchatDart api) async {
    try {
      final (groupsSuccess, _) = await api.rawApi
          .getFavoritesApi()
          .getFavoriteGroups(n: 100)
          .validateVrc();

      final groups =
          (groupsSuccess?.data ?? const <FavoriteGroup>[])
              .where((g) => g.type == FavoriteType.friend)
              .map(
                (g) =>
                    FavoriteGroupData(name: g.name, displayName: g.displayName),
              )
              .toList()
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
            );

      _favoriteGroups = List.unmodifiable(groups);

      final userFavoriteGroup = <String, String>{};
      const pageSize = 100;
      var offset = 0;

      while (true) {
        final (favoritesSuccess, _) = await api.rawApi
            .getFavoritesApi()
            .getFavorites(type: 'friend', n: pageSize, offset: offset)
            .validateVrc();

        final page = favoritesSuccess?.data ?? const <Favorite>[];
        for (final item in page) {
          if (item.favoriteId.isEmpty) continue;
          final tag = item.tags.firstWhere(
            (t) => t.trim().isNotEmpty,
            orElse: () => '',
          );
          if (tag.isNotEmpty &&
              !userFavoriteGroup.containsKey(item.favoriteId)) {
            userFavoriteGroup[item.favoriteId] = tag;
          }
        }

        if (page.length < pageSize) break;
        offset += page.length;
      }

      _userFavoriteGroup = userFavoriteGroup;
    } catch (_) {
      // ignore
    }
  }

  Future<void> loadOnlineFriends(VrchatDart api) async {
    final online = await _fetchAllFriends(api: api, offline: false);

    for (final friend in online) {
      _allFriendIds.add(friend.id);
      _onlineFriendIds.add(friend.id);
      _limitedUsers[friend.id] = friend;
    }

    await Future.wait(
      online.map((f) => loadUser(f.id, api.rawApi, notify: false)),
    );
  }

  Future<void> loadOfflineFriendIds(VrchatDart api) async {
    final offline = await _fetchAllFriends(api: api, offline: true);

    for (final friend in offline) {
      _allFriendIds.add(friend.id);
      _limitedUsers[friend.id] = friend;
      final avatarFileId = _extractAvatarFileIdFromLimitedUser(friend);
      if (avatarFileId != null) {
        _avatarFileIdByUserId[friend.id] = avatarFileId;
      }
      final headerFileId = _extractHeaderFileIdFromLimitedUser(friend);
      if (headerFileId != null) {
        _headerFileIdByUserId[friend.id] = headerFileId;
      }
    }
  }

  Future<User?> loadUser(
    String userId,
    VrchatDartGenerated api, {
    bool notify = true,
  }) {
    final id = userId.trim();
    if (id.isEmpty) return Future<User?>.value(null);

    final cached = _users[id];
    if (cached != null) return Future<User?>.value(cached);

    final loading = _loadingUserById[id];
    if (loading != null) return loading;

    final future = _fetchUser(id, api, notify: notify);
    _loadingUserById[id] = future;
    return future.whenComplete(() {
      _loadingUserById.remove(id);
    });
  }

  Future<User?> _fetchUser(
    String userId,
    VrchatDartGenerated api, {
    required bool notify,
  }) async {
    try {
      final (success, _) = await api
          .getUsersApi()
          .getUser(userId: userId)
          .validateVrc();
      final user = success?.data;
      if (user == null) return null;

      _setUser(user);
      _allFriendIds.add(userId);
      if (notify) notifyListeners();
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<List<MutualFriend>?> loadMutualFriends(
    String userId,
    VrchatDartGenerated api, {
    bool notify = true,
  }) {
    final id = userId.trim();
    if (id.isEmpty) return Future<List<MutualFriend>?>.value(null);

    final cached = _mutualFriends[id];
    if (cached != null) return Future<List<MutualFriend>?>.value(cached);

    final loading = _loadingMutualFriendsById[id];
    if (loading != null) return loading;

    final future = _fetchMutualFriends(id, api, notify: notify);
    _loadingMutualFriendsById[id] = future;
    return future.whenComplete(() {
      _loadingMutualFriendsById.remove(id);
    });
  }

  Future<List<MutualFriend>?> _fetchMutualFriends(
    String userId,
    VrchatDartGenerated api, {
    required bool notify,
  }) async {
    try {
      final (success, _) = await api
          .getUsersApi()
          .getMutualFriends(userId: userId, n: 100)
          .validateVrc();
      final friends = success?.data;
      if (friends == null) return null;

      _mutualFriends[userId] = friends;
      if (notify) notifyListeners();
      return friends;
    } catch (_) {
      return null;
    }
  }

  Future<FriendStatus?> loadFriendStatus(
    String userId,
    VrchatDartGenerated api, {
    bool notify = true,
  }) {
    final id = userId.trim();
    if (id.isEmpty) return Future<FriendStatus?>.value(null);

    final cached = _friendStatuses[id];
    if (cached != null) return Future<FriendStatus?>.value(cached);

    final loading = _loadingFriendStatusById[id];
    if (loading != null) return loading;

    final future = _fetchFriendStatus(id, api, notify: notify);
    _loadingFriendStatusById[id] = future;
    return future.whenComplete(() {
      _loadingFriendStatusById.remove(id);
    });
  }

  Future<FriendStatus?> _fetchFriendStatus(
    String userId,
    VrchatDartGenerated api, {
    required bool notify,
  }) async {
    try {
      final (success, _) = await api
          .getFriendsApi()
          .getFriendStatus(userId: userId)
          .validateVrc();
      final status = success?.data;
      if (status == null) return null;

      _friendStatuses[userId] = status;
      if (notify) notifyListeners();
      return status;
    } catch (_) {
      return null;
    }
  }

  void handleWebSocketEvent(VrcStreamingEvent event) {
    if (event is ErrorEvent) return;

    switch (event.type) {
      case VrcStreamingEventType.friendOnline:
        final e = event as FriendOnlineEvent;
        _allFriendIds.add(e.user.id);
        _onlineFriendIds.add(e.user.id);
        if (e.location != null && e.location!.isNotEmpty) {
          _locationByUserId[e.user.id] = e.location!;
        }
        _setEventWorldName(e.user.id, e.world?.name);
        _cacheWorldFromEvent(world: e.world, location: e.location);
        _setUser(e.user);
        break;
      case VrcStreamingEventType.friendLocation:
        final e = event as FriendLocationEvent;
        _allFriendIds.add(e.user.id);
        _onlineFriendIds.add(e.user.id);
        if (e.location != null && e.location!.isNotEmpty) {
          _locationByUserId[e.user.id] = e.location!;
        }
        _setEventWorldName(e.user.id, e.world?.name);
        _cacheWorldFromEvent(world: e.world, location: e.location);
        _setUser(e.user);
        break;
      case VrcStreamingEventType.friendOffline:
        final e = event as FriendOfflineEvent;
        _allFriendIds.add(e.userId);
        _onlineFriendIds.remove(e.userId);
        _locationByUserId.remove(e.userId);
        _eventWorldNameByUserId.remove(e.userId);
        break;
      case VrcStreamingEventType.friendAdd:
        final e = event as FriendAddEvent;
        _allFriendIds.add(e.user.id);
        _setUser(e.user);
        if (e.user.status != UserStatus.offline) {
          _onlineFriendIds.add(e.user.id);
        }
        break;
      case VrcStreamingEventType.friendDelete:
        final e = event as FriendDeleteEvent;
        _allFriendIds.remove(e.userId);
        _onlineFriendIds.remove(e.userId);
        _limitedUsers.remove(e.userId);
        _users.remove(e.userId);
        _avatarFileIdByUserId.remove(e.userId);
        _headerFileIdByUserId.remove(e.userId);
        _locationByUserId.remove(e.userId);
        _eventWorldNameByUserId.remove(e.userId);
        _mutualFriends.remove(e.userId);
        _friendStatuses.remove(e.userId);
        break;
      case VrcStreamingEventType.friendActive:
        final e = event as FriendActiveEvent;
        _allFriendIds.add(e.user.id);
        _onlineFriendIds.add(e.user.id);
        _setUser(e.user);
        break;
      case VrcStreamingEventType.friendUpdate:
        final e = event as FriendUpdateEvent;
        _setUser(e.user);
        if (!_onlineFriendIds.contains(e.user.id) &&
            e.user.status != UserStatus.offline) {
          _onlineFriendIds.add(e.user.id);
        } else if (_onlineFriendIds.contains(e.user.id) &&
            e.user.status == UserStatus.offline) {
          _onlineFriendIds.remove(e.user.id);
        }
        break;
      case VrcStreamingEventType.userLocation:
        final e = event as UserLocationEvent;
        _setSelfLocationState(
          location: e.location,
          instance: e.instance,
          worldName: e.world?.name,
        );
        _cacheWorldFromEvent(world: e.world, location: e.location);
        break;
      default:
        return;
    }

    notifyListeners();
  }

  List<User> getAllFriends() {
    final result = _onlineFriendIds
        .map((id) => _users[id])
        .whereType<User>()
        .toList();
    result.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return result;
  }

  List<String> getFriendIds() {
    final ids = _allFriendIds.toList();
    ids.sort();
    return ids;
  }

  List<String> getOnlineFriendIds() {
    final ids = _onlineFriendIds.toList();
    ids.sort();
    return ids;
  }

  User? getUser(String userId) => _users[userId];

  String? getAvatarFileId(String userId) => _avatarFileIdByUserId[userId];

  UserAvatarInfo? getAvatarInfo(String userId) {
    final user = _users[userId];
    if (user != null) {
      return UserAvatarInfo.fromUser(user);
    }

    final limited = _limitedUsers[userId];
    if (limited != null) {
      return UserAvatarInfo.fromLimitedUser(limited);
    }

    return null;
  }

  String? getHeaderFileId(String userId) => _headerFileIdByUserId[userId];

  String? getEventLocation(String userId) => _locationByUserId[userId];

  String? getEventWorldName(String userId) => _eventWorldNameByUserId[userId];

  String? getSelfLocation() => _selfLocation;

  String? getSelfInstance() => _selfInstance;

  String? getSelfEventWorldName() => _selfEventWorldName;

  String? getSelfWorldId() => _selfWorldId;

  Color trustColorForTags(List<String> tags) {
    final trustTags = tags.map((e) => e.toLowerCase()).toSet();
    if (trustTags.contains('system_trust_veteran')) {
      return _trustVeteranColor;
    }
    if (trustTags.contains('system_trust_trusted')) {
      return _trustTrustedColor;
    }
    if (trustTags.contains('system_trust_known')) {
      return _trustKnownColor;
    }
    if (trustTags.contains('system_trust_basic')) {
      return _trustBasicColor;
    }
    return _trustDefaultColor;
  }

  void _setUser(User user) {
    _users[user.id] = user;
    final avatarFileId = _extractAvatarFileId(user);
    if (avatarFileId != null) {
      _avatarFileIdByUserId[user.id] = avatarFileId;
    }
    final headerFileId = _extractHeaderFileId(user);
    if (headerFileId != null) {
      _headerFileIdByUserId[user.id] = headerFileId;
    }
  }

  void _cacheWorldFromEvent({
    required World? world,
    required String? location,
  }) {
    final _ = location; // reserved for future fallback parsing
    if (world == null) return;
    unawaited(WorldStore.instance.putWorld(world));
  }

  void _setEventWorldName(String userId, String? worldName) {
    final next = worldName?.trim() ?? '';
    if (next.isEmpty) return;
    _eventWorldNameByUserId[userId] = next;
  }

  void _setSelfLocationState({
    required String? location,
    required String? instance,
    required String? worldName,
  }) {
    final normalizedLocation = location?.trim() ?? '';
    final normalizedInstance = instance?.trim() ?? '';
    final normalizedWorldName = worldName?.trim() ?? '';
    final parsed = cache.CacheManager.parseLocation(normalizedLocation);

    _selfLocation = normalizedLocation.isEmpty ? null : normalizedLocation;
    _selfInstance = normalizedInstance.isEmpty ? null : normalizedInstance;
    _selfWorldId = parsed?.worldId;
    _selfEventWorldName = normalizedWorldName.isEmpty
        ? null
        : normalizedWorldName;

    final lower = normalizedLocation.toLowerCase();
    if (lower == 'offline') {
      _clearSelfLocationState();
    }
  }

  void _clearSelfLocationState() {
    _selfLocation = null;
    _selfInstance = null;
    _selfEventWorldName = null;
    _selfWorldId = null;
  }

  static String? _extractAvatarFileId(User user) {
    final userIcon = user.userIcon.trim();
    if (userIcon.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(userIcon);
    }

    final profilePic = user.profilePicOverride.trim();
    if (profilePic.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(profilePic);
    }

    final avatarImg = user.currentAvatarImageUrl.trim();
    if (avatarImg.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(avatarImg);
    }

    return null;
  }

  static String? _extractHeaderFileId(User user) {
    final profilePic = user.profilePicOverride.trim();
    if (profilePic.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(profilePic);
    }

    final avatarImg = user.currentAvatarImageUrl.trim();
    if (avatarImg.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(avatarImg);
    }

    return null;
  }

  static String? _extractAvatarFileIdFromLimitedUser(LimitedUserFriend user) {
    final userIcon = user.userIcon?.trim() ?? '';
    if (userIcon.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(userIcon);
    }

    final profilePic = user.profilePicOverride?.trim() ?? '';
    if (profilePic.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(profilePic);
    }

    final avatarImg = user.currentAvatarImageUrl?.trim() ?? '';
    if (avatarImg.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(avatarImg);
    }

    return null;
  }

  static String? _extractHeaderFileIdFromLimitedUser(LimitedUserFriend user) {
    final profilePic = user.profilePicOverride?.trim() ?? '';
    if (profilePic.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(profilePic);
    }

    final avatarImg = user.currentAvatarImageUrl?.trim() ?? '';
    if (avatarImg.isNotEmpty) {
      return cache.ImageCache.extractFileIdFromUrl(avatarImg);
    }

    return null;
  }

  LimitedUserFriend? getLimitedUser(String userId) => _limitedUsers[userId];

  List<MutualFriend>? getMutualFriends(String userId) => _mutualFriends[userId];

  FriendStatus? getFriendStatus(String userId) => _friendStatuses[userId];

  bool isFriend(String userId) => _friendStatuses[userId]?.isFriend ?? false;

  bool isUserOnline(String userId) => _onlineFriendIds.contains(userId);

  List<User> getSortedOnlineFriends({Set<String>? favoriteIds}) {
    final result = _onlineFriendIds
        .map((id) => _users[id])
        .whereType<User>()
        .toList();

    result.sort((a, b) {
      final aFavorite = favoriteIds?.contains(a.id) ?? false;
      final bFavorite = favoriteIds?.contains(b.id) ?? false;
      if (aFavorite != bFavorite) return aFavorite ? -1 : 1;

      final aPriority = _statusPriority(a.status);
      final bPriority = _statusPriority(b.status);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return result;
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

  List<FavoriteGroupData> getFavoriteGroups() =>
      List.unmodifiable(_favoriteGroups);

  String? getFavoriteGroupForUser(String userId) => _userFavoriteGroup[userId];

  Set<String> getFavoriteFriendIds() {
    return _userFavoriteGroup.keys.toSet();
  }

  void setUserFavoriteGroup(String userId, String? groupName) {
    final newMap = Map<String, String>.from(_userFavoriteGroup);
    if (groupName == null || groupName.isEmpty) {
      newMap.remove(userId);
    } else {
      newMap[userId] = groupName;
    }
    _userFavoriteGroup = newMap;
    notifyListeners();
  }

  void clearAll({bool notify = true}) {
    _allFriendIds.clear();
    _onlineFriendIds.clear();
    _users.clear();
    _avatarFileIdByUserId.clear();
    _headerFileIdByUserId.clear();
    _limitedUsers.clear();
    _eventWorldNameByUserId.clear();
    _mutualFriends.clear();
    _friendStatuses.clear();
    _loadingUserById.clear();
    _loadingMutualFriendsById.clear();
    _loadingFriendStatusById.clear();
    _favoriteGroups = const [];
    _userFavoriteGroup = {};
    _clearSelfLocationState();
    if (notify) notifyListeners();
  }

  Future<List<LimitedUserFriend>> _fetchAllFriends({
    required VrchatDart api,
    required bool offline,
  }) async {
    final result = <LimitedUserFriend>[];
    var offset = 0;

    while (true) {
      final (success, _) = await api.rawApi
          .getFriendsApi()
          .getFriends(offline: offline, n: _pageSize, offset: offset)
          .validateVrc();
      final page = success?.data ?? const <LimitedUserFriend>[];
      result.addAll(page);
      if (page.length < _pageSize) break;
      offset += page.length;
    }

    return result;
  }
}
