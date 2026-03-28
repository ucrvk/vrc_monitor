import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrc_monitor/app_config.dart';
import 'package:vrc_monitor/app_settings.dart';
import 'package:vrc_monitor/services/cache_manager.dart';
import 'package:vrc_monitor/services/world_store.dart';
import 'package:vrc_monitor/update_checker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppUpdateChecker _updateChecker = AppUpdateChecker();
  String _branch = AppConfig.fallback.branch;
  String _appVersion = '读取中...';
  bool _checkingUpdate = false;
  bool _clearingWorldStore = false;
  bool _clearingImageCache = false;
  int _storedWorldCount = 0;

  @override
  void initState() {
    super.initState();
    _loadBranch();
    _loadAppVersion();
    _refreshWorldCount();
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
      final info = await _updateChecker.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('发现新版本'),
            content: Text(
              info.force
                  ? '发现新版本 ${info.latestVersion}，请立即更新。'
                  : '发现新版本 ${info.latestVersion}，是否前往更新？',
            ),
            actions: [
              if (!info.force)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('稍后'),
                ),
              FilledButton(
                onPressed: () async {
                  await launchUrl(
                    await _updateChecker.releaseUrlForVersion(
                      info.latestVersion,
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('前往更新'),
              ),
            ],
          );
        },
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
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(),
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
      if (launched) return;
      _showLaunchFailedMessage();
    } on PlatformException {
      _showLaunchFailedMessage();
    } catch (_) {
      _showLaunchFailedMessage();
    }
  }

  void _showLaunchFailedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接，请稍后重试。')));
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
              subtitle: Text('当前：$_branch'),
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
            child: ListTile(
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
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openPrivacyPolicy,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('访问项目 GitHub'),
              subtitle: Text('当前版本 $_appVersion'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openProjectGithub,
            ),
          ),
          Card(
            child: ListTile(
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
                    '正在努力开发了',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
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
