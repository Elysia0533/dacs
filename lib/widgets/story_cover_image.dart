import 'dart:io';

import 'package:flutter/material.dart';

class StoryCoverImage extends StatelessWidget {
  static const String fallbackAsset = 'assets/covers/default_cover.png';

  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;

  const StoryCoverImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedPath = imagePath.trim();
    final Widget image;

    if (trimmedPath.startsWith('http')) {
      image = Image.network(
        trimmedPath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
      );
    } else if (trimmedPath.isNotEmpty && File(trimmedPath).existsSync()) {
      image = Image.file(
        File(trimmedPath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _fallback(),
      );
    } else {
      image = _fallback();
    }

    final content = ColoredBox(
      color: backgroundColor ?? Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(width: width, height: height, child: image),
    );

    if (borderRadius == null) return content;
    return ClipRRect(borderRadius: borderRadius!, child: content);
  }

  Widget _fallback() {
    return Image.asset(fallbackAsset, width: width, height: height, fit: fit);
  }
}
