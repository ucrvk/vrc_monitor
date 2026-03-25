import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vrc_monitor/network/web_client.dart';
import 'package:vrc_monitor/services/cache_manager.dart';

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

  static final Map<String, Uint8List> _memoryCache = {};
  static Future<io.Directory>? _cacheDirFuture;

  static Future<Uint8List?> loadBytes({
    required Dio dio,
    required String? imageUrl,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return null;

    final unifiedCache = CacheManager.instance.imageCache;
    final unifiedBytes = await unifiedCache.getByUrl(url);
    if (unifiedBytes != null && unifiedBytes.isNotEmpty) {
      _memoryCache[url] = unifiedBytes;
      return unifiedBytes;
    }

    final cached = _memoryCache[url];
    if (cached != null && cached.isNotEmpty) return cached;

    final cacheFile = await _cacheFileForUrl(url);
    if (await cacheFile.exists()) {
      final bytes = await cacheFile.readAsBytes();
      if (bytes.isNotEmpty) {
        _memoryCache[url] = bytes;
        return bytes;
      }
    }

    try {
      await unifiedCache.cacheByUrl(dio: dio, imageUrl: url);
      final fresh = await unifiedCache.getByUrl(url);
      if (fresh != null && fresh.isNotEmpty) {
        _memoryCache[url] = fresh;
        await cacheFile.writeAsBytes(fresh, flush: true);
        return fresh;
      }

      final response = await WebClient.getWithUserAgent<List<int>>(
        dio: dio,
        url: url,
        options: WebClient.withUserAgent(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        _memoryCache[url] = bytes;
        await cacheFile.writeAsBytes(bytes, flush: true);
        return bytes;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<io.File> _cacheFileForUrl(String url) async {
    _cacheDirFuture ??= _initCacheDir();
    final dir = await _cacheDirFuture!;
    final key = sha1.convert(utf8.encode(url)).toString();
    return io.File('${dir.path}/$key.img');
  }

  static Future<io.Directory> _initCacheDir() async {
    final tempDir = await getTemporaryDirectory();
    final dir = io.Directory('${tempDir.path}/image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
