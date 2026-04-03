import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeSettings {
  static const String _themeModeKey = 'app_theme_mode';
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeModeKey);
    themeModeNotifier.value = _themeModeFromRaw(raw);
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _themeModeToRaw(mode));
  }

  static ThemeMode _themeModeFromRaw(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _themeModeToRaw(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

enum MapRoomSortMode { starFirst, countFirst }

class AppMapSettings {
  static const String _mapRoomSortModeKey = 'map_room_sort_mode';
  static final ValueNotifier<MapRoomSortMode> roomSortModeNotifier =
      ValueNotifier<MapRoomSortMode>(MapRoomSortMode.starFirst);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mapRoomSortModeKey);
    roomSortModeNotifier.value = _modeFromRaw(raw);
  }

  static Future<void> setRoomSortMode(MapRoomSortMode mode) async {
    roomSortModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapRoomSortModeKey, _modeToRaw(mode));
  }

  static MapRoomSortMode _modeFromRaw(String? raw) {
    return switch (raw) {
      'count_first' => MapRoomSortMode.countFirst,
      _ => MapRoomSortMode.starFirst,
    };
  }

  static String _modeToRaw(MapRoomSortMode mode) {
    return switch (mode) {
      MapRoomSortMode.starFirst => 'star_first',
      MapRoomSortMode.countFirst => 'count_first',
    };
  }
}
