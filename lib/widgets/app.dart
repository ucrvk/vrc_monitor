import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrc_monitor/app_settings.dart';
import 'package:vrc_monitor/services/app_navigator.dart';
import 'package:vrc_monitor/services/session_guard.dart';
import 'package:vrc_monitor/services/update_installer.dart';
import 'package:vrc_monitor/update_checker.dart';
import 'package:vrc_monitor/widgets/login_page.dart';

class VrcMonitorApp extends StatefulWidget {
  const VrcMonitorApp({super.key});

  @override
  State<VrcMonitorApp> createState() => _VrcMonitorAppState();
}

class _VrcMonitorAppState extends State<VrcMonitorApp> {
  final AppUpdateChecker _updateChecker = AppUpdateChecker();
  final UpdateInstaller _updateInstaller = UpdateInstaller();
  late final StreamSubscription<SessionEvent> _sessionSubscription;
  bool _checkedOnce = false;
  bool _navigatingToLogin = false;

  @override
  void initState() {
    super.initState();
    AppThemeSettings.load();
    AppMapSettings.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateInBackground();
    });
    _sessionSubscription = SessionGuard.instance.events.listen(
      _handleSessionEvent,
    );
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    super.dispose();
  }

  Future<void> _checkUpdateInBackground() async {
    if (_checkedOnce || !mounted) return;
    _checkedOnce = true;

    final updateInfo = await _updateChecker.checkForUpdate();
    if (!mounted || updateInfo == null) return;

    if (updateInfo.force) {
      await _showForceUpdateDialog(updateInfo);
      return;
    }
    await _showOptionalUpdateDialog(updateInfo);
  }

  Future<void> _showOptionalUpdateDialog(AppUpdateInfo info) async {
    final dialogContext = AppNavigator.navigatorKey.currentContext;
    if (dialogContext == null) return;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        final description = info.message.trim();
        final hasDescription = description.isNotEmpty;
        return AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
            hasDescription
                ? '发现新版本 ${info.latestVersion}\n\n更新简介：$description\n\n是否更新？\n取消后当前版本不再提示。'
                : '发现新版本 ${info.latestVersion}，是否更新？\n取消后当前版本不再提示。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final launched = await _openGithubDownload(info);
                if (context.mounted && launched) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('访问 GitHub 下载'),
            ),
            if (info.sourceType == UpdateSourceType.updateManager)
              FilledButton(
                onPressed: () async {
                  final launched = await _handleAutoDownloadAction(info);
                  if (context.mounted && launched) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('自动下载'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showForceUpdateDialog(AppUpdateInfo info) async {
    final dialogContext = AppNavigator.navigatorKey.currentContext;
    if (dialogContext == null) return;

    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        final description = info.message.trim();
        final hasDescription = description.isNotEmpty;
        return AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
            hasDescription
                ? '发现新版本 ${info.latestVersion}\n\n更新简介：$description\n\n请立即更新。'
                : '发现新版本 ${info.latestVersion}，请立即更新。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                SystemNavigator.pop();
              },
              child: const Text('退出'),
            ),
            FilledButton(
              onPressed: () async {
                await _openGithubDownload(info);
              },
              child: const Text('访问 GitHub 下载'),
            ),
            if (info.sourceType == UpdateSourceType.updateManager)
              FilledButton(
                onPressed: () async {
                  await _handleAutoDownloadAction(info);
                },
                child: const Text('自动下载'),
              ),
          ],
        );
      },
    );
  }

  Future<bool> _openGithubDownload(AppUpdateInfo info) async {
    return launchUrl(
      await _updateChecker.releaseUrlForVersion(info.latestVersion),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<bool> _handleAutoDownloadAction(AppUpdateInfo info) async {
    final downloadLink = info.downloadLink.trim();
    if (downloadLink.isEmpty) {
      _showLaunchFailedMessage('更新源未提供下载地址，请稍后重试。');
      return false;
    }

    final downloadUri = Uri.tryParse(downloadLink);
    if (downloadUri == null) return false;
    try {
      final installed = await _downloadAndInstallWithProgress(
        info,
        downloadLink,
      );
      if (installed) return true;
    } catch (_) {
      // fallback to opening URL
    }
    return launchUrl(downloadUri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _downloadAndInstallWithProgress(
    AppUpdateInfo info,
    String downloadLink,
  ) async {
    final dialogContext = AppNavigator.navigatorKey.currentContext;
    if (dialogContext == null) {
      return _updateInstaller.downloadAndInstallApk(
        downloadLink,
        expectedTotalBytes: info.sizeOriginal,
      );
    }

    final progress = ValueNotifier<_DownloadProgress>(
      const _DownloadProgress(receivedBytes: 0, totalBytes: null),
    );
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (dialogCtx) => ValueListenableBuilder<_DownloadProgress>(
        valueListenable: progress,
        builder: (buildContext, value, child) {
          final total = value.totalBytes;
          final fraction = total == null || total <= 0
              ? null
              : value.receivedBytes / total;
          final percentText = fraction == null
              ? '下载中...'
              : '下载中 ${(fraction * 100).clamp(0, 100).toStringAsFixed(1)}%';
          return AlertDialog(
            title: const Text('正在下载更新'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 12),
                Text(
                  '$percentText\n${_formatBytes(value.receivedBytes)}'
                  '${total == null ? '' : ' / ${_formatBytes(total)}'}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      return await _updateInstaller.downloadAndInstallApk(
        downloadLink,
        expectedTotalBytes: info.sizeOriginal,
        onProgress: (receivedBytes, totalBytes) {
          progress.value = _DownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : null,
          );
        },
      );
    } finally {
      progress.dispose();
      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).maybePop();
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  void _showLaunchFailedMessage(String message) {
    AppNavigator.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleSessionEvent(SessionEvent event) async {
    switch (event.type) {
      case SessionEventType.rotationNotice:
        final message = event.message?.trim() ?? '';
        if (message.isEmpty) return;
        AppNavigator.scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      case SessionEventType.requireLogin:
        if (_navigatingToLogin) return;
        final navigator = AppNavigator.navigatorKey.currentState;
        if (navigator == null) return;
        _navigatingToLogin = true;
        try {
          await navigator.pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) =>
                  LoginPage(skipTokenAutoLogin: event.skipTokenAutoLogin),
              settings: const RouteSettings(name: 'login'),
            ),
            (route) => false,
          );
        } finally {
          _navigatingToLogin = false;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeSettings.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,
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
          themeMode: themeMode,
          home: const LoginPage(),
        );
      },
    );
  }
}

class _DownloadProgress {
  const _DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;
}
