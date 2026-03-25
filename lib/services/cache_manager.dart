import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/network/web_client.dart';

class CachedFavoriteGroup {
  const CachedFavoriteGroup({
    required this.name,
    required this.displayName,
  });

  final String name;
  final String displayName;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'displayName': displayName,
    };
  }

  factory CachedFavoriteGroup.fromJson(Map<String, dynamic> json) {
    return CachedFavoriteGroup(
      name: json['name']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
    );
  }
}

class DataCache {
  static const String _keyFavoriteGroups = 'cache.favorite_groups';
  static const String _keyUserFavoriteGroups = 'cache.user_favorite_groups';
  static const String _keyWorldNameById = 'cache.world_name_by_id';
  static const String _keyInstanceTypeByLocation = 'cache.instance_type_by_location';
  static const String _keyUserDisplayNameById = 'cache.user_display_name_by_id';

  SharedPreferences? _prefs;
  List<CachedFavoriteGroup> _favoriteGroups = const [];
  Map<String, Set<String>> _userFavoriteGroups = const {};
  Map<String, String> _worldNameById = const {};
  Map<String, String> _instanceTypeByLocation = const {};
  Map<String, String> _userDisplayNameById = const {};

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _favoriteGroups = _readFavoriteGroups();
    _userFavoriteGroups = _readSetMap(_keyUserFavoriteGroups);
    _worldNameById = _readStringMap(_keyWorldNameById);
    _instanceTypeByLocation = _readStringMap(_keyInstanceTypeByLocation);
    _userDisplayNameById = _readStringMap(_keyUserDisplayNameById);
  }

  List<CachedFavoriteGroup> get favoriteGroups => List.unmodifiable(_favoriteGroups);

  Map<String, Set<String>> get userFavoriteGroups {
    return Map.unmodifiable(
      _userFavoriteGroups.map((k, v) => MapEntry(k, Set<String>.from(v))),
    );
  }

  Map<String, String> get worldNameById => Map.unmodifiable(_worldNameById);

  Map<String, String> get instanceTypeByLocation {
    return Map.unmodifiable(_instanceTypeByLocation);
  }

  Map<String, String> get userDisplayNameById {
    return Map.unmodifiable(_userDisplayNameById);
  }

  Set<String> favoriteGroupsForUser(String userId) {
    return Set<String>.from(_userFavoriteGroups[userId] ?? const <String>{});
  }

  String? worldName(String worldId) => _worldNameById[worldId];

  String? instanceType(String location) => _instanceTypeByLocation[location];

  String? displayName(String userId) => _userDisplayNameById[userId];

  Future<void> setFavoriteGroups(List<CachedFavoriteGroup> groups) async {
    _favoriteGroups = List.unmodifiable(groups);
    final prefs = await _ensurePrefs();
    final jsonString = jsonEncode(groups.map((e) => e.toJson()).toList());
    await prefs.setString(_keyFavoriteGroups, jsonString);
  }

  Future<void> setUserFavoriteGroups(Map<String, Set<String>> map) async {
    _userFavoriteGroups = map.map((k, v) => MapEntry(k, Set<String>.from(v)));
    final prefs = await _ensurePrefs();
    await prefs.setString(
      _keyUserFavoriteGroups,
      jsonEncode(_userFavoriteGroups.map((k, v) => MapEntry(k, v.toList()))),
    );
  }

  Future<void> setWorldNameById(Map<String, String> map) async {
    _worldNameById = Map<String, String>.from(map);
    final prefs = await _ensurePrefs();
    await prefs.setString(_keyWorldNameById, jsonEncode(_worldNameById));
  }

  Future<void> setInstanceTypeByLocation(Map<String, String> map) async {
    _instanceTypeByLocation = Map<String, String>.from(map);
    final prefs = await _ensurePrefs();
    await prefs.setString(
      _keyInstanceTypeByLocation,
      jsonEncode(_instanceTypeByLocation),
    );
  }

  Future<void> setUserDisplayNameById(Map<String, String> map) async {
    _userDisplayNameById = Map<String, String>.from(map);
    final prefs = await _ensurePrefs();
    await prefs.setString(
      _keyUserDisplayNameById,
      jsonEncode(_userDisplayNameById),
    );
  }

  Future<void> putWorldName(String worldId, String worldName) async {
    if (worldId.isEmpty || worldName.isEmpty) return;
    _worldNameById = {..._worldNameById, worldId: worldName};
    await _writeStringMap(_keyWorldNameById, _worldNameById);
  }

  Future<void> putInstanceType(String location, String typeLabel) async {
    if (location.isEmpty || typeLabel.isEmpty) return;
    _instanceTypeByLocation = {
      ..._instanceTypeByLocation,
      location: typeLabel,
    };
    await _writeStringMap(_keyInstanceTypeByLocation, _instanceTypeByLocation);
  }

  Future<void> putUserDisplayName(String userId, String displayName) async {
    if (userId.isEmpty || displayName.isEmpty) return;
    _userDisplayNameById = {..._userDisplayNameById, userId: displayName};
    await _writeStringMap(_keyUserDisplayNameById, _userDisplayNameById);
  }

  Future<SharedPreferences> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  List<CachedFavoriteGroup> _readFavoriteGroups() {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final raw = prefs.getString(_keyFavoriteGroups);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return parsed
          .whereType<Map>()
          .map((e) => CachedFavoriteGroup.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, String> _readStringMap(String key) {
    final prefs = _prefs;
    if (prefs == null) return const {};
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return const {};
      return parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return const {};
    }
  }

  Map<String, Set<String>> _readSetMap(String key) {
    final prefs = _prefs;
    if (prefs == null) return const {};
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return const {};
      final map = <String, Set<String>>{};
      for (final entry in parsed.entries) {
        final value = entry.value;
        if (value is List) {
          map[entry.key.toString()] = value
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toSet();
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeStringMap(String key, Map<String, String> map) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(key, jsonEncode(map));
  }
}

class ImageCache {
  static const String _avatarPrefix = 'avatar';
  static const String _profilePrefix = 'profile';
  static const String _worldPrefix = 'world';

  io.Directory? _cacheDir;
  final Map<String, Uint8List> _memoryByUrl = {};

  Future<void> initialize() async {
    if (_cacheDir != null) return;
    final support = await getApplicationSupportDirectory();
    final dir = io.Directory('${support.path}/vrc_monitor_image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
  }

  Future<Uint8List?> getAvatar(String userId) async {
    return _readBytes(_avatarPrefix, userId);
  }

  Future<Uint8List?> getProfile(String userId) async {
    return _readBytes(_profilePrefix, userId);
  }

  Future<Uint8List?> getWorld(String worldId) async {
    return _readBytes(_worldPrefix, worldId);
  }

  Future<Uint8List?> getByUrl(String? imageUrl) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return null;

    final mem = _memoryByUrl[url];
    if (mem != null && mem.isNotEmpty) return mem;

    final file = await _fileForUrl(url);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    _memoryByUrl[url] = bytes;
    return bytes;
  }

  Future<void> cacheByUrl({
    required Dio dio,
    required String? imageUrl,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return;

    if (_memoryByUrl[url]?.isNotEmpty == true) return;

    final file = await _fileForUrl(url);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _memoryByUrl[url] = bytes;
      }
      return;
    }

    try {
      final response = await WebClient.getWithUserAgent<List<int>>(
        dio: dio,
        url: url,
        options: WebClient.withUserAgent(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200 || response.data == null) return;
      final bytes = Uint8List.fromList(response.data!);
      _memoryByUrl[url] = bytes;
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      return;
    }
  }

  Future<void> cacheAvatar({
    required Dio dio,
    required String userId,
    required String? imageUrl,
  }) async {
    await _cacheByKey(
      dio: dio,
      keyType: _avatarPrefix,
      keyId: userId,
      imageUrl: imageUrl,
    );
  }

  Future<void> cacheProfile({
    required Dio dio,
    required String userId,
    required String? imageUrl,
  }) async {
    await _cacheByKey(
      dio: dio,
      keyType: _profilePrefix,
      keyId: userId,
      imageUrl: imageUrl,
    );
  }

  Future<void> cacheWorldImage({
    required Dio dio,
    required String worldId,
    required String? imageUrl,
  }) async {
    await _cacheByKey(
      dio: dio,
      keyType: _worldPrefix,
      keyId: worldId,
      imageUrl: imageUrl,
    );
  }

  Future<void> _cacheByKey({
    required Dio dio,
    required String keyType,
    required String keyId,
    required String? imageUrl,
  }) async {
    final url = imageUrl?.trim() ?? '';
    final id = keyId.trim();
    if (url.isEmpty || id.isEmpty) return;

    final keyFile = await _fileForKey(keyType, id);
    if (await keyFile.exists()) return;

    await cacheByUrl(dio: dio, imageUrl: url);
    final bytes = await getByUrl(url);
    if (bytes == null || bytes.isEmpty) return;
    await keyFile.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> _readBytes(String keyType, String keyId) async {
    final id = keyId.trim();
    if (id.isEmpty) return null;
    final file = await _fileForKey(keyType, id);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return bytes;
  }

  Future<io.File> _fileForKey(String keyType, String keyId) async {
    await initialize();
    return io.File('${_cacheDir!.path}/$keyType-$keyId.img');
  }

  Future<io.File> _fileForUrl(String url) async {
    await initialize();
    final key = sha1.convert(utf8.encode(url)).toString();
    return io.File('${_cacheDir!.path}/url-$key.img');
  }
}

class CacheManager {
  CacheManager._();

  static final CacheManager instance = CacheManager._();

  final DataCache dataCache = DataCache();
  final ImageCache imageCache = ImageCache();

  Future<void>? _initializingFuture;

  Future<void> initialize({
    required VrchatDart api,
    required CurrentUser currentUser,
    bool preload = true,
  }) {
    final running = _initializingFuture;
    if (running != null) return running;

    final future = _doInitialize(api: api, currentUser: currentUser, preload: preload);
    _initializingFuture = future.whenComplete(() {
      _initializingFuture = null;
    });
    return _initializingFuture!;
  }

  Future<void> _doInitialize({
    required VrchatDart api,
    required CurrentUser currentUser,
    required bool preload,
  }) async {
    await dataCache.initialize();
    await imageCache.initialize();
    if (preload) {
      await preloadAll(api: api, currentUser: currentUser);
    }
  }

  Future<void> preloadAll({
    required VrchatDart api,
    required CurrentUser currentUser,
  }) async {
    await Future.wait([
      _preloadFavoriteData(api),
      _preloadFriendData(api),
    ]);

    await dataCache.putUserDisplayName(currentUser.id, currentUser.displayName);
  }

  Future<void> refresh({
    required VrchatDart api,
    required CurrentUser currentUser,
  }) async {
    await preloadAll(api: api, currentUser: currentUser);
  }

  Future<void> _preloadFavoriteData(VrchatDart api) async {
    final (groupsSuccess, _) = await _runVrcRequest(
      () => api.rawApi.getFavoritesApi().getFavoriteGroups(n: 100).validateVrc(),
    );

    final groups = (groupsSuccess?.data ?? const <FavoriteGroup>[])
        .where((g) => g.type == FavoriteType.friend)
        .map(
          (g) => CachedFavoriteGroup(name: g.name, displayName: g.displayName),
        )
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    await dataCache.setFavoriteGroups(groups);

    final userFavoriteGroups = <String, Set<String>>{};
    const pageSize = 100;
    var offset = 0;

    while (true) {
      final (favoritesSuccess, _) = await _runVrcRequest(
        () => api.rawApi
            .getFavoritesApi()
            .getFavorites(type: 'friend', n: pageSize, offset: offset)
            .validateVrc(),
      );

      final page = favoritesSuccess?.data ?? const <Favorite>[];
      for (final item in page) {
        if (item.favoriteId.isEmpty) continue;
        final tags = item.tags.where((e) => e.trim().isNotEmpty).toSet();
        if (tags.isEmpty) continue;
        userFavoriteGroups.putIfAbsent(item.favoriteId, () => <String>{}).addAll(tags);
      }

      if (page.length < pageSize) break;
      offset += page.length;
    }

    await dataCache.setUserFavoriteGroups(userFavoriteGroups);
  }

  Future<void> _preloadFriendData(VrchatDart api) async {
    final onlineFuture = _fetchAllFriends(api: api, offline: false);
    final offlineFuture = _fetchAllFriends(api: api, offline: true);
    final online = await onlineFuture;
    final offline = await offlineFuture;

    final merged = <String, LimitedUserFriend>{
      for (final f in online) f.id: f,
      for (final f in offline) f.id: f,
    };

    final displayNames = <String, String>{};
    final worldNames = <String, String>{...dataCache.worldNameById};
    final unresolvedWorldIds = <String>{};

    for (final friend in merged.values) {
      if (friend.displayName.trim().isNotEmpty) {
        displayNames[friend.id] = friend.displayName.trim();
      }

      final parsed = parseLocation(friend.location);
      if (parsed == null) continue;

      if (!worldNames.containsKey(parsed.worldId)) {
        unresolvedWorldIds.add(parsed.worldId);
      }
    }

    for (final worldId in unresolvedWorldIds) {
      final (success, _) = await _runVrcRequest(
        () => api.rawApi.getWorldsApi().getWorld(worldId: worldId).validateVrc(),
      );
      final world = success?.data;
      if (world == null) {
        worldNames[worldId] = worldId;
        continue;
      }
      worldNames[worldId] = world.name;
    }

    await dataCache.setUserDisplayNameById({
      ...dataCache.userDisplayNameById,
      ...displayNames,
    });
    await dataCache.setWorldNameById(worldNames);
  }

  Future<List<LimitedUserFriend>> _fetchAllFriends({
    required VrchatDart api,
    required bool offline,
  }) async {
    const pageSize = 100;
    final result = <LimitedUserFriend>[];
    var offset = 0;

    while (true) {
      final (success, _) = await _runVrcRequest(
        () => api.rawApi
            .getFriendsApi()
            .getFriends(offline: offline, n: pageSize, offset: offset)
            .validateVrc(),
      );
      final page = success?.data ?? const <LimitedUserFriend>[];
      result.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }

    return result;
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

  static ParsedLocation? parseLocation(String? location) {
    final value = location?.trim() ?? '';
    if (value.isEmpty || !value.contains(':')) return null;

    final firstColon = value.indexOf(':');
    final worldId = value.substring(0, firstColon);
    if (!worldId.startsWith('wrld_')) return null;

    final instanceId = value.substring(firstColon + 1);
    if (instanceId.isEmpty) return null;
    return ParsedLocation(
      rawLocation: value,
      worldId: worldId,
      instanceId: instanceId,
    );
  }

  static String instanceTypeLabel(
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

class ParsedLocation {
  const ParsedLocation({
    required this.rawLocation,
    required this.worldId,
    required this.instanceId,
  });

  final String rawLocation;
  final String worldId;
  final String instanceId;
}
