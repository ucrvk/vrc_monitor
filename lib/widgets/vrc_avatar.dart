import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as cache;

class VrcAvatar extends StatelessWidget {
  const VrcAvatar({
    super.key,
    required this.dio,
    this.imageUrl,
    this.fileId,
    this.size = 40,
    this.placeholderIcon = Icons.person,
  });

  final Dio dio;
  final String? imageUrl;
  final String? fileId;
  final double size;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    final iconSize = size * 0.55;
    final bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: bgColor,
          child: hasImage
              ? _AvatarWithCache(
                  dio: dio,
                  imageUrl: imageUrl!,
                  fileId: fileId,
                  size: size,
                  iconSize: iconSize,
                  placeholderIcon: placeholderIcon,
                )
              : Icon(placeholderIcon, size: iconSize),
        ),
      ),
    );
  }
}

class _AvatarWithCache extends StatefulWidget {
  const _AvatarWithCache({
    required this.dio,
    required this.imageUrl,
    this.fileId,
    required this.size,
    required this.iconSize,
    required this.placeholderIcon,
  });

  final Dio dio;
  final String imageUrl;
  final String? fileId;
  final double size;
  final double iconSize;
  final IconData placeholderIcon;

  @override
  State<_AvatarWithCache> createState() => _AvatarWithCacheState();
}

class _AvatarWithCacheState extends State<_AvatarWithCache> {
  Uint8List? _cachedBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_AvatarWithCache oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fileId != widget.fileId) {
      setState(() {
        _cachedBytes = null;
        _isLoading = true;
      });
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final normalizedUrl = widget.imageUrl.trim();
    final resolvedFileId = widget.fileId?.trim().isNotEmpty == true
        ? widget.fileId!.trim()
        : cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (resolvedFileId == null || resolvedFileId.isEmpty) {
      if (mounted) {
        setState(() {
          _cachedBytes = null;
          _isLoading = false;
        });
      }
      return;
    }

    var bytes = await cache.CacheManager.instance.imageCache.getByFileId(
      resolvedFileId,
    );

    if (bytes != null && bytes.isNotEmpty) {
      if (mounted) {
        setState(() {
          _cachedBytes = bytes;
          _isLoading = false;
        });
      }
      return;
    }

    await cache.CacheManager.instance.imageCache.cacheByFileId(
      dio: widget.dio,
      fileId: resolvedFileId,
      imageUrl: normalizedUrl,
    );

    bytes = await cache.CacheManager.instance.imageCache.getByFileId(
      resolvedFileId,
    );

    if (mounted) {
      setState(() {
        _cachedBytes = bytes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = widget.imageUrl.trim();
    final resolvedFileId = widget.fileId?.trim().isNotEmpty == true
        ? widget.fileId!.trim()
        : cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (_cachedBytes != null && _cachedBytes!.isNotEmpty) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: ClipOval(child: Image.memory(_cachedBytes!, fit: BoxFit.cover)),
      );
    }

    if (resolvedFileId == null || resolvedFileId.isEmpty) {
      return VrcNetworkImage(
        dio: widget.dio,
        imageUrl: normalizedUrl,
        fit: BoxFit.cover,
        placeholder: Icon(widget.placeholderIcon, size: widget.iconSize),
        errorWidget: Icon(widget.placeholderIcon, size: widget.iconSize),
      );
    }

    if (_isLoading) {
      return Icon(widget.placeholderIcon, size: widget.iconSize);
    }

    return VrcNetworkImage(
      dio: widget.dio,
      imageUrl: normalizedUrl,
      fit: BoxFit.cover,
      placeholder: Icon(widget.placeholderIcon, size: widget.iconSize),
      errorWidget: Icon(widget.placeholderIcon, size: widget.iconSize),
    );
  }
}
