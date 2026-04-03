import 'package:flutter_test/flutter_test.dart';
import 'package:vrc_monitor/services/token_pool.dart';

void main() {
  group('TokenPool', () {
    test('promote inserts newest token at the front and deduplicates', () {
      final pool = TokenPool.promote(const ['b', 'a'], 'a');

      expect(pool, equals(const ['a', 'b']));
    });

    test('promote enforces LRU capacity', () {
      var pool = const <String>[];
      for (final token in const ['a', 'b', 'c', 'd', 'e', 'f']) {
        pool = TokenPool.promote(pool, token);
      }

      expect(pool, equals(const ['f', 'e', 'd', 'c', 'b']));
    });

    test('remove drops only the specified token', () {
      final pool = TokenPool.remove(const ['c', 'b', 'a'], 'b');

      expect(pool, equals(const ['c', 'a']));
    });
  });
}
