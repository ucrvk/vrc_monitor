import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

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
  List<LimitedUserFriend> _friends = const [];
  final Map<String, String> _worldNameById = {};
  final Map<String, String> _instanceTypeByLocation = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
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

    final friends = merged.values.toList()
      ..sort((a, b) {
        final aOnline = a.status != UserStatus.offline;
        final bOnline = b.status != UserStatus.offline;
        if (aOnline != bOnline) return aOnline ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

    setState(() {
      _loading = false;
      _friends = friends;
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
    await widget.api.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('好友列表 (${_friends.length})'),
        actions: [
          IconButton(
            onPressed: _loadFriends,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _logout,
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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

    return ListView.separated(
      itemCount: _friends.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _FriendRow(
        friend: _friends[index],
        dio: widget.api.rawApi.dio,
        locationText: _locationText(_friends[index].location),
      ),
    );
  }

  Future<void> _resolveLocationDetails(List<LimitedUserFriend> friends) async {
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

  String _locationText(String rawLocation) {
    final location = rawLocation.trim();
    final lower = location.toLowerCase();
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

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.dio,
    required this.locationText,
  });

  final LimitedUserFriend friend;
  final Dio dio;
  final String locationText;

  @override
  Widget build(BuildContext context) {
    final statusMeta = _statusMeta(friend.status);

    return ListTile(
      leading: _Avatar(imageUrl: _avatarUrl(friend), dio: dio),
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

  String? _avatarUrl(LimitedUserFriend friend) {
    final candidates = [
      friend.profilePicOverrideThumbnail,
      friend.profilePicOverride,
      friend.currentAvatarThumbnailImageUrl,
      friend.userIcon,
      friend.imageUrl,
    ];

    for (final url in candidates) {
      if (url != null && url.isNotEmpty) return url;
    }

    return null;
  }

  _StatusMeta _statusMeta(UserStatus status) {
    switch (status) {
      case UserStatus.joinMe:
        return const _StatusMeta(label: 'join', color: Colors.blue);
      case UserStatus.active:
        return const _StatusMeta(label: 'online', color: Colors.green);
      case UserStatus.askMe:
        return const _StatusMeta(label: 'askme', color: Colors.orange);
      case UserStatus.busy:
        return const _StatusMeta(label: 'nodisturb', color: Colors.red);
      case UserStatus.offline:
        return const _StatusMeta(label: 'offline', color: Colors.grey);
    }
  }
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
