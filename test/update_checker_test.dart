import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrc_monitor/app_config.dart';
import 'package:vrc_monitor/update_checker.dart';

void main() {
  group('AppUpdateChecker', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('uses legacy version.json when updateManagerBaseUrl is empty', () async {
      final config = AppConfig(
        githubPage: 'https://github.com/ucrvk/vrc_monitor',
        branch: 'beta',
      );
      var requestedUrl = '';

      final checker = AppUpdateChecker(
        localVersionLoader: () async => '1.0.0',
        configLoader: () async => config,
        abiResolver: () async => 'arm64-v8a',
        publicJsonFetcher: (url) async {
          requestedUrl = url;
          return <String, dynamic>{'version': '1.1.0', 'force': false};
        },
      );

      final info = await checker.checkForUpdate();
      expect(info, isNotNull);
      expect(info!.sourceType, UpdateSourceType.github);
      expect(
        requestedUrl,
        '${config.versionJsonRawUriForBranch('beta')}?branch=beta&abi=arm64-v8a',
      );
    });

    test(
      'uses update manager base url and parses message/downloadLink',
      () async {
        final checker = AppUpdateChecker(
          localVersionLoader: () async => '1.0.0',
          abiResolver: () async => 'x86_64',
          configLoader: () async => const AppConfig(
            githubPage: 'https://github.com/ucrvk/vrc_monitor',
            branch: 'beta',
            updateManagerBaseUrl: 'https://updates.example.com/base/',
          ),
          publicJsonFetcher: (url) async {
            expect(
              url,
              'https://updates.example.com/base?branch=beta&abi=x86_64',
            );
            return <String, dynamic>{
              'version': '1.2.0',
              'force': true,
              'msg': 'Hotfix bundle',
              'downloadLink': 'https://updates.example.com/files/app.apk',
            };
          },
        );

        final info = await checker.checkForUpdate();
        expect(info, isNotNull);
        expect(info!.sourceType, UpdateSourceType.updateManager);
        expect(info.message, 'Hotfix bundle');
        expect(info.downloadLink, 'https://updates.example.com/files/app.apk');
      },
    );

    test('treats missing message/downloadLink as empty strings', () async {
      final checker = AppUpdateChecker(
        localVersionLoader: () async => '1.0.0',
        abiResolver: () async => 'armeabi-v7a',
        configLoader: () async => const AppConfig(
          githubPage: 'https://github.com/ucrvk/vrc_monitor',
          branch: 'main',
          updateManagerBaseUrl: 'https://updates.example.com',
        ),
        publicJsonFetcher: (url) async => <String, dynamic>{
          'version': '1.0.1',
          'force': false,
        },
      );

      final info = await checker.checkForUpdate();
      expect(info, isNotNull);
      expect(info!.message, isEmpty);
      expect(info.downloadLink, isEmpty);
    });

    test('keeps ignored-version behavior for non-force updates', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ignored_update_version': '1.3.0',
      });

      final checker = AppUpdateChecker(
        localVersionLoader: () async => '1.0.0',
        abiResolver: () async => null,
        configLoader: () async => const AppConfig(
          githubPage: 'https://github.com/ucrvk/vrc_monitor',
          branch: 'main',
        ),
        publicJsonFetcher: (url) async => <String, dynamic>{
          'version': '1.3.0',
          'force': false,
        },
      );

      final info = await checker.checkForUpdate();
      expect(info, isNull);
    });
  });
}
