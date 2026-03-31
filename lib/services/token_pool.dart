class TokenPool {
  TokenPool._();

  static const int capacity = 5;

  static List<String> promote(
    List<String> pool,
    String token, {
    int maxSize = capacity,
  }) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return List<String>.from(pool);
    }

    final next = <String>[normalized];
    for (final item in pool) {
      final value = item.trim();
      if (value.isEmpty || value == normalized) continue;
      next.add(value);
      if (next.length >= maxSize) break;
    }
    return next;
  }

  static List<String> remove(List<String> pool, String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return List<String>.from(pool);
    }

    return pool
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != normalized)
        .toList(growable: false);
  }

  static List<String> normalize(List<String> pool, {int maxSize = capacity}) {
    var next = <String>[];
    for (final token in pool) {
      next = promote(next, token, maxSize: maxSize);
    }
    return next;
  }
}
