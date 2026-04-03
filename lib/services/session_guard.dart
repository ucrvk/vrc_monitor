import 'dart:async';

class SessionEvent {
  const SessionEvent._({
    required this.type,
    this.message,
    this.skipTokenAutoLogin = false,
  });

  const SessionEvent.rotationNotice(String message)
    : this._(type: SessionEventType.rotationNotice, message: message);

  const SessionEvent.requireLogin({bool skipTokenAutoLogin = false})
    : this._(
        type: SessionEventType.requireLogin,
        skipTokenAutoLogin: skipTokenAutoLogin,
      );

  final SessionEventType type;
  final String? message;
  final bool skipTokenAutoLogin;
}

enum SessionEventType { rotationNotice, requireLogin }

class SessionGuard {
  SessionGuard._();

  static final SessionGuard instance = SessionGuard._();

  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();
  bool _loginRequiredPending = false;

  Stream<SessionEvent> get events => _events.stream;

  void showRotationNotice(String message) {
    if (message.trim().isEmpty) return;
    _events.add(SessionEvent.rotationNotice(message));
  }

  void requireLogin({bool skipTokenAutoLogin = false}) {
    if (_loginRequiredPending) return;
    _loginRequiredPending = true;
    _events.add(
      SessionEvent.requireLogin(skipTokenAutoLogin: skipTokenAutoLogin),
    );
  }

  void resetLoginRequired() {
    _loginRequiredPending = false;
  }
}
