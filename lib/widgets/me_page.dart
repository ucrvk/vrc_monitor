import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;
import 'package:vrc_monitor/services/auth_manager.dart';
import 'package:vrc_monitor/services/auth_vault.dart';
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/widgets/friend_detail_page.dart';
import 'package:vrc_monitor/widgets/login_page.dart';
import 'package:vrc_monitor/widgets/settings_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';
import 'package:vrc_monitor/widgets/world_detail_page.dart';

enum QuickLookupType { instance, world, user, avatar }

class QuickLookupMatch {
  const QuickLookupMatch._({
    required this.type,
    required this.value,
    this.worldId,
    this.instanceId,
  });

  const QuickLookupMatch.instance({
    required String value,
    required String worldId,
    required String instanceId,
  }) : this._(
         type: QuickLookupType.instance,
         value: value,
         worldId: worldId,
         instanceId: instanceId,
       );

  const QuickLookupMatch.world(String value)
    : this._(type: QuickLookupType.world, value: value);

  const QuickLookupMatch.user(String value)
    : this._(type: QuickLookupType.user, value: value);

  const QuickLookupMatch.avatar(String value)
    : this._(type: QuickLookupType.avatar, value: value);

  final QuickLookupType type;
  final String value;
  final String? worldId;
  final String? instanceId;
}

final RegExp _quickLookupInstanceRegExp = RegExp(
  r'''wrld_[0-9a-fA-F-]{36}:[^\s"'`，。；！？、,;!?]+''',
);

