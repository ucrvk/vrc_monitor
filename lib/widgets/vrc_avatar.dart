import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vrc_monitor/network/vrc_network_image.dart';

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
              ? VrcNetworkImage(
                  dio: dio,
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: Icon(placeholderIcon, size: iconSize),
                  errorWidget: Icon(placeholderIcon, size: iconSize),
                )
              : Icon(placeholderIcon, size: iconSize),
        ),
      ),
    );
  }
}
