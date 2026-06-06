import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/google_drive_service.dart';

class StoryCoverImage extends StatefulWidget {
  static const String fallbackAsset = 'assets/covers/default_cover.png';

  final String imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final String driveFileId;
  final String fileType;

  const StoryCoverImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.driveFileId = '',
    this.fileType = '',
  });

  @override
  State<StoryCoverImage> createState() => _StoryCoverImageState();
}

class _StoryCoverImageState extends State<StoryCoverImage> {
  int _candidateIndex = 0;
  Future<String?>? _driveCoverFuture;

  @override
  void didUpdateWidget(covariant StoryCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.driveFileId != widget.driveFileId ||
        oldWidget.fileType != widget.fileType) {
      _candidateIndex = 0;
      _driveCoverFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedPath = widget.imagePath.trim();
    final Widget image;

    if (trimmedPath.startsWith('http')) {
      image = _networkImage(
        GoogleDriveService.coverImageCandidates(trimmedPath),
      );
    } else if (trimmedPath.isNotEmpty && File(trimmedPath).existsSync()) {
      image = Image.file(
        File(trimmedPath),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _fallback(),
      );
    } else {
      image = _driveCoverOrFallback();
    }

    final content = ColoredBox(
      color:
          widget.backgroundColor ??
          Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(width: widget.width, height: widget.height, child: image),
    );

    if (widget.borderRadius == null) return content;
    return ClipRRect(borderRadius: widget.borderRadius!, child: content);
  }

  Widget _networkImage(List<String> candidates) {
    if (candidates.isEmpty) return _fallback();

    final index = _candidateIndex >= candidates.length ? 0 : _candidateIndex;
    final imageUrl = candidates[index];

    return Image.network(
      imageUrl,
      key: ValueKey(imageUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _loading();
      },
      errorBuilder: (_, _, _) {
        if (index + 1 < candidates.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _candidateIndex = index + 1);
          });
          return _loading();
        }
        return _driveCoverOrFallback();
      },
    );
  }

  Widget _driveCoverOrFallback() {
    final driveFileId = widget.driveFileId.trim();
    final fileType = widget.fileType.trim().toLowerCase();
    if (driveFileId.isEmpty || fileType != 'epub') return _fallback();

    _driveCoverFuture ??= ApiService.getCachedDriveCoverPath(
      driveFileId: driveFileId,
      fileType: fileType,
    );

    return FutureBuilder<String?>(
      future: _driveCoverFuture,
      builder: (context, snapshot) {
        final coverPath = snapshot.data;
        if (coverPath != null && coverPath.isNotEmpty) {
          return Image.file(
            File(coverPath),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, _, _) => _fallback(),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loading();
        }
        return _fallback();
      },
    );
  }

  Widget _loading() {
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _fallback() {
    return Image.asset(
      StoryCoverImage.fallbackAsset,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
