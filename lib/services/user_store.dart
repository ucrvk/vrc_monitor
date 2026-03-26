import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class FavoriteGroupData {
  const FavoriteGroupData({required this.name, required this.displayName});

  final String name;
  final String displayName;
}

class UserStore extends ChangeNotifier {
  UserStore._();

  static final UserStore instance = UserStore._();

  static const int _pageSize = 100;

  final Set<String> _allFriendIds = <String>{};
  final Set<String> _onlineFriendIds = <String>{};
  final Map<String, User> _users = <String, User>{};
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

      _users[userId] = user;
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
        _users[e.user.id] = e.user;
        break;
      case VrcStreamingEventType.friendLocation:
        final e = event as FriendLocationEvent;
        _allFriendIds.add(e.user.id);
        _onlineFriendIds.add(e.user.id);
        _users[e.user.id] = e.user;
        break;
      case VrcStreamingEventType.friendOffline:
        final e = event as FriendOfflineEvent;
        _allFriendIds.add(e.userId);
        _onlineFriendIds.remove(e.userId);
        break;
      case VrcStreamingEventType.friendAdd:
        final e = event as FriendAddEvent;
        _allFriendIds.add(e.user.id);
        _users[e.user.id] = e.user;
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
        _mutualFriends.remove(e.userId);
        _friendStatuses.remove(e.userId);
        break;
      case VrcStreamingEventType.friendActive:
        final e = event as FriendActiveEvent;
        _allFriendIds.add(e.user.id);
        _onlineFriendIds.add(e.user.id);
        _users[e.user.id] = e.user;
        break;
      case VrcStreamingEventType.friendUpdate:
        final e = event as FriendUpdateEvent;
        _users[e.user.id] = e.user;
        if (!_onlineFriendIds.contains(e.user.id) &&
            e.user.status != UserStatus.offline) {
          _onlineFriendIds.add(e.user.id);
        } else if (_onlineFriendIds.contains(e.user.id) &&
            e.user.status == UserStatus.offline) {
          _onlineFriendIds.remove(e.user.id);
        }
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
    _limitedUsers.clear();
    _mutualFriends.clear();
    _friendStatuses.clear();
    _loadingUserById.clear();
    _loadingMutualFriendsById.clear();
    _loadingFriendStatusById.clear();
    _favoriteGroups = const [];
    _userFavoriteGroup = {};
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
