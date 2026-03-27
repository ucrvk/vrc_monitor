class RegionInfo {
  const RegionInfo({required this.emoji, required this.text});

  final String emoji;
  final String text;
}

class LocationUtils {
  const LocationUtils._();

  static const _regionMap = <String, RegionInfo>{
    'us': RegionInfo(emoji: '🇺🇸', text: '美国'),
    'usw': RegionInfo(emoji: '🇺🇸', text: '美国'),
    'jp': RegionInfo(emoji: '🇯🇵', text: '日本'),
    'eu': RegionInfo(emoji: '🇪🇺', text: '欧盟'),
  };

  static bool isTraveling(String? location) {
    final trimmed = location?.trim().toLowerCase();
    return trimmed == 'traveling';
  }

  static String? extractRegion(String? location) {
    if (location == null || location.isEmpty) return null;
    final value = location.trim();
    if (!value.contains(':')) return null;

    final regionMatch = RegExp(r'~region\(([^)]+)\)').firstMatch(value);
    if (regionMatch == null) return null;

    final region = regionMatch.group(1)?.toLowerCase();
    if (region == null || region.isEmpty) return null;

    return region;
  }

  static RegionInfo? getRegionInfo(String? region) {
    if (region == null || region.isEmpty) return null;
    return _regionMap[region.toLowerCase()];
  }

  static String? getRegionEmoji(String? location) {
    final region = extractRegion(location);
    return getRegionInfo(region)?.emoji;
  }
}
