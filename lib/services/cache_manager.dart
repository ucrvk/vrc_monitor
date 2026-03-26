import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/network/web_client.dart';

class MemoryDataCache {
  Map<String, String> _instanceTypeByLocation = const {};

  Map<String, String> get instanceTypeByLocation {
    return Map.unmodifiable(_instanceTypeByLocation);
  }

  String? instanceType(String location) => _instanceTypeByLocation[location];

  void setInstanceTypeByLocation(Map<String, String> map) {
    _instanceTypeByLocation = Map<String, String>.from(map);
  }

  void putInstanceType(String location, String typeLabel) {
    if (location.isEmpty || typeLabel.isEmpty) return;
    _instanceTypeByLocation = {..._instanceTypeByLocation, location: typeLabel};
  }
}

class WorldNameCache {
  io.File? _cacheFile;
  Map<String, String> _worldNameById = const {};

  Map<String, String> get worldNameById => Map.unmodifiable(_worldNameById);

  String? worldName(String worldId) => _worldNameById[worldId];

  Future<void> initialize() async {
    if (_cacheFile != null) return;
    final tempDir = await getTemporaryDirectory();
    _cacheFile = io.File('${tempDir.path}/vrc_world_names.json');
    await load();
  }

  Future<void> load() async {
    final file = _cacheFile;
    if (file == null) return;

    if (!await file.exists()) {
      _worldNameById = const {};
      return;
    }

    try {
      final content = await file.readAsString();
      if (content.isEmpty) {
        _worldNameById = const {};
        return;
      }
      final parsed = jsonDecode(content);
      if (parsed is! Map) {
        _worldNameById = const {};
        return;
      }
      _worldNameById = parsed.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      _worldNameById = const {};
    }
  }

  Future<void> save() async {
    final file = _cacheFile;
    if (file == null) return;
    await file.writeAsString(jsonEncode(_worldNameById));
  }

  Future<void> putWorldName(String worldId, String name) async {
    if (worldId.isEmpty || name.isEmpty) return;
    _worldNameById = {..._worldNameById, worldId: name};
    await save();
  }

  Future<void> setWorldNameById(Map<String, String> map) async {
    _worldNameById = Map<String, String>.from(map);
    await save();
  }
}

class ImageCache {
  static final RegExp _fileIdPattern = RegExp(
    r'file_[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}',
    caseSensitive: false,
  );

  io.Directory? _cacheDir;
  final Map<String, Uint8List> _memoryCache = {};

  static String? extractFileIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = _fileIdPattern.firstMatch(url);
    return match?.group(0);
  }

  Future<void> initialize() async {
    if (_cacheDir != null) return;
    final tempDir = await getTemporaryDirectory();
    final dir = io.Directory('${tempDir.path}/vrc_monitor_image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
  }

  Future<Uint8List?> getByFileId(String? fileId) async {
    final id = fileId?.trim() ?? '';
    if (id.isEmpty) return null;

    final mem = _memoryCache[id];
    if (mem != null && mem.isNotEmpty) return mem;

    final file = await _fileForFileId(id);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    _memoryCache[id] = bytes;
    return bytes;
  }

  Future<void> cacheByFileId({
    required Dio dio,
    required String? fileId,
    required String? imageUrl,
  }) async {
    final id = fileId?.trim() ?? '';
    final url = imageUrl?.trim() ?? '';
    if (id.isEmpty || url.isEmpty) return;

    if (_memoryCache[id]?.isNotEmpty == true) return;

    final file = await _fileForFileId(id);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        _memoryCache[id] = bytes;
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
      _memoryCache[id] = bytes;
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      return;
    }
  }

  Future<Uint8List?> getWorldImage(String? imageUrl) async {
    final fileId = extractFileIdFromUrl(imageUrl);
    if (fileId == null || fileId.isEmpty) return null;
    return getByFileId(fileId);
  }

  Future<void> cacheWorldImage({
    required Dio dio,
    required String? imageUrl,
  }) async {
    final fileId = extractFileIdFromUrl(imageUrl);
    if (fileId == null || fileId.isEmpty) return;
    await cacheByFileId(dio: dio, fileId: fileId, imageUrl: imageUrl);
  }

  Future<io.File> _fileForFileId(String fileId) async {
    await initialize();
    return io.File('${_cacheDir!.path}/$fileId.img');
  }
}

class CacheManager {
  CacheManager._();

  static final CacheManager instance = CacheManager._();

  final MemoryDataCache memoryCache = MemoryDataCache();
  final WorldNameCache worldNameCache = WorldNameCache();
  final ImageCache imageCache = ImageCache();

  Future<void>? _initializingFuture;

  Future<void> initialize({
    required VrchatDart api,
    required CurrentUser currentUser,
    bool preload = true,
  }) {
    final running = _initializingFuture;
    if (running != null) return running;

    final future = _doInitialize(
      api: api,
      currentUser: currentUser,
      preload: preload,
    );
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
    await worldNameCache.initialize();
    await imageCache.initialize();
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
