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
    this.size = 40,
    this.placeholderIcon = Icons.person,
  });

  final Dio dio;
  final String? imageUrl;
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

class _AvatarWithCache extends StatelessWidget {
  const _AvatarWithCache({
    required this.dio,
    required this.imageUrl,
    required this.size,
    required this.iconSize,
    required this.placeholderIcon,
  });

  final Dio dio;
  final String imageUrl;
  final double size;
  final double iconSize;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl.trim();
    final fileId = cache.ImageCache.extractFileIdFromUrl(normalizedUrl);

    if (fileId == null || fileId.isEmpty) {
      return VrcNetworkImage(
        dio: dio,
        imageUrl: normalizedUrl,
        fit: BoxFit.cover,
        placeholder: Icon(placeholderIcon, size: iconSize),
        errorWidget: Icon(placeholderIcon, size: iconSize),
      );
    }

    Future.microtask(
      () => cache.CacheManager.instance.imageCache.cacheByFileId(
        dio: dio,
        fileId: fileId,
        imageUrl: normalizedUrl,
      ),
    );

    return FutureBuilder<Uint8List?>(
      future: cache.CacheManager.instance.imageCache.getByFileId(fileId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
          );
        }
        return VrcNetworkImage(
          dio: dio,
          imageUrl: normalizedUrl,
          fit: BoxFit.cover,
          placeholder: Icon(placeholderIcon, size: iconSize),
          errorWidget: Icon(placeholderIcon, size: iconSize),
        );
      },
    );
  }
}
