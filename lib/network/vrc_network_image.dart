import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrc_monitor/network/web_client.dart';

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

  @override
  State<VrcNetworkImage> createState() => _VrcNetworkImageState();
}

class _VrcNetworkImageState extends State<VrcNetworkImage> {
  static final Map<String, Uint8List> _memoryCache = {};

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
    final url = widget.imageUrl?.trim() ?? '';
    if (url.isEmpty) return null;

    final cached = _memoryCache[url];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final response = await widget.dio.get<List<int>>(
        url,
        options: WebClient.withUserAgent(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final bytes = Uint8List.fromList(response.data!);
        _memoryCache[url] = bytes;
        return bytes;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