QuickLookupMatch? parseQuickLookup(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final instanceMatch = _quickLookupInstanceRegExp.firstMatch(text);
  if (instanceMatch != null) {
    final value = instanceMatch.group(0)!;
    final parsed = cache.CacheManager.parseLocation(value);
    if (parsed != null) {
      return QuickLookupMatch.instance(
        value: parsed.rawLocation,
        worldId: parsed.worldId,
        instanceId: parsed.instanceId,
      );
    }
    final colonIndex = value.indexOf(':');
    return QuickLookupMatch.instance(
      value: value,
      worldId: value.substring(0, colonIndex),
      instanceId: value.substring(colonIndex + 1),
    );
  }

  final worldMatch = RegExp(
    r'wrld_[0-9a-fA-F-]{36}',
  ).firstMatch(text)?.group(0);
  if (worldMatch != null) {
    return QuickLookupMatch.world(worldMatch);
  }

  final userMatch = RegExp(r'usr_[0-9a-fA-F-]{36}').firstMatch(text)?.group(0);
  if (userMatch != null) {
    return QuickLookupMatch.user(userMatch);
  }

  final avatarMatch = RegExp(
    r'avtr_[0-9a-fA-F-]{36}',
  ).firstMatch(text)?.group(0);
  if (avatarMatch != null) {
    return QuickLookupMatch.avatar(avatarMatch);
  }

  return null;
}

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.api,
    required this.currentUser,
    this.onLogout,
  });

  final VrchatDart api;
  final CurrentUser currentUser;
  final VoidCallback? onLogout;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late CurrentUser _currentUser;
  int? _onlineUsers;
  bool _loadingUser = false;
  bool _saving = false;
  bool _lookupLoading = false;
  bool _bioExpanded = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    _refreshCurrentUser();
    _refreshOnlineUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我'),
        actions: [
          AnimatedBuilder(
            animation: UserStore.instance,
            builder: (context, _) {
              final status = UserStore.instance.wsConnectionStatus;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: '服务器连接状态',
                  onPressed: () {
                    final failure = UserStore.instance.wsFailureMessage;
                    final text = switch (status) {
                      WsConnectionStatus.connected => '服务器连接状态：连接',
                      WsConnectionStatus.connecting => '服务器连接状态：正在连接',
                      WsConnectionStatus.disconnected =>
                        failure == null
                            ? '服务器连接状态：断开连接'
                            : '服务器连接状态：断开连接\n$failure',
                    };
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(text)));
                  },
                  icon: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: switch (status) {
                        WsConnectionStatus.connected => Colors.green,
                        WsConnectionStatus.connecting => Colors.yellow,
                        WsConnectionStatus.disconnected => Colors.red,
                      },
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            onPressed: _logout,
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  VrcAvatar(
                    dio: widget.api.rawApi.dio,
                    imageUrl: _currentUserAvatarUrl(_currentUser),
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentUser.displayName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: UserStore.instance.trustColorForTags(
                                  _currentUser.tags,
                                ),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_loadingUser)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('称谓'),
                  subtitle: Text(
                    _safeText(_currentUser.pronouns, fallback: '未设定'),
                  ),
                  trailing: IconButton(
                    tooltip: '编辑称谓',
                    onPressed: _saving ? null : _editPronouns,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('个人简介'),
                  subtitle: _buildBioSubtitle(),
                  isThreeLine: _bioExpanded,
                  trailing: IconButton(
                    tooltip: '编辑个人简介',
                    onPressed: _saving ? null : _editBio,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.circle_notifications_outlined),
                  title: const Text('状态'),
                  subtitle: Text(_statusSummary(_currentUser)),
                  trailing: IconButton(
                    tooltip: '编辑状态',
                    onPressed: _saving ? null : _editStatus,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('当前总在线人数'),
              subtitle: Text(_onlineUsers == null ? '读取中...' : '$_onlineUsers'),
              trailing: const Icon(Icons.refresh),
              onTap: _refreshOnlineUsers,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.search),
              title: const Text('快速查询'),
              subtitle: const Text('支持 instance / world / user / avatar'),
              trailing: _lookupLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _lookupLoading ? null : _openQuickLookup,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              onTap: _openSettingsPage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSubtitle() {
    final bio = _currentUser.bio.trim();
    if (bio.isEmpty) {
      return const Text('暂无个人简介');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bio,
          maxLines: _bioExpanded ? null : 4,
          overflow: _bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: _bioExpanded ? '收起简介' : '展开简介',
            onPressed: () {
              setState(() {
                _bioExpanded = !_bioExpanded;
              });
            },
            icon: Icon(
              _bioExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshCurrentUser() async {
    if (_loadingUser) return;
    setState(() {
      _loadingUser = true;
    });
    try {
      final (success, _) = await widget.api.rawApi
          .getAuthenticationApi()
          .getCurrentUser()
          .validateVrc();
      if (!mounted) return;
      if (success != null) {
        setState(() {
          _currentUser = success.data;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingUser = false;
        });
      }
    }
  }

  Future<void> _refreshOnlineUsers() async {
    final (success, _) = await widget.api.rawApi
        .getMiscellaneousApi()
        .getCurrentOnlineUsers()
        .validateVrc();
    if (!mounted) return;
    setState(() {
      _onlineUsers = success?.data;
    });
  }

  Future<void> _editBio() async {
    final controller = TextEditingController(text: _currentUser.bio);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改个人简介'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          maxLength: 512,
          decoration: const InputDecoration(
            hintText: '输入个人简介',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _updateUser(UpdateUserRequest(bio: controller.text.trim()));
  }

  Future<void> _editPronouns() async {
    final controller = TextEditingController(text: _currentUser.pronouns);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改称谓'),
        content: TextField(
          controller: controller,
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: '例如 he/him、she/her、they/them',
            helperText: '留空表示未设定',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _updateUser(UpdateUserRequest(pronouns: controller.text.trim()));
  }

  Future<void> _editStatus() async {
    UserStatus selectedStatus = _currentUser.status;
    final descController = TextEditingController(
      text: _currentUser.statusDescription,
    );
    final historyOptions = _currentUser.statusHistory
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    String? selectedHistory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('修改状态'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<UserStatus>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: '状态',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: UserStatus.active, child: Text('在线')),
                  DropdownMenuItem(
                    value: UserStatus.joinMe,
                    child: Text('欢迎加入'),
                  ),
                  DropdownMenuItem(value: UserStatus.askMe, child: Text('忙碌')),
                  DropdownMenuItem(value: UserStatus.busy, child: Text('请勿打扰')),
                  DropdownMenuItem(
                    value: UserStatus.offline,
                    child: Text('离线'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedStatus = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: '状态描述',
                  border: OutlineInputBorder(),
                ),
              ),
              if (historyOptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedHistory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '历史状态描述',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('选择历史描述（可选）'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('不使用历史描述'),
                    ),
                    for (final option in historyOptions)
                      DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedHistory = value;
                      if (value != null && value.isNotEmpty) {
                        descController.text = value;
                      }
                    });
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _updateUser(
      UpdateUserRequest(
        status: selectedStatus,
        statusDescription: descController.text.trim(),
      ),
    );
  }

  Future<void> _updateUser(UpdateUserRequest request) async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    try {
      final (success, failure) = await widget.api.rawApi
          .getUsersApi()
          .updateUser(userId: _currentUser.id, updateUserRequest: request)
          .validateVrc();
      if (!mounted) return;
      if (success == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败：${failure?.error ?? '未知错误'}')),
        );
        return;
      }
      setState(() {
        _currentUser = success.data;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新成功')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  Future<void> _openQuickLookup() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text?.trim() ?? '';
    if (clipboardText.isNotEmpty && parseQuickLookup(clipboardText) != null) {
      await _runQuickLookupInput(clipboardText);
      return;
    }

    final query = await _showQuickLookupDialog();
    if (!mounted || query == null) return;
    await _runQuickLookupInput(query);
  }

  Future<void> _runQuickLookupInput(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入要查询的内容')));
      return;
    }

    setState(() {
      _lookupLoading = true;
    });
    try {
      final match = parseQuickLookup(input);
      if (match == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未识别到 instance、world、user 或 avatar ID')),
        );
        return;
      }

      switch (match.type) {
        case QuickLookupType.instance:
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorldDetailPage(
                api: widget.api.rawApi,
                worldId: match.worldId!,
                instanceId: match.instanceId!,
              ),
            ),
          );
          break;
        case QuickLookupType.world:
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂不支持仅 world ID 查询')));
          break;
        case QuickLookupType.user:
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  FriendDetailPage(userId: match.value, api: widget.api.rawApi),
            ),
          );
          break;
        case QuickLookupType.avatar:
          await _handleAvatarLookup(match.value);
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _lookupLoading = false;
        });
      }
    }
  }

  Future<String?> _showQuickLookupDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('快速查询'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴任意文本，自动识别 instance / world / user / avatar',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('查询'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAvatarLookup(String avatarId) async {
    final (avatarSuccess, avatarFailure) = await widget.api.rawApi
        .getAvatarsApi()
        .getAvatar(avatarId: avatarId)
        .validateVrc();
    if (!mounted) return;

    if (avatarSuccess == null) {
      if (avatarFailure?.response?.statusCode == 404) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到该 Avatar')));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('查询 Avatar 失败: ${avatarFailure?.error ?? '未知错误'}'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设为当前模型'),
        content: Text('已识别到 Avatar：$avatarId\n是否将其设为您的模型？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final (selectSuccess, selectFailure) = await widget.api.rawApi
        .getAvatarsApi()
        .selectAvatar(avatarId: avatarId)
        .validateVrc();
    if (!mounted) return;

    if (selectSuccess == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('设置 Avatar 失败: ${selectFailure?.error ?? '未知错误'}'),
        ),
      );
      return;
    }

    setState(() {
      _currentUser = selectSuccess.data;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已将该 Avatar 设为您的模型')));
  }

  Future<void> _logout() async {
    widget.onLogout?.call();
    await widget.api.auth.logout();
    await AuthManager.instance.clearSession(widget.api);
    final rememberPassword = await AuthVault.instance.readRememberPassword();
    if (!rememberPassword) {
      await AuthVault.instance.clearPassword();
    }
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const LoginPage(skipTokenAutoLogin: true),
      ),
      (route) => false,
    );
  }

  String _safeText(String? value, {required String fallback}) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _statusSummary(CurrentUser user) {
    final label = switch (user.status) {
      UserStatus.active => '在线',
      UserStatus.joinMe => '欢迎加入',
      UserStatus.askMe => '忙碌',
      UserStatus.busy => '请勿打扰',
      UserStatus.offline => '离线',
    };
    final desc = user.statusDescription.trim();
    if (desc.isEmpty) return label;
    return '$label · $desc';
  }

  String? _currentUserAvatarUrl(CurrentUser user) {
    final candidates = [
      user.profilePicOverrideThumbnail,
      user.profilePicOverride,
      user.currentAvatarThumbnailImageUrl,
      user.userIcon,
      user.currentAvatarImageUrl,
    ];

    for (final url in candidates) {
      if (url.isNotEmpty) return url;
    }
    return null;
  }
}
