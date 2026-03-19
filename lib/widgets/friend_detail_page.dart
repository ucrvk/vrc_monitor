import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';

class FriendDetailPage extends StatelessWidget {
  const FriendDetailPage({
    super.key,
    this.dio,
    this.displayName = '',
    this.avatarUrl,
    this.imageUrl,
    this.bio,
    this.nameColor,
  });

  static final Dio _fallbackDio = Dio();
  Dio get _dio => dio ?? _fallbackDio;

  final Dio? dio;
  final String displayName;
  final String? avatarUrl;
  final String? imageUrl;
  final String? bio;
  final Color? nameColor;

  @override
  Widget build(BuildContext context) {
    final bioText = (bio == null || bio!.trim().isEmpty) ? '暂无个人介绍' : bio!.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('好友信息')),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _HeaderImage(dio: _dio, imageUrl: imageUrl),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: ClipOval(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: VrcNetworkImage(
                        dio: _dio,
                        imageUrl: avatarUrl,
                        placeholder: const Icon(Icons.person),
                        errorWidget: const Icon(Icons.person),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: nameColor ?? Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('个人介绍', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(bioText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage({required this.dio, this.imageUrl});

  final Dio dio;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 40)),
      );
    }

    return VrcNetworkImage(
      dio: dio,
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      errorWidget: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
      ),
    );
  }
}
