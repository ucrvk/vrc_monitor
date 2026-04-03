import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrc_monitor/app_config.dart';
import 'package:vrc_monitor/app_settings.dart';
import 'package:vrc_monitor/services/auth_vault.dart';
import 'package:vrc_monitor/services/cache_manager.dart';
import 'package:vrc_monitor/services/update_installer.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/update_checker.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _fixedFriendUserId =
      'usr_33db0274-7fb6-4057-ba68-5d13fa66dc47';
  final AppUpdateChecker _updateChecker = AppUpdateChecker();
  final UpdateInstaller _updateInstaller = UpdateInstaller();
  String _branch = AppConfig.fallback.branch;
  String _appVersion = '读取中...';
  bool _checkingUpdate = false;
  bool _clearingWorldStore = false;
  bool _clearingImageCache = false;
  bool _updatingForceAutoLogin = false;
  bool _forceAutoLogin = false;
  int _storedWorldCount = 0;

  @override
  void initState() {
    super.initState();
    _loadBranch();
    _loadAppVersion();
    _loadAuthSettings();
    _refreshWorldCount();
  }

  Future<void> _loadAuthSettings() async {
    final forceAutoLogin = await AuthVault.instance.readForceAutoLogin();
    if (!mounted) return;
    setState(() {
      _forceAutoLogin = forceAutoLogin;
    });
  }

  Future<void> _loadBranch() async {
    final config = await AppConfigLoader.load();
    if (!mounted) return;
    setState(() {
      _branch = config.branch;
    });
  }

  Future<void> _setBranch(String value) async {
    await AppConfigLoader.setBranch(value);
    if (!mounted) return;
    setState(() {
      _branch = value;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('发布通道已切换到 $value')));
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = '未知版本';
      });
    }
  }

  Future<void> _refreshWorldCount() async {
    await WorldStore.instance.initialize();
    if (!mounted) return;
    setState(() {
      _storedWorldCount = WorldStore.instance.storedWorldCount;
    });
  }

  Future<void> _clearWorldStore() async {
    if (_clearingWorldStore) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _clearingWorldStore = true;
    });
    try {
      final removed = await WorldStore.instance.clearStorage();
      if (!mounted) return;
      await _refreshWorldCount();
      messenger.showSnackBar(
        SnackBar(content: Text('已清理 world 存储，共删除 $removed 条')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearingWorldStore = false;
        });
      }
    }
  }

  Future<void> _clearImageCache() async {
    if (_clearingImageCache) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _clearingImageCache = true;
    });
    try {
      final removed = await CacheManager.instance.imageCache.clearAll();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('已清理图片缓存，删除 $removed 个文件')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearingImageCache = false;
        });
      }
    }
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
    });
    try {
      final info = await _updateChecker.checkForUpdate(
        respectIgnoredVersion: false,
      );
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已经是最新版本')));
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
            info.force
                ? _updateMessage(info, force: true)
                : _updateMessage(info, force: false),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                await _openGithubDownload(info);
                if (mounted) {
                  navigator.pop();
                }
              },
              child: const Text('访问 GitHub 下载'),
            ),
            if (info.sourceType == UpdateSourceType.updateManager)
              FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(dialogContext);
                  await _handleAutoDownloadAction(info);
                  if (mounted) {
                    navigator.pop();
                  }
                },
                child: const Text('自动下载'),
              ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    String policy;
    try {
      policy = (await rootBundle.loadString('assets/privacyPolicy.md')).trim();
    } catch (_) {
      policy = '';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('隐私政策'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: MarkdownBody(
              data: policy.isEmpty ? '暂无隐私政策内容' : policy,
              selectable: true,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProjectGithub() async {
    try {
      final config = await AppConfigLoader.load();
      final launched = await launchUrl(
        config.githubPageUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showLaunchFailedMessage();
    } catch (_) {
      _showLaunchFailedMessage();
    }
  }

  Future<void> _setForceAutoLogin(bool value) async {
    if (_updatingForceAutoLogin) return;

    if (value) {
      final username = (await AuthVault.instance.readUsername()).trim();
      final password = await AuthVault.instance.readPassword();
      if (username.isEmpty || password.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先使用记住密码登录一次后再开启强制自动登录')));
        return;
      }
    }

    setState(() {
      _updatingForceAutoLogin = true;
    });
    try {
      await AuthVault.instance.writeForceAutoLogin(value);
      if (!mounted) return;
      setState(() {
        _forceAutoLogin = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '已开启强制自动登录，Token 全部失效时会自动使用保存的账号密码重新登录' : '已关闭强制自动登录',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingForceAutoLogin = false;
        });
      }
    }
  }

  void _showLaunchFailedMessage([String message = '无法打开链接，请稍后重试。']) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _updateMessage(AppUpdateInfo info, {required bool force}) {
    final message = info.message.trim();
    final tail = force ? '请立即更新。' : '是否前往更新？';
    if (message.isEmpty) {
      return '发现新版本 ${info.latestVersion}，$tail';
    }
    return '发现新版本 ${info.latestVersion}\n\n更新简介：$message\n\n$tail';
  }

  Future<void> _openGithubDownload(AppUpdateInfo info) async {
    final launched = await launchUrl(
      await _updateChecker.releaseUrlForVersion(info.latestVersion),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) _showLaunchFailedMessage();
  }

  Future<void> _handleAutoDownloadAction(AppUpdateInfo info) async {
    final downloadLink = info.downloadLink.trim();
    if (downloadLink.isEmpty) {
      _showLaunchFailedMessage('更新源未提供下载地址，请稍后重试。');
      return;
    }

    final downloadUri = Uri.tryParse(downloadLink);
    if (downloadUri == null) {
      _showLaunchFailedMessage();
      return;
    }
    try {
      final installed = await _downloadAndInstallWithProgress(
        info,
        downloadLink,
      );
      if (installed) return;
    } catch (_) {
      // fallback to opening URL
    }
    final launched = await launchUrl(
      downloadUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) _showLaunchFailedMessage();
  }

  Future<bool> _downloadAndInstallWithProgress(
    AppUpdateInfo info,
    String downloadLink,
  ) async {
    final progress = ValueNotifier<_DownloadProgress>(
      const _DownloadProgress(receivedBytes: 0, totalBytes: null),
    );
    showDialog<void>(
      context: context,
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
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
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

  Future<void> _openFixedFriendDetail() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const FriendDetailPage(userId: _fixedFriendUserId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主题色设置'),
              subtitle: ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeSettings.themeModeNotifier,
                builder: (context, mode, child) => Text(_themeLabel(mode)),
              ),
              trailing: ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeSettings.themeModeNotifier,
                builder: (context, mode, child) => DropdownButton<ThemeMode>(
                  value: mode,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('跟随系统'),
                    ),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      AppThemeSettings.setThemeMode(value);
                    }
                  },
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alt_route),
              title: const Text('发布通道选择'),
              subtitle: Text('当前: $_branch'),
              trailing: DropdownButton<String>(
                value: _branch,
                items: const [
                  DropdownMenuItem(value: 'main', child: Text('main')),
                  DropdownMenuItem(value: 'beta', child: Text('beta')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setBranch(value);
                  }
                },
              ),
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.lock_reset_outlined),
              value: _forceAutoLogin,
              onChanged: _updatingForceAutoLogin ? null : _setForceAutoLogin,
              title: const Text('强制自动登录'),
              subtitle: const Text(
                '开启后会强制记住密码；当 Token 池全部失效时，将直接使用保存的账号密码重新登录。',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('清理 world 存储'),
              subtitle: Text('已存储 $_storedWorldCount 条'),
              trailing: _clearingWorldStore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
              onTap: _clearingWorldStore ? null : _clearWorldStore,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清理图片缓存'),
              subtitle: const Text('效果类似系统“清缓存”中的图片缓存清理'),
              trailing: _clearingImageCache
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              onTap: _clearingImageCache ? null : _clearImageCache,
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('检查更新'),
                  trailing: _checkingUpdate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _checkingUpdate ? null : _checkUpdate,
                ),
                Divider(height: 1, thickness: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openPrivacyPolicy,
                ),
                Divider(height: 1, thickness: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('开源许可'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'VRChat Monitor',
                      applicationVersion: _appVersion,
                    );
                  },
                ),
                Divider(height: 1, thickness: 1),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('访问项目 GitHub'),
                  subtitle: Text('当前版本 $_appVersion'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openProjectGithub,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Image(image: AssetImage('assets/developing.gif'), width: 220),
                  SizedBox(height: 12),
                  Text(
                    '正在努力开发中',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openFixedFriendDetail,
            child: const SizedBox(height: 10),
          ),
          const Text('最后希望有人能够添加我的好友:wenwen12305', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
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
