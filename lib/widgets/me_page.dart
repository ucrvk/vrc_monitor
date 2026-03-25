import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/widgets/login_page.dart';
import 'package:vrc_monitor/widgets/settings_page.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class MePage extends StatefulWidget {
  const MePage({super.key, required this.api, required this.currentUser, this.onLogout});

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
        title: Text("我"),
        actions: [
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _trustColorForCurrentUser(_currentUser),
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
                leading: const Icon(Icons.badge_outlined),
                title: const Text('个人简介'),
                subtitle: Text(_safeText(_currentUser.bio, fallback: '暂无个人简介')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _saving ? null : _editBio,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.circle_notifications_outlined),
                title: const Text('状态'),
                subtitle: Text(_statusSummary(_currentUser)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _saving ? null : _editStatus,
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
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            onTap: _openSettingsPage,
          ),
        ),
      ],
      ),
    );
  }

  Future<void> _refreshCurrentUser() async {
    if (_loadingUser) return;
    setState(() {
      _loadingUser = true;
    });
    try {
      final (success, _) = await widget.api.rawApi.getAuthenticationApi().getCurrentUser().validateVrc();
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

  Future<void> _editStatus() async {
    UserStatus selectedStatus = _currentUser.status;
    final descController = TextEditingController(text: _currentUser.statusDescription);
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
                  DropdownMenuItem(value: UserStatus.joinMe, child: Text('欢迎加入')),
                  DropdownMenuItem(value: UserStatus.askMe, child: Text('忙碌')),
                  DropdownMenuItem(value: UserStatus.busy, child: Text('请勿打扰')),
                  DropdownMenuItem(value: UserStatus.offline, child: Text('离线')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失败：${failure?.error ?? '未知错误'}')));
        return;
      }
      setState(() {
        _currentUser = success.data;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新成功')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  Future<void> _logout() async {
    widget.onLogout?.call();
    await widget.api.auth.logout();
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
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

  Color _trustColorForCurrentUser(CurrentUser user) {
    final trustTags = user.tags.map((e) => e.toLowerCase()).toSet();
    if (trustTags.contains('system_trust_veteran')) {
      return const Color(0xFF8E44AD);
    }
    if (trustTags.contains('system_trust_trusted')) {
      return const Color(0xFFFF9800);
    }
    if (trustTags.contains('system_trust_known')) {
      return const Color(0xFF4CAF50);
    }
    if (trustTags.contains('system_trust_basic')) {
      return const Color(0xFF64B5F6);
    }
    return Colors.grey;
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