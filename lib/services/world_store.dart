import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class WorldStore extends ChangeNotifier {
  WorldStore._();

  static final WorldStore instance = WorldStore._();
  static const String _boxName = 'world_store_box';
  static bool _hiveInitialized = false;

  Box<String>? _box;
  Map<String, World> _worldById = <String, World>{};
  final Map<String, Future<World?>> _loadingById = <String, Future<World?>>{};
  Future<void>? _initializingFuture;

  Map<String, World> get worldById => Map.unmodifiable(_worldById);
  int get storedWorldCount => _worldById.length;

  Map<String, String> get worldNameById => Map.unmodifiable(
    _worldById.map((id, world) => MapEntry(id, world.name.trim())),
  );

  Future<void> initialize() {
    final running = _initializingFuture;
    if (running != null) return running;

    final future = _doInitialize();
    _initializingFuture = future.whenComplete(() {
      _initializingFuture = null;
    });
    return _initializingFuture!;
  }

  Future<void> _doInitialize() async {
    if (!_hiveInitialized) {
      await Hive.initFlutter();
      _hiveInitialized = true;
    }
    _box = await Hive.openBox<String>(_boxName);
    _loadFromBox();
  }

  void _loadFromBox() {
    final box = _box;
    if (box == null) {
      _worldById = <String, World>{};
      return;
    }

    final next = <String, World>{};
    for (final key in box.keys) {
      final worldId = key.toString().trim();
      if (worldId.isEmpty) continue;

      final raw = box.get(worldId);
      if (raw == null || raw.isEmpty) continue;

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final world = World.fromJson(decoded.cast<String, dynamic>());
        final id = world.id.trim();
        if (id.isEmpty) continue;
        next[id] = world;
      } catch (_) {
        // ignore bad records and keep loading others
      }
    }
    _worldById = next;
  }

  String _encodeWorld(World world) => jsonEncode(world.toJson());

  World? getWorld(String worldId) {
    final id = worldId.trim();
    if (id.isEmpty) return null;
    return _worldById[id];
  }

  String? getWorldName(String worldId) {
    final world = getWorld(worldId);
    final name = world?.name.trim() ?? '';
    if (name.isEmpty) return null;
    return name;
  }

  Future<void> putWorld(World world) async {
    await initialize();
    final box = _box;
    if (box == null) return;

    final worldId = world.id.trim();
    if (worldId.isEmpty) return;

    final existing = _worldById[worldId];
    if (existing != null && _worldEquals(existing, world)) return;

    _worldById = <String, World>{..._worldById, worldId: world};
    await box.put(worldId, _encodeWorld(world));
    notifyListeners();
  }

  Future<void> putWorlds(Iterable<World> worlds) async {
    await initialize();
    final box = _box;
    if (box == null) return;

    var changed = false;
    final next = <String, World>{..._worldById};
    final updates = <String, String>{};

    for (final world in worlds) {
      final worldId = world.id.trim();
      if (worldId.isEmpty) continue;
      final existing = next[worldId];
      if (existing != null && _worldEquals(existing, world)) continue;
      next[worldId] = world;
      updates[worldId] = _encodeWorld(world);
      changed = true;
    }

    if (!changed) return;
    _worldById = next;
    await box.putAll(updates);
    notifyListeners();
  }

  Future<World?> getOrFetch(String worldId, VrchatDartGenerated api) async {
    await initialize();
    final id = worldId.trim();
    if (id.isEmpty) return null;

    final cached = _worldById[id];
    if (cached != null) return cached;

    final inflight = _loadingById[id];
    if (inflight != null) return inflight;

    final future = _fetchAndStore(id, api);
    _loadingById[id] = future;
    return future.whenComplete(() {
      _loadingById.remove(id);
    });
  }

  Future<World?> _fetchAndStore(String worldId, VrchatDartGenerated api) async {
    try {
      final (success, _) = await api
          .getWorldsApi()
          .getWorld(worldId: worldId)
          .validateVrc();
      final world = success?.data;
      if (world == null) return null;
      await putWorld(world);
      return world;
    } catch (_) {
      return null;
    }
  }

  bool _worldEquals(World left, World right) {
    return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
  }

  Future<int> clearStorage() async {
    await initialize();
    final box = _box;
    if (box == null) return 0;

    final removed = box.length;
    await box.clear();
    _worldById = <String, World>{};
    notifyListeners();
    return removed;
  }
}
