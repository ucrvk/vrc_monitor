import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrc_monitor/update_checker.dart';
import 'package:vrc_monitor/widgets/login_page.dart';

class VrcMonitorApp extends StatefulWidget {
  const VrcMonitorApp({super.key});

  @override
  State<VrcMonitorApp> createState() => _VrcMonitorAppState();
}

class _VrcMonitorAppState extends State<VrcMonitorApp> {
  final AppUpdateChecker _updateChecker = AppUpdateChecker();
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateInBackground();
    });
  }

  Future<void> _checkUpdateInBackground() async {
    if (_checkedOnce || !mounted) return;
    _checkedOnce = true;

    final updateInfo = await _updateChecker.checkForUpdate();
    if (!mounted || updateInfo == null) return;

    if (updateInfo.force) {
      await _showForceUpdateDialog(updateInfo.latestVersion);
      return;
    }
    await _showOptionalUpdateDialog(updateInfo.latestVersion);
  }

  Future<void> _showOptionalUpdateDialog(String latestVersion) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发现新版本'),
          content: Text('发现新版本 $latestVersion，是否更新？\n取消后当前版本不再提示。'),
          actions: [
            TextButton(
              onPressed: () async {
                await _updateChecker.ignoreVersion(latestVersion);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('取消（不再提示）'),
            ),
            FilledButton(
              onPressed: () async {
                final launched = await launchUrl(
                  await _updateChecker.releaseUrlForVersion(latestVersion),
                  mode: LaunchMode.externalApplication,
                );
                if (dialogContext.mounted && launched) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('前往 GitHub 更新'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showForceUpdateDialog(String latestVersion) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发现新版本'),
          content: Text('发现新版本 $latestVersion，请立即更新。'),
          actions: [
            TextButton(
              onPressed: () {
                SystemNavigator.pop();
              },
              child: const Text('退出'),
            ),
            FilledButton(
              onPressed: () async {
                await launchUrl(
                  await _updateChecker.releaseUrlForVersion(latestVersion),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('前往更新'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRChat Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const LoginPage(),
    );
  }
}
