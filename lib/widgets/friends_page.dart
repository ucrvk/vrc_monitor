import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';
import 'package:vrc_monitor/widgets/friend_search_page.dart';
import 'package:vrc_monitor/widgets/login_page.dart';
import 'package:vrc_monitor/widgets/me_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.api, required this.currentUser});

  final VrchatDart api;
  final CurrentUser currentUser;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  static const int _pageSize = 100;

  bool _loading = true;
  String? _error;
  int _currentTabIndex = 0;
  List<_FriendEntry> _friends = const [];
  final Map<String, String> _worldNameById = {};
  final Map<String, String> _instanceTypeByLocation = {};
  Timer? _refreshCooldownTimer;
  StreamSubscription<VrcStreamingEvent>? _wsSubscription;
  int _refreshCooldownSeconds = 0;
  bool _onlineExpanded = true;
  bool _webExpanded = true;
  bool _offlineExpanded = false;
  List<_FavoriteFriendGroupView> _favoriteFriendGroups = const [];
  final Map<String, bool> _favoriteGroupExpandedByName = {};
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTabIndex);
    _startStreamingSync();
    _loadFriends();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _refreshCooldownTimer?.cancel();
    _wsSubscription?.cancel();
    widget.api.streaming.stop();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final onlineFuture = _fetchAllFriends(offline: false);
    final offlineFuture = _fetchAllFriends(offline: true);
    final favoritesFuture = _fetchFavoriteFriendGroups();

    final (onlineFriends, onlineFailure) = await onlineFuture;
    final (offlineFriends, offlineFailure) = await offlineFuture;
    final favoriteFriendGroups = await favoritesFuture;

    if (!mounted) return;

    if (onlineFriends.isEmpty && offlineFriends.isEmpty) {
      setState(() {
        _loading = false;
        _error = _extractFailureText(onlineFailure ?? offlineFailure);
      });
      return;
    }

    final Map<String, LimitedUserFriend> merged = {};
    for (final friend in onlineFriends) {
      merged[friend.id] = friend;
    }
    for (final friend in offlineFriends) {
      merged[friend.id] = friend;
    }

    final friends =
        merged.values.map(_FriendEntry.fromLimitedUserFriend).toList()
          ..sort(_sortFriends);

    setState(() {
      _loading = false;
      _friends = friends;
      _favoriteFriendGroups = favoriteFriendGroups;
      _error = null;
    });
    _syncFavoriteGroupExpansionState(favoriteFriendGroups);

    _resolveLocationDetails(friends);
  }

  Future<(List<LimitedUserFriend>, InvalidResponse?)> _fetchAllFriends({
    required bool offline,
  }) async {
    final List<LimitedUserFriend> result = [];
    InvalidResponse? lastFailure;
    var offset = 0;

    while (true) {
      final (success, failure) = await _runVrcRequest(
        () => widget.api.rawApi
            .getFriendsApi()
            .getFriends(offline: offline, n: _pageSize, offset: offset)
            .validateVrc(),
      );

      if (success == null) {
        lastFailure = failure;
        break;
      }

      final page = success.data;
      result.addAll(page);
      if (page.length < _pageSize) break;

      offset += page.length;
    }

    return (result, lastFailure);
  }

  Future<List<_FavoriteFriendGroupView>> _fetchFavoriteFriendGroups() async {
    final (groupsSuccess, _) = await _runVrcRequest(
      () => widget.api.rawApi
          .getFavoritesApi()
          .getFavoriteGroups(n: 100)
          .validateVrc(),
    );
    if (groupsSuccess == null) return const [];

    final friendGroups =
        groupsSuccess.data.where((g) => g.type == FavoriteType.friend).toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    if (friendGroups.isEmpty) return const [];

    final friendIdsByGroupName = <String, Set<String>>{
      for (final group in friendGroups) group.name: <String>{},
    };

    var offset = 0;
    while (true) {
      final (favoritesSuccess, _) = await _runVrcRequest(
        () => widget.api.rawApi
            .getFavoritesApi()
            .getFavorites(type: 'friend', n: _pageSize, offset: offset)
            .validateVrc(),
      );
      if (favoritesSuccess == null) break;

      final page = favoritesSuccess.data;
      for (final favorite in page) {
        for (final tag in favorite.tags) {
          final friendIds = friendIdsByGroupName[tag];
          if (friendIds != null) {
            friendIds.add(favorite.favoriteId);
          }
        }
      }

      if (page.length < _pageSize) break;
      offset += page.length;
    }

    return friendGroups
        .map(
          (group) => _FavoriteFriendGroupView(
            name: group.name,
            displayName: group.displayName,
            friendIds: friendIdsByGroupName[group.name] ?? const {},
          ),
        )
        .toList();
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

  String _extractFailureText(InvalidResponse? failure) {
    if (failure == null) return '获取好友失败，未返回错误详情。';

    final responseData = failure.response?.data;
    if (responseData is Map<String, dynamic>) {
      final errorMap = responseData['error'];
      if (errorMap is Map<String, dynamic> && errorMap['message'] != null) {
        return errorMap['message'].toString();
      }

      final message = responseData['message'];
      if (message != null) return message.toString();
    }

    return failure.error.toString();
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

  Future<void> _logout() async {
    _wsSubscription?.cancel();
    widget.api.streaming.stop();
    await widget.api.auth.logout();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _startStreamingSync() {
    _wsSubscription = widget.api.streaming.vrcEventStream.listen(
      _onWsEvent,
      onError: (Object error) {
        debugPrint('WS stream error: $error');
      },
    );
    widget.api.streaming.start();
  }

  void _onWsEvent(VrcStreamingEvent event) {
    if (!mounted) return;

    if (event is ErrorEvent) {
      debugPrint('WS event error: ${event.message}');
      return;
    }

    switch (event.type) {
      case VrcStreamingEventType.friendOnline:
        final e = event as FriendOnlineEvent;
        _upsertFriendFromWsUser(
          e.user,
          statusOverride: UserStatus.active,
          locationOverride: e.location,
        );
        break;
      case VrcStreamingEventType.friendLocation:
        final e = event as FriendLocationEvent;
        _upsertFriendFromWsUser(
          e.user,
          statusOverride: e.user.status,
          locationOverride: e.location,
        );
        break;
      case VrcStreamingEventType.friendUpdate:
        final e = event as FriendUpdateEvent;
        _upsertFriendFromWsUser(
          e.user,
          statusOverride: e.user.status,
          locationOverride: e.user.location,
        );
        break;
      case VrcStreamingEventType.friendActive:
        final e = event as FriendActiveEvent;
        _upsertFriendFromWsUser(
          e.user,
          statusOverride: UserStatus.active,
          locationOverride: 'offline',
          platformOverride: 'web',
        );
        break;
      case VrcStreamingEventType.friendAdd:
        final e = event as FriendAddEvent;
        _upsertFriendFromWsUser(
          e.user,
          statusOverride: e.user.status,
          locationOverride: e.user.location,
        );
        break;
      case VrcStreamingEventType.friendOffline:
        final e = event as FriendOfflineEvent;
        _markFriendOffline(e.userId);
        break;
      case VrcStreamingEventType.friendDelete:
        final e = event as FriendDeleteEvent;
        _removeFriend(e.userId);
        break;
      case VrcStreamingEventType.userUpdate:
      case VrcStreamingEventType.userLocation:
      case VrcStreamingEventType.notificationReceived:
      case VrcStreamingEventType.notificationSeen:
      case VrcStreamingEventType.notificationResponse:
      case VrcStreamingEventType.notificationHide:
      case VrcStreamingEventType.notificationClear:
      case VrcStreamingEventType.error:
      case VrcStreamingEventType.unknown:
        break;
    }
  }

  void _upsertFriendFromWsUser(
    User user, {
    required UserStatus statusOverride,
    String? locationOverride,
    String? platformOverride,
  }) {
    final index = _friends.indexWhere((f) => f.id == user.id);
    final location = (locationOverride ?? user.location ?? 'offline').trim();
    final updated = _FriendEntry.fromWsUser(
      user,
      status: statusOverride,
      location: location.isEmpty ? 'offline' : location,
      lastPlatform: platformOverride ?? user.lastPlatform,
    );

    if (index == -1) {
      setState(() {
        _friends = [..._friends, updated]..sort(_sortFriends);
      });
    } else {
      final next = [..._friends];
      next[index] = updated;
      next.sort(_sortFriends);
      setState(() {
        _friends = next;
      });
    }

    _resolveLocationDetails(_friends);
  }

  void _markFriendOffline(String userId) {
    final index = _friends.indexWhere((f) => f.id == userId);
    if (index == -1) return;

    final next = [..._friends];
    next[index] = next[index].copyWith(
      status: UserStatus.offline,
      location: 'offline',
    );
    next.sort(_sortFriends);
    setState(() {
      _friends = next;
    });
  }

  void _removeFriend(String userId) {
    final next = _friends.where((f) => f.id != userId).toList();
    if (next.length == _friends.length) return;
    setState(() {
      _friends = next;
    });
  }

  int _sortFriends(_FriendEntry a, _FriendEntry b) {
    final aOnline = a.status != UserStatus.offline;
    final bOnline = b.status != UserStatus.offline;
    if (aOnline != bOnline) return aOnline ? -1 : 1;

    if (aOnline && bOnline) {
      final aFavoritePriority = _onlineFavoritePriority(a.id);
      final bFavoritePriority = _onlineFavoritePriority(b.id);
      if (aFavoritePriority != bFavoritePriority) {
        return aFavoritePriority.compareTo(bFavoritePriority);
      }
    }

    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  int _statusPriorityForGroup(UserStatus status) {
    switch (status) {
      case UserStatus.joinMe:
        return 0; // blue
      case UserStatus.active:
        return 1; // green
      case UserStatus.askMe:
        return 2; // orange
      case UserStatus.busy:
        return 3; // red
      case UserStatus.offline:
        return 4; // gray
    }
  }

  List<_FriendEntry> _sortedForGroup(List<_FriendEntry> friends) {
    final sorted = [...friends];
    sorted.sort((a, b) {
      final aPriority = _statusPriorityForGroup(a.status);
      final bPriority = _statusPriorityForGroup(b.status);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return sorted;
  }

  int _onlineFavoritePriority(String friendId) {
    for (var i = 0; i < _favoriteFriendGroups.length; i++) {
      if (_favoriteFriendGroups[i].friendIds.contains(friendId)) {
        return i;
      }
    }
    return _favoriteFriendGroups.length + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTabIndex == 0 ? '好友位置 (${_friends.length})' : '我'),
        actions: [
          if (_currentTabIndex == 0)
            IconButton(
              onPressed: _loading ? null : _openFriendSearchPage,
              tooltip: '搜索好友',
              icon: const Icon(Icons.search),
            ),
          if (_currentTabIndex == 0)
            IconButton(
              onPressed: _loading || _refreshCooldownSeconds > 0
                  ? null
                  : _onRefreshPressed,
              tooltip: _refreshCooldownSeconds > 0
                  ? '刷新 (${_refreshCooldownSeconds}s)'
                  : '刷新',
              icon: const Icon(Icons.refresh),
            ),
          if (_currentTabIndex == 1)
            IconButton(
              onPressed: _logout,
              tooltip: '退出登录',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        children: [
          _buildFriendsBody(),
          MePage(currentUser: widget.currentUser),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: '好友位置',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('错误: $_error'),
        ),
      );
    }

    if (_friends.isEmpty) {
      return const Center(child: Text('暂无好友数据'));
    }

    final grouped = _groupFriends(_friends);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildOnlineGroupSection(grouped.online),
        _buildGroupSection(
          title: '在网页或其他端登录',
          friends: grouped.webOrOtherClient,
          expanded: _webExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _webExpanded = value;
            });
          },
        ),
        _buildGroupSection(
          title: '离线',
          friends: grouped.offline,
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

  Widget _buildGroupSection({
    required String title,
    required List<_FriendEntry> friends,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
  }) {
    final sortedFriends = _sortedForGroup(friends);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text('$title (${friends.length})'),
        children: _buildFriendRows(sortedFriends),
      ),
    );
  }

  Widget _buildOnlineGroupSection(List<_FriendEntry> onlineFriends) {
    final favoriteSections = <Widget>[];
    final assignedFriendIds = <String>{};

    for (final favoriteGroup in _favoriteFriendGroups) {
      final members = onlineFriends
          .where((f) => favoriteGroup.friendIds.contains(f.id))
          .toList();
      final sortedMembers = _sortedForGroup(members);
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
          children: _buildFriendRows(sortedMembers),
        ),
      );
    }

    final others = _sortedForGroup(
      onlineFriends.where((f) => !assignedFriendIds.contains(f.id)).toList(),
    );

    if (favoriteSections.isNotEmpty) {
      favoriteSections.add(
        ExpansionTile(
          initiallyExpanded: true,
          title: Text('其他在线 (${others.length})'),
          children: _buildFriendRows(others),
        ),
      );
    } else {
      favoriteSections.addAll(_buildFriendRows(_sortedForGroup(onlineFriends)));
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

  List<Widget> _buildFriendRows(List<_FriendEntry> friends) {
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
        _FriendRow(
          friend: friends[i],
          dio: widget.api.rawApi.dio,
          locationText: _locationTextFor(friends[i]),
          onTap: () => _openFriendDetailPage(friends[i]),
        ),
        if (i != friends.length - 1) const Divider(height: 1),
      ],
    ];
  }

  Future<void> _onRefreshPressed() async {
    _startRefreshCooldown();
    await _loadFriends();
  }

  Future<void> _openFriendSearchPage() async {
    final searchUsers = _friends.map(_toSearchUser).toList();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendSearchPage(
          friends: searchUsers,
          dio: widget.api.rawApi.dio,
          rawApi: widget.api.rawApi,
          onOpenDetail: _openFriendDetailFromSearchUser,
        ),
      ),
    );
  }

  FriendSearchUser _toSearchUser(_FriendEntry friend) {
    return FriendSearchUser(
      id: friend.id,
      displayName: friend.displayName,
      status: friend.status,
      location: friend.location,
      locationText: _locationTextFor(friend),
      lastPlatform: friend.lastPlatform,
      tags: friend.tags,
      bio: friend.bio,
      statusDescription: friend.statusDescription,
      pronouns: friend.pronouns,
      bioLinks: friend.bioLinks,
      dateJoined: friend.dateJoined,
      lastActivity: friend.lastActivity,
      profilePicOverrideThumbnail: friend.profilePicOverrideThumbnail,
      profilePicOverride: friend.profilePicOverride,
      currentAvatarThumbnailImageUrl: friend.currentAvatarThumbnailImageUrl,
      userIcon: friend.userIcon,
      imageUrl: friend.imageUrl,
      isFriend: true,
    );
  }

  Future<void> _openFriendDetailFromSearchUser(FriendSearchUser user) async {
    final index = _friends.indexWhere((f) => f.id == user.id);
    final entry = index >= 0 ? _friends[index] : _FriendEntry.fromSearchUser(user);
    await _openFriendDetailPage(entry, isFriend: user.isFriend);
  }

  Future<void> _openFriendDetailPage(_FriendEntry friend, {bool isFriend = true}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendDetailPage(
          dio: widget.api.rawApi.dio,
          userId: friend.id,
          displayName: friend.displayName,
          avatarUrl: friend.smallAvatarUrl,
          imageUrl: friend.imageUrl,
          location: friend.location,
          isFriend: isFriend,
          bio: friend.bio,
          nameColor: friend.trustColor,
          status: friend.status,
          statusDescription: friend.statusDescription,
          pronouns: friend.pronouns,
          bioLinks: friend.bioLinks,
          dateJoined: friend.dateJoined,
          lastActivity: friend.lastActivity,
          rawApi: widget.api.rawApi,
        ),
      ),
    );
  }

  void _startRefreshCooldown() {
    _refreshCooldownTimer?.cancel();
    setState(() {
      _refreshCooldownSeconds = 60;
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

  _FriendGroups _groupFriends(List<_FriendEntry> friends) {
    final List<_FriendEntry> online = [];
    final List<_FriendEntry> webOrOtherClient = [];
    final List<_FriendEntry> offline = [];

    for (final friend in friends) {
      if (friend.status == UserStatus.offline) {
        offline.add(friend);
      } else if (_isWebOrOtherClient(friend)) {
        webOrOtherClient.add(friend);
      } else {
        online.add(friend);
      }
    }

    return _FriendGroups(
      online: online,
      webOrOtherClient: webOrOtherClient,
      offline: offline,
    );
  }

  bool _isWebOrOtherClient(_FriendEntry friend) {
    return friend.status != UserStatus.offline &&
        friend.location.trim().toLowerCase() == 'offline';
  }

  Future<void> _resolveLocationDetails(List<_FriendEntry> friends) async {
    final Set<String> worldIds = {};
    final List<(String, String, String)> worldInstances = [];

    for (final friend in friends) {
      final parsed = _parseLocation(friend.location);
      final worldId = parsed?.worldId;
      if (worldId != null && !_worldNameById.containsKey(worldId)) {
        worldIds.add(worldId);
      }
      if (parsed != null && !_instanceTypeByLocation.containsKey(parsed.raw)) {
        worldInstances.add((parsed.raw, parsed.worldId, parsed.instanceId));
      }
    }

    if (worldIds.isEmpty && worldInstances.isEmpty) return;

    var changed = false;
    final worldResults = await Future.wait([
      for (final worldId in worldIds)
        _runVrcRequest(
          () => widget.api.rawApi
              .getWorldsApi()
              .getWorld(worldId: worldId)
              .validateVrc(),
        ).then((result) => (worldId, result.$1)),
    ]);

    if (!mounted) return;
    for (final (worldId, success) in worldResults) {
      if (success != null) {
        _worldNameById[worldId] = success.data.name;
      } else {
        _worldNameById[worldId] = worldId;
      }
      changed = true;
    }

    final instanceResults = await Future.wait([
      for (final (raw, worldId, instanceId) in worldInstances)
        _runVrcRequest(
          () => widget.api.rawApi
              .getWorldsApi()
              .getWorldInstance(worldId: worldId, instanceId: instanceId)
              .validateVrc(),
        ).then((result) => (raw, result.$1)),
    ]);

    if (!mounted) return;
    for (final (raw, success) in instanceResults) {
      if (success != null) {
        _instanceTypeByLocation[raw] = _instanceTypeLabel(
          success.data.type,
          canRequestInvite: success.data.canRequestInvite ?? false,
        );
      }
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  String _locationTextFor(_FriendEntry friend) {
    final location = friend.location.trim();
    final lower = location.toLowerCase();
    if (friend.status != UserStatus.offline && _isWebOrOtherClient(friend)) {
      return '在网页或其他端登录';
    }
    if (lower.contains('private')) return '在私人房间';
    if (lower == 'offline') return '离线';

    final parsed = _parseLocation(location);
    if (parsed == null) return location;

    final worldName = _worldNameById[parsed.worldId];
    final base = (worldName == null || worldName == parsed.worldId)
        ? location
        : worldName;

    final typeLabel = _instanceTypeByLocation[parsed.raw];
    if (typeLabel == null || typeLabel.isEmpty) return base;
    return '$base - $typeLabel';
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
      raw: value,
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
}

class _ParsedLocation {
  const _ParsedLocation({
    required this.raw,
    required this.worldId,
    required this.instanceId,
  });

  final String raw;
  final String worldId;
  final String instanceId;
}

class _FriendEntry {
  const _FriendEntry({
    required this.id,
    required this.displayName,
    required this.status,
    required this.location,
    required this.lastPlatform,
    required this.tags,
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

  factory _FriendEntry.fromLimitedUserFriend(LimitedUserFriend friend) {
    return _FriendEntry.fromLimitedUser(
      friend.toLimitedUser(),
      status: friend.status,
      location: friend.location,
      lastPlatform: friend.lastPlatform,
    );
  }

  factory _FriendEntry.fromWsUser(
    User user, {
    required UserStatus status,
    required String location,
    required String lastPlatform,
  }) {
    final limited = user.toLimitedUser();
    return _FriendEntry(
      id: limited.id,
      displayName: limited.displayName,
      status: status,
      location: location,
      lastPlatform: lastPlatform,
      tags: limited.tags,
      bio: limited.bio,
      statusDescription: _normalizeText(limited.statusDescription),
      pronouns: _normalizeText(limited.pronouns),
      bioLinks: _normalizeBioLinks(limited.bioLinks),
      dateJoined: limited.dateJoined,
      lastActivity: limited.lastActivity ?? limited.lastLogin,
      profilePicOverrideThumbnail: limited.profilePicOverrideThumbnail,
      profilePicOverride: limited.profilePicOverride,
      currentAvatarThumbnailImageUrl: limited.currentAvatarThumbnailImageUrl,
      userIcon: limited.userIcon,
      imageUrl: limited.imageUrl ?? limited.currentAvatarImageUrl,
    );
  }

  factory _FriendEntry.fromLimitedUser(
    LimitedUser user, {
    required UserStatus status,
    required String location,
    required String lastPlatform,
  }) {
    return _FriendEntry(
      id: user.id,
      displayName: user.displayName,
      status: status,
      location: location,
      lastPlatform: lastPlatform,
      tags: user.tags,
      bio: user.bio,
      statusDescription: _normalizeText(user.statusDescription),
      pronouns: _normalizeText(user.pronouns),
      bioLinks: _normalizeBioLinks(user.bioLinks),
      dateJoined: user.dateJoined,
      lastActivity: user.lastActivity ?? user.lastLogin,
      profilePicOverrideThumbnail: user.profilePicOverrideThumbnail,
      profilePicOverride: user.profilePicOverride,
      currentAvatarThumbnailImageUrl: user.currentAvatarThumbnailImageUrl,
      userIcon: user.userIcon,
      imageUrl: user.imageUrl ?? user.currentAvatarImageUrl,
    );
  }

  factory _FriendEntry.fromSearchUser(FriendSearchUser user) {
    return _FriendEntry(
      id: user.id,
      displayName: user.displayName,
      status: user.status,
      location: user.location,
      lastPlatform: user.lastPlatform,
      tags: user.tags,
      bio: user.bio,
      statusDescription: user.statusDescription,
      pronouns: user.pronouns,
      bioLinks: user.bioLinks,
      dateJoined: user.dateJoined,
      lastActivity: user.lastActivity,
      profilePicOverrideThumbnail: user.profilePicOverrideThumbnail,
      profilePicOverride: user.profilePicOverride,
      currentAvatarThumbnailImageUrl: user.currentAvatarThumbnailImageUrl,
      userIcon: user.userIcon,
      imageUrl: user.imageUrl,
    );
  }

  static String? _normalizeText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static List<String> _normalizeBioLinks(List<String>? rawLinks) {
    if (rawLinks == null || rawLinks.isEmpty) return const [];
    final sanitized = rawLinks
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (sanitized.isEmpty) return const [];
    return sanitized;
  }

  final String id;
  final String displayName;
  final UserStatus status;
  final String location;
  final String lastPlatform;
  final List<String> tags;
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

  _FriendEntry copyWith({
    UserStatus? status,
    String? location,
    String? lastPlatform,
  }) {
    return _FriendEntry(
      id: id,
      displayName: displayName,
      status: status ?? this.status,
      location: location ?? this.location,
      lastPlatform: lastPlatform ?? this.lastPlatform,
      tags: tags,
      bio: bio,
      statusDescription: statusDescription,
      pronouns: pronouns,
      bioLinks: bioLinks,
      dateJoined: dateJoined,
      lastActivity: lastActivity,
      profilePicOverrideThumbnail: profilePicOverrideThumbnail,
      profilePicOverride: profilePicOverride,
      currentAvatarThumbnailImageUrl: currentAvatarThumbnailImageUrl,
      userIcon: userIcon,
      imageUrl: imageUrl,
    );
  }

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
    if (trustTags.contains('system_trust_veteran'))
      return const Color(0xFF8E44AD);
    if (trustTags.contains('system_trust_trusted'))
      return const Color(0xFFFF9800);
    if (trustTags.contains('system_trust_known'))
      return const Color(0xFF4CAF50);
    if (trustTags.contains('system_trust_basic'))
      return const Color(0xFF64B5F6);
    return Colors.grey;
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.dio,
    required this.locationText,
    required this.onTap,
  });

  final _FriendEntry friend;
  final Dio dio;
  final String locationText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusMeta = _statusMeta(friend.status);

    return ListTile(
      onTap: onTap,
      leading: _AvatarWithStatusDot(
        dio: dio,
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
        child: Text(locationText),
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

class _AvatarWithStatusDot extends StatelessWidget {
  const _AvatarWithStatusDot({
    required this.dio,
    required this.imageUrl,
    required this.statusColor,
  });

  final Dio dio;
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

class _FriendGroups {
  const _FriendGroups({
    required this.online,
    required this.webOrOtherClient,
    required this.offline,
  });

  final List<_FriendEntry> online;
  final List<_FriendEntry> webOrOtherClient;
  final List<_FriendEntry> offline;
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

class _StatusMeta {
  const _StatusMeta({required this.color});
  final Color color;
}

