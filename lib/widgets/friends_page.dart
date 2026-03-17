import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/me_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
    required this.api,
    required this.currentUser,
  });

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

  @override
  void initState() {
    super.initState();
    _startStreamingSync();
    _loadFriends();
  }

  @override
  void dispose() {
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

    final (onlineFriends, onlineFailure) = await _fetchAllFriends(offline: false);
    final (offlineFriends, offlineFailure) = await _fetchAllFriends(offline: true);

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

    final friends = merged.values.map(_FriendEntry.fromLimitedUserFriend).toList()
      ..sort((a, b) {
        final aOnline = a.status != UserStatus.offline;
        final bOnline = b.status != UserStatus.offline;
        if (aOnline != bOnline) return aOnline ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

    setState(() {
      _loading = false;
      _friends = friends;
      _error = null;
    });

    _resolveLocationDetails(friends);
  }

  Future<(List<LimitedUserFriend>, InvalidResponse?)> _fetchAllFriends({
    required bool offline,
  }) async {
    final List<LimitedUserFriend> result = [];
    InvalidResponse? lastFailure;
    var offset = 0;

    while (true) {
      final (success, failure) = await widget.api.rawApi
          .getFriendsApi()
          .getFriends(offline: offline, n: _pageSize, offset: offset)
          .validateVrc();

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

  Future<void> _logout() async {
    _wsSubscription?.cancel();
    widget.api.streaming.stop();
    await widget.api.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pop();
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
  }) {
    final index = _friends.indexWhere((f) => f.id == user.id);
    final location = (locationOverride ?? user.location ?? 'offline').trim();
    final updated = _FriendEntry.fromWsUser(
      user,
      status: statusOverride,
      location: location.isEmpty ? 'offline' : location,
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
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTabIndex == 0 ? '好友位置 (${_friends.length})' : '我',
        ),
        actions: [
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
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildFriendsBody(),
          MePage(currentUser: widget.currentUser),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
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
        _buildGroupSection(
          title: '在线',
          friends: grouped.online,
          expanded: _onlineExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _onlineExpanded = value;
            });
          },
        ),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        title: Text('$title (${friends.length})'),
        children: friends.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('暂无数据'),
                  ),
                ),
              ]
            : [
                for (var i = 0; i < friends.length; i++) ...[
                  _FriendRow(
                    friend: friends[i],
                    dio: widget.api.rawApi.dio,
                    locationText: _locationTextFor(friends[i]),
                  ),
                  if (i != friends.length - 1) const Divider(height: 1),
                ],
              ],
      ),
    );
  }

  Future<void> _onRefreshPressed() async {
    _startRefreshCooldown();
    await _loadFriends();
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
      final isLocationOffline = friend.location.trim().toLowerCase() == 'offline';
      if (friend.status == UserStatus.offline) {
        offline.add(friend);
      } else if (isLocationOffline) {
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
    for (final worldId in worldIds) {
      final (success, _) = await widget.api.rawApi
          .getWorldsApi()
          .getWorld(worldId: worldId)
          .validateVrc();

      if (!mounted) return;
      if (success != null) {
        _worldNameById[worldId] = success.data.name;
      } else {
        _worldNameById[worldId] = worldId;
      }
      changed = true;
    }

    for (final (raw, worldId, instanceId) in worldInstances) {
      final (success, _) = await widget.api.rawApi
          .getWorldsApi()
          .getWorldInstance(worldId: worldId, instanceId: instanceId)
          .validateVrc();
      if (!mounted) return;
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
    if (friend.status != UserStatus.offline && lower == 'offline') {
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
    return _ParsedLocation(raw: value, worldId: worldId, instanceId: instanceId);
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
    this.profilePicOverrideThumbnail,
    this.profilePicOverride,
    this.currentAvatarThumbnailImageUrl,
    this.userIcon,
    this.imageUrl,
  });

  factory _FriendEntry.fromLimitedUserFriend(LimitedUserFriend friend) {
    return _FriendEntry(
      id: friend.id,
      displayName: friend.displayName,
      status: friend.status,
      location: friend.location,
      profilePicOverrideThumbnail: friend.profilePicOverrideThumbnail,
      profilePicOverride: friend.profilePicOverride,
      currentAvatarThumbnailImageUrl: friend.currentAvatarThumbnailImageUrl,
      userIcon: friend.userIcon,
      imageUrl: friend.imageUrl,
    );
  }

  factory _FriendEntry.fromWsUser(
    User user, {
    required UserStatus status,
    required String location,
  }) {
    return _FriendEntry(
      id: user.id,
      displayName: user.displayName,
      status: status,
      location: location,
      profilePicOverrideThumbnail: user.profilePicOverrideThumbnail,
      profilePicOverride: user.profilePicOverride,
      currentAvatarThumbnailImageUrl: user.currentAvatarThumbnailImageUrl,
      userIcon: user.userIcon,
      imageUrl: user.currentAvatarImageUrl,
    );
  }

  final String id;
  final String displayName;
  final UserStatus status;
  final String location;
  final String? profilePicOverrideThumbnail;
  final String? profilePicOverride;
  final String? currentAvatarThumbnailImageUrl;
  final String? userIcon;
  final String? imageUrl;

  _FriendEntry copyWith({
    UserStatus? status,
    String? location,
  }) {
    return _FriendEntry(
      id: id,
      displayName: displayName,
      status: status ?? this.status,
      location: location ?? this.location,
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
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.dio,
    required this.locationText,
  });

  final _FriendEntry friend;
  final Dio dio;
  final String locationText;

  @override
  Widget build(BuildContext context) {
    final statusMeta = _statusMeta(friend.status);

    return ListTile(
      leading: _Avatar(imageUrl: friend.avatarUrl, dio: dio),
      title: Row(
        children: [
          Expanded(
            child: Text(
              friend.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusMeta.label,
            style: TextStyle(
              color: statusMeta.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
        return const _StatusMeta(label: 'joinMe', color: Colors.blue);
      case UserStatus.active:
        return const _StatusMeta(label: 'online', color: Colors.green);
      case UserStatus.askMe:
        return const _StatusMeta(label: 'askMe', color: Colors.orange);
      case UserStatus.busy:
        return const _StatusMeta(label: 'noDisturb', color: Colors.red);
      case UserStatus.offline:
        return const _StatusMeta(label: 'offline', color: Colors.grey);
    }
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

class _Avatar extends StatefulWidget {
  const _Avatar({required this.dio, this.imageUrl});

  final Dio dio;
  final String? imageUrl;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  static final Set<String> _logged403Urls = <String>{};
  static final Map<String, Uint8List> _memoryAvatarCache = {};
  static Future<io.Directory>? _cacheDirFuture;

  late Future<Uint8List?> _avatarFuture;

  @override
  void initState() {
    super.initState();
    _avatarFuture = _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _avatarFuture = _loadAvatar();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null) {
      return const CircleAvatar(child: Icon(Icons.person));
    }

    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: FutureBuilder<Uint8List?>(
        future: _avatarFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Icon(Icons.person);
          }

          return ClipOval(
            child: Image.memory(
              bytes,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }

  Future<Uint8List?> _loadAvatar() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return null;

    final cachedInMemory = _memoryAvatarCache[url];
    if (cachedInMemory != null && cachedInMemory.isNotEmpty) {
      return cachedInMemory;
    }

    final cacheFile = await _cacheFileForUrl(url);
    if (await cacheFile.exists()) {
      final bytes = await cacheFile.readAsBytes();
      if (bytes.isNotEmpty) {
        _memoryAvatarCache[url] = bytes;
        return bytes;
      }
    }

    try {
      final response = await widget.dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 200 && response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        _memoryAvatarCache[url] = bytes;
        await cacheFile.writeAsBytes(bytes, flush: true);
        return bytes;
      }

      if (statusCode == 403 && !_logged403Urls.contains(url)) {
        _logged403Urls.add(url);
        final body = _decodeBody(response.data);
        debugPrint('Avatar 403 URL: $url');
        debugPrint('Avatar 403 BODY: $body');
      }
    } catch (e) {
      debugPrint('Avatar request failed: $e');
    }

    return null;
  }

  Future<io.File> _cacheFileForUrl(String url) async {
    _cacheDirFuture ??= _initCacheDir();
    final dir = await _cacheDirFuture!;
    final key = sha1.convert(utf8.encode(url)).toString();
    return io.File('${dir.path}/$key.img');
  }

  Future<io.Directory> _initCacheDir() async {
    final tempDir = await getTemporaryDirectory();
    final dir = io.Directory('${tempDir.path}/avatar_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _decodeBody(List<int>? data) {
    if (data == null || data.isEmpty) return '<empty>';
    final body = utf8.decode(data, allowMalformed: true).trim();
    if (body.isEmpty) return '<empty>';
    return body.length > 1200 ? '${body.substring(0, 1200)}...(truncated)' : body;
  }
}

class _StatusMeta {
  const _StatusMeta({required this.label, required this.color});

  final String label;
  final Color color;
}
