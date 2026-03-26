import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrc_monitor/services/cache_manager.dart' as vrc_cache;

class VrcNetworkImage extends StatefulWidget {
  const VrcNetworkImage({
    super.key,
    required this.dio,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final Dio dio;
  final String? imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  static Future<Uint8List?> loadBytes({
    required Dio dio,
    required String? imageUrl,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return null;

    final imageCache = vrc_cache.CacheManager.instance.imageCache;
    final fileId = vrc_cache.ImageCache.extractFileIdFromUrl(url);

    if (fileId != null && fileId.isNotEmpty) {
      final cached = await imageCache.getByFileId(fileId);
      if (cached != null && cached.isNotEmpty) return cached;

      await imageCache.cacheByFileId(dio: dio, fileId: fileId, imageUrl: url);
      final fresh = await imageCache.getByFileId(fileId);
      if (fresh != null && fresh.isNotEmpty) return fresh;
    }

    return null;
  }

  @override
  State<VrcNetworkImage> createState() => _VrcNetworkImageState();
}

class _VrcNetworkImageState extends State<VrcNetworkImage> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadImage();
  }

  @override
  void didUpdateWidget(covariant VrcNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageFuture = _loadImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ?? const SizedBox.shrink();
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return widget.errorWidget ?? const SizedBox.shrink();
        }

        return Image.memory(bytes, fit: widget.fit);
      },
    );
  }

  Future<Uint8List?> _loadImage() async {
    return VrcNetworkImage.loadBytes(
      dio: widget.dio,
      imageUrl: widget.imageUrl,
    );
  }
}
