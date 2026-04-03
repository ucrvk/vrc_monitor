import 'package:flutter_test/flutter_test.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/user_store.dart';

void main() {
  group('UserStore.refreshForForeground', () {
    late VrchatDart api;
    final store = UserStore.instance;

    setUp(() async {
      api = VrchatDart(
        userAgent: const VrchatUserAgent(
          applicationName: 'vrc-monitor-test',
          version: '1.0.0',
          contactInfo: 'test@vrc-monitor.app',
        ),
        // Use an unroutable local endpoint to avoid hitting real VRChat API.
        baseUrl: 'http://127.0.0.1:9',
        websocketUrl: 'ws://127.0.0.1:9',
      );
      api.rawApi.dio.options.connectTimeout = const Duration(milliseconds: 80);
      api.rawApi.dio.options.receiveTimeout = const Duration(milliseconds: 80);
      api.rawApi.dio.options.sendTimeout = const Duration(milliseconds: 80);
      store.clearAll(notify: false);
      await store.stopRealtimeSync();
    });

    tearDown(() async {
      await store.stopRealtimeSync();
      store.clearAll(notify: false);
    });

    test('clears existing favorite mapping when refresh init cannot reload data',
        () async {
      store.setUserFavoriteGroup('usr_test', 'group_test');
      expect(store.getFavoriteFriendIds(), contains('usr_test'));

      await store.refreshForForeground(api);

      expect(store.getFavoriteFriendIds(), isEmpty);
    });
  });
}
