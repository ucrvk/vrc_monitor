import 'dart:io' as io;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/network/web_client.dart';
import 'package:vrc_monitor/widgets/vrc_avatar.dart';

class FriendDetailPage extends StatefulWidget {
  const FriendDetailPage({
    super.key,
    this.dio,
    required this.userId,
    this.displayName = '',
    this.avatarUrl,
    this.imageUrl,
    this.bio,
    this.nameColor,
    this.status = UserStatus.offline,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
    this.rawApi,
  });

  static final Dio _fallbackDio = WebClient.publicDio;

  final Dio? dio;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final String? bio;
  final Color? nameColor;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;
  final VrchatDartGenerated? rawApi;

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  late Future<User?> _userDetailsFuture;

  @override
  void initState() {
    super.initState();
    _userDetailsFuture = _fetchUserDetailsIfNeeded();
  }

  Future<User?> _fetchUserDetailsIfNeeded() async {
    final api = widget.rawApi;
    final needsUpdate = widget.pronouns == null || widget.dateJoined == null;

    if (!needsUpdate || api == null) {
      return null;
    }

    try {
      final (success, _) = await api
          .getUsersApi()
          .getUser(userId: widget.userId)
          .validateVrc();
      return success?.data;
    } catch (e) {
      debugPrint('Failed to fetch user details: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _userDetailsFuture,
      builder: (context, snapshot) {
        final enrichedUser = snapshot.data;
        return _FriendDetailPageContent(
          dio: widget.dio ?? FriendDetailPage._fallbackDio,
          displayName: widget.displayName,
          avatarUrl: widget.avatarUrl,
          imageUrl: widget.imageUrl,
          bio: widget.bio,
          nameColor: widget.nameColor,
          status: widget.status,
          statusDescription: widget.statusDescription,
          pronouns: enrichedUser?.pronouns ?? widget.pronouns,
          bioLinks: enrichedUser?.bioLinks ?? widget.bioLinks,
          dateJoined: enrichedUser?.dateJoined ?? widget.dateJoined,
          lastActivity:
              (enrichedUser?.lastActivity != null
                  ? DateTime.tryParse(enrichedUser!.lastActivity)
                  : null) ??
              widget.lastActivity,
        );
      },
    );
  }
}

class _FriendDetailPageContent extends StatelessWidget {
  const _FriendDetailPageContent({
    required this.dio,
    required this.displayName,
    this.avatarUrl,
    this.imageUrl,
    this.bio,
    this.nameColor,
    this.status = UserStatus.offline,
    this.statusDescription,
    this.pronouns,
    this.bioLinks = const [],
    this.dateJoined,
    this.lastActivity,
  });

  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final String? bio;
  final Color? nameColor;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final List<String> bioLinks;
  final DateTime? dateJoined;
  final DateTime? lastActivity;

