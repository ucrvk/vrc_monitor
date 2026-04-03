import 'package:flutter_test/flutter_test.dart';
import 'package:vrc_monitor/services/auth_manager.dart';

void main() {
  group('Auth cookie tools', () {
    test('extracts auth and twoFactorAuth values from set-cookie lines', () {
      const line =
          'twoFactorAuth=two-factor-token; Path=/; HttpOnly; SameSite=Lax';
      const line2 = 'auth=auth-token; Path=/; HttpOnly';
      const line3 = '_ga=ignored; Path=/';

      expect(
        AuthManager.extractCookieValueForTest(line, 'twoFactorAuth'),
        equals('two-factor-token'),
      );
      expect(
        AuthManager.extractCookieValueForTest(line2, 'auth'),
        equals('auth-token'),
      );
      expect(
        AuthManager.extractCookieValueForTest(line3, 'twoFactorAuth'),
        isNull,
      );
    });

    test('builds cookie header with auth only', () {
      expect(
        AuthManager.buildCookieHeaderForTest(authToken: 'auth-token'),
        equals('auth=auth-token'),
      );
    });

    test('builds cookie header with auth and twoFactorAuth', () {
      expect(
        AuthManager.buildCookieHeaderForTest(
          authToken: 'auth-token',
          twoFactorAuthToken: 'two-factor-token',
        ),
        equals('auth=auth-token; twoFactorAuth=two-factor-token'),
      );
    });

    test('omits empty cookie values', () {
      expect(
        AuthManager.buildCookieHeaderForTest(
          authToken: '  ',
          twoFactorAuthToken: 'two-factor-token',
        ),
        equals('twoFactorAuth=two-factor-token'),
      );
      expect(AuthManager.buildCookieHeaderForTest(), isNull);
    });

    test(
      'invalidates stored twoFactorAuth only when response still requires 2FA',
      () {
        const requiresTwoFactor = {
          'requiresTwoFactorAuth': ['totp', 'otp'],
        };
        const normalData = {'ok': true};

        expect(
          AuthManager.shouldInvalidateStoredTwoFactorForTest(
            hadStoredTwoFactor: true,
            responseData: requiresTwoFactor,
          ),
          isTrue,
        );
        expect(
          AuthManager.shouldInvalidateStoredTwoFactorForTest(
            hadStoredTwoFactor: false,
            responseData: requiresTwoFactor,
          ),
          isFalse,
        );
        expect(
          AuthManager.shouldInvalidateStoredTwoFactorForTest(
            hadStoredTwoFactor: true,
            responseData: normalData,
          ),
          isFalse,
        );
      },
    );
  });
}
