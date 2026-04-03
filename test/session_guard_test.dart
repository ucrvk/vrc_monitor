import 'package:flutter_test/flutter_test.dart';
import 'package:vrc_monitor/services/session_guard.dart';

void main() {
  test('requireLogin is coalesced until reset', () async {
    final guard = SessionGuard.instance;
    guard.resetLoginRequired();

    final events = <SessionEvent>[];
    final subscription = guard.events.listen(events.add);

    guard.requireLogin(skipTokenAutoLogin: true);
    guard.requireLogin(skipTokenAutoLogin: true);
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 1);
    expect(events.single.type, SessionEventType.requireLogin);
    expect(events.single.skipTokenAutoLogin, true);

    guard.resetLoginRequired();
    guard.requireLogin(skipTokenAutoLogin: true);
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 2);

    await subscription.cancel();
    guard.resetLoginRequired();
  });
}