  @override
  Widget build(BuildContext context) {
    const expandedHeaderHeight = 260.0;
    final bioText = (bio == null || bio!.trim().isEmpty)
        ? '暂无个人介绍'
        : bio!.trim();
    final visibleLinks = _sanitizeBioLinks(bioLinks).take(3).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: expandedHeaderHeight,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: _CollapsingHeader(
              dio: dio,
              displayName: displayName,
              avatarUrl: avatarUrl,
              imageUrl: imageUrl,
              nameColor: nameColor,
              expandedHeight: expandedHeaderHeight,
              status: status,
              statusDescription: statusDescription,
              pronouns: pronouns,
              onAvatarTap: () =>
                  _openImagePreview(context, imageUrl: avatarUrl, title: '头像'),
              onHeaderTap: () =>
                  _openImagePreview(context, imageUrl: imageUrl, title: '背景图'),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: false,
                  title: Text(
                    '个人介绍',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () async {
                          await Clipboard.setData(ClipboardData(text: bioText));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('个人介绍已复制')),
                            );
                          }
                        },
                        child: Text(bioText),
                      ),
                    ),
                    if (visibleLinks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '个人链接',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < visibleLinks.length; i++) ...[
                              FilledButton.tonal(
                                onPressed: () =>
                                    _openBioLink(context, visibleLinks[i]),
                                child: Text(_hostLabel(visibleLinks[i])),
                              ),
                              if (i != visibleLinks.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('加入时间'),
                      trailing: Text(_formatJoinedDate(dateJoined)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('上次在线'),
                      trailing: Text(_formatLastActivity(lastActivity)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openImagePreview(
    BuildContext context, {
    required String? imageUrl,
    required String title,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可预览的图片')));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ImagePreviewPage(dio: dio, imageUrl: url, title: title),
      ),
    );
  }

  static List<String> _sanitizeBioLinks(List<String> rawLinks) {
    final unique = <String>{};
    for (final raw in rawLinks) {
      final uri = _normalizeUri(raw);
      if (uri != null) {
        unique.add(uri.toString());
      }
    }
    return unique.toList();
  }

  static Uri? _normalizeUri(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static String _hostLabel(String url) {
    final uri = _normalizeUri(url);
    if (uri == null) return url;
    final host = uri.host.toLowerCase();
    if (host.startsWith('www.')) return host.substring(4);
    return host;
  }

  static Future<void> _openBioLink(BuildContext context, String url) async {
    final uri = _normalizeUri(url);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开该链接')));
    }
  }

  static String _formatJoinedDate(DateTime? value) {
    if (value == null) return '未知';
    final local = value.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }

  static String _formatLastActivity(DateTime? value) {
    if (value == null) return '未知';

    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({
    required this.dio,
    required this.displayName,
    required this.avatarUrl,
    required this.imageUrl,
    required this.nameColor,
    required this.expandedHeight,
    required this.status,
    required this.statusDescription,
    required this.pronouns,
    required this.onAvatarTap,
    required this.onHeaderTap,
  });

  final Dio dio;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final Color? nameColor;
  final double expandedHeight;
  final UserStatus status;
  final String? statusDescription;
  final String? pronouns;
  final VoidCallback onAvatarTap;
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final minHeight = topPadding + kToolbarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentHeight = constraints.biggest.height;
        final maxScrollExtent = expandedHeight - minHeight;
        final collapseRatio = maxScrollExtent <= 0
            ? 1.0
            : ((expandedHeight - currentHeight) / maxScrollExtent).clamp(
                0.0,
                1.0,
              );

        final avatarSize = lerpDouble(56, 30, collapseRatio)!;
        final left = lerpDouble(16, 56, collapseRatio)!;
        final expandedTop = currentHeight - avatarSize - 24;
        final collapsedTop = topPadding + (kToolbarHeight - avatarSize) / 2;
        final top = lerpDouble(expandedTop, collapsedTop, collapseRatio)!;
        final nameSize = lerpDouble(26, 18, collapseRatio)!;
        final imageOpacity = (1 - collapseRatio * 1.4).clamp(0.0, 1.0);

        final statusMeta = _statusMeta(status, statusDescription);
        final collapsedNameColor = Theme.of(context).colorScheme.onSurface;
        final collapsedSubColor = Theme.of(
          context,
        ).colorScheme.onSurfaceVariant;
        final mergedNameColor = Color.lerp(
          nameColor ?? Colors.white,
          collapsedNameColor,
          collapseRatio,
        );
        final mergedSubColor = Color.lerp(
          Colors.white70,
          collapsedSubColor,
          collapseRatio,
        );
        final pronounsText = pronouns?.trim();

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Theme.of(context).colorScheme.surface),
            if (imageOpacity > 0)
              Opacity(
                opacity: imageOpacity,
                child: _HeaderImage(
                  dio: dio,
                  imageUrl: imageUrl,
                  onTap: onHeaderTap,
                ),
              ),
            if (imageOpacity > 0)
              Opacity(
                opacity: imageOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: left,
              right: 16,
              top: top,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: VrcAvatar(
                      dio: dio,
                      imageUrl: avatarUrl,
                      size: avatarSize,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mergedNameColor,
                            fontSize: nameSize,
                            fontWeight: FontWeight.w700,
                            shadows: imageOpacity > 0
                                ? const [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : const [],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusMeta.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusMeta.color,
                            fontWeight: FontWeight.w600,
                            fontSize: lerpDouble(12, 13, collapseRatio),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pronounsText != null && pronounsText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      pronounsText,
                      style: TextStyle(
                        color: mergedSubColor,
                        fontWeight: FontWeight.w500,
                        fontSize: lerpDouble(12, 13, collapseRatio),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  _StatusMeta _statusMeta(UserStatus status, String? description) {
    final desc = description?.trim();
    final label = (desc != null && desc.isNotEmpty)
        ? desc
        : _fallbackStatusLabel(status);
    final color = switch (status) {
      UserStatus.joinMe => Colors.blue,
      UserStatus.active => Colors.green,
      UserStatus.askMe => Colors.orange,
      UserStatus.busy => Colors.red,
      UserStatus.offline => Colors.grey,
    };
    return _StatusMeta(label: label, color: color);
  }

  String _fallbackStatusLabel(UserStatus status) {
    return switch (status) {
      UserStatus.active => 'online',
      UserStatus.joinMe => 'joinMe',
      UserStatus.askMe => 'askMe',
      UserStatus.busy => 'noDisturb',
      UserStatus.offline => 'offline',
    };
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage({required this.dio, this.imageUrl, this.onTap});

  final Dio dio;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 40),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: VrcNetworkImage(
        dio: dio,
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        errorWidget: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({
    required this.dio,
    required this.imageUrl,
    required this.title,
  });

  final Dio dio;
  final String imageUrl;
  final String title;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late Future<Uint8List?> _imageFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _imageFuture = VrcNetworkImage.loadBytes(
      dio: widget.dio,
      imageUrl: widget.imageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveImage,
            tooltip: '保存图片',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Center(child: Text('图片加载失败'));
          }

          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: Image.memory(bytes)),
          );
        },
      ),
    );
  }

  Future<void> _saveImage() async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await VrcNetworkImage.loadBytes(
        dio: widget.dio,
        imageUrl: widget.imageUrl,
      );
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败：图片为空')));
        return;
      }

      final saveDir = await _resolveSaveDir();
      final ext = _guessExt(widget.imageUrl);
      final fileName = 'vrc_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = io.File(
        '${saveDir.path}${io.Platform.pathSeparator}$fileName',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('图片已保存到: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<io.Directory> _resolveSaveDir() async {
    io.Directory? dir;

    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }

    dir ??= await getApplicationDocumentsDirectory();

    final imageDir = io.Directory(
      '${dir.path}${io.Platform.pathSeparator}vrc_monitor_images',
    );
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  String _guessExt(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpg';
  }
}

class _StatusMeta {
  const _StatusMeta({required this.label, required this.color});

  final String label;
  final Color color;
}
