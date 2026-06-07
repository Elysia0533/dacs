import 'package:flutter/material.dart';
import 'dart:io';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/google_drive_service.dart';
import 'package:path_provider/path_provider.dart';
import 'chapter_reader_screen.dart';
import 'epub_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'reading_screen.dart';
import '../widgets/story_cover_image.dart';

class StoryDetailScreen extends StatefulWidget {
  final Story story;

  const StoryDetailScreen({super.key, required this.story});

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  bool _isDownloading = false;
  bool _descExpanded = false;
  double? _downloadProgress;
  int _downloadedBytes = 0;
  int? _downloadTotalBytes;
  late Story _story;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
  }

  Future<void> _addToLibrary() async {
    await ApiService.importLocalStory(_story);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã thêm vào Kệ sách!')));
    }
  }

  Future<void> _downloadStory() async {
    if (!_story.isFromDrive || _story.driveFileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Truyện này không hỗ trợ tải xuống trực tiếp.'),
        ),
      );
      return;
    }
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadedBytes = 0;
      _downloadTotalBytes = null;
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeTitle = _safeFileName(_story.title);
      final guessedExt = _storyFileType.isEmpty ? 'epub' : _storyFileType;
      var file = File('${dir.path}/$safeTitle.$guessedExt');
      file = await GoogleDriveService.downloadFileToFile(
        _story.driveFileId,
        file,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = receivedBytes;
            _downloadTotalBytes = totalBytes;
            _downloadProgress = totalBytes != null && totalBytes > 0
                ? receivedBytes / totalBytes
                : null;
          });
        },
      );

      final ext = await _detectFileType(file);
      if (!file.path.toLowerCase().endsWith('.$ext')) {
        final renamedFile = File('${dir.path}/$safeTitle.$ext');
        if (await renamedFile.exists()) {
          await renamedFile.delete();
        }
        file = await file.rename(renamedFile.path);
      }

      String iconUrl = _story.iconUrl;
      String description = _story.description;
      String author = _story.author;
      List<String> genres = _story.genres;
      int totalChapters = _story.totalChapters;
      String content = _story.content;
      if (ext == 'epub') {
        final metadata = await ApiService.extractEpubMetadata(file.path);
        if (metadata['coverPath'] != null &&
            metadata['coverPath']!.isNotEmpty) {
          iconUrl = metadata['coverPath']!;
        }
        if (metadata['description'] != null &&
            metadata['description']!.isNotEmpty) {
          description = metadata['description']!;
        }
        final metadataAuthor = metadata['author'];
        if (metadataAuthor is String && metadataAuthor.isNotEmpty) {
          author = metadataAuthor;
        }
        final metadataGenres = metadata['genres'];
        if (metadataGenres is List) {
          genres = metadataGenres.map((genre) => genre.toString()).toList();
        }
        final metadataChapterCount = metadata['chapterCount'];
        if (metadataChapterCount is int && metadataChapterCount > 0) {
          totalChapters = metadataChapterCount;
        }
      } else if (ext == 'txt') {
        content = await file.readAsString();
      }

      Story updatedStory = _story.copyWith(
        localPath: file.path,
        isLocal: true,
        iconUrl: iconUrl,
        description: description,
        author: author,
        genres: genres,
        totalChapters: totalChapters,
        content: content,
        fileType: ext,
      );
      await ApiService.importLocalStory(updatedStory);
      final savedStory = await ApiService.updateLocalStory(updatedStory);
      setState(() => _story = savedStory ?? updatedStory);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Lưu về máy thành công!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải xuống: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = null;
          _downloadedBytes = 0;
          _downloadTotalBytes = null;
        });
      }
    }
  }

  String get _downloadButtonLabel {
    if (!_isDownloading) return 'Lưu về máy';
    final progress = _downloadProgress;
    if (progress == null) return 'Đang tải...';
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return 'Đang tải $percent%';
  }

  String _safeFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return safe.isEmpty ? 'story_${_story.driveFileId}' : safe;
  }

  Future<String> _detectFileType(File file) async {
    final stream = file.openRead(0, 4);
    final header = <int>[];
    await for (final chunk in stream) {
      header.addAll(chunk);
    }
    if (header.length >= 4) {
      if (header[0] == 0x25 &&
          header[1] == 0x50 &&
          header[2] == 0x44 &&
          header[3] == 0x46) {
        return 'pdf';
      }
      if (header[0] == 0x50 && header[1] == 0x4B) {
        return 'epub';
      }
    }
    return 'txt';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get _storyFileType {
    if (_story.fileType.isNotEmpty) return _story.fileType.toLowerCase();
    if (_story.localPath.isNotEmpty && _story.localPath.contains('.')) {
      return _story.localPath.split('.').last.toLowerCase();
    }
    return 'epub';
  }

  bool get _canReadOnline =>
      _story.isFromDrive &&
      _story.localPath.isEmpty &&
      (_storyFileType == 'epub' || _storyFileType == 'pdf');

  void _startReading() {
    ApiService.recordReadingHistory(
      _story,
      chapterIndex: _story.savedChapterIndex,
      chapterTitle: _story.savedChapterIndex > 0
          ? 'Chương ${_story.savedChapterIndex + 1}'
          : 'Bắt đầu đọc',
    );

    final localPath = _story.localPath;
    if (localPath.isEmpty) {
      if (_story.isFromDrive && _story.driveFileId.isNotEmpty) {
        if (_storyFileType == 'pdf') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PdfReaderScreen(story: _story)),
          );
          return;
        }
        if (_storyFileType == 'epub') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EpubReaderScreen(story: _story)),
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng lưu truyện về máy trước khi đọc định dạng này.',
          ),
        ),
      );
      return;
    }
    if (localPath.endsWith('.pdf')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfReaderScreen(story: _story)),
      );
    } else if (localPath.endsWith('.epub')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChapterReaderScreen(story: _story)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReadingScreen(story: _story)),
      );
    }
  }

  Widget _buildCoverImage(double width, double height) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: StoryCoverImage(
          imagePath: _story.iconUrl,
          driveFileId: _story.driveFileId,
          fileType: _story.fileType,
          width: width,
          height: height,
          borderRadius: BorderRadius.circular(8),
          backgroundColor: Colors.grey.shade800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: size.height * 0.38,
            pinned: true,
            stretch: true,
            backgroundColor: colorScheme.surface,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  StoryCoverImage(
                    imagePath: _story.iconUrl,
                    driveFileId: _story.driveFileId,
                    fileType: _story.fileType,
                    width: double.infinity,
                    height: double.infinity,
                    backgroundColor: const Color(0xFF2C2C2C),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildCoverImage(90, 130),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _story.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black),
                                  ],
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              _buildInfoChip(
                                _storyFileType.toUpperCase(),
                                Colors.white.withValues(alpha: 0.25),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (_story.isFromDrive && _story.localPath.isEmpty) ...[
                        if (_canReadOnline) ...[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isDownloading ? null : _startReading,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 20,
                              ),
                              label: const Text('Đọc online'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isDownloading ? null : _downloadStory,
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 20),
                            label: Text(_downloadButtonLabel),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: _startReading,
                            icon: const Icon(Icons.menu_book_rounded, size: 20),
                            label: Text(
                              _story.savedChapterIndex > 0
                                  ? 'Đọc tiếp (Ch.${_story.savedChapterIndex + 1})'
                                  : 'Đọc ngay',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        if (!_story.isLocal) ...[
                          const SizedBox(width: 12),
                          IconButton.outlined(
                            onPressed: _addToLibrary,
                            icon: const Icon(Icons.library_add_rounded),
                            tooltip: 'Thêm vào kệ',
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (_isDownloading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 6),
                    Text(
                      _downloadTotalBytes == null
                          ? _formatBytes(_downloadedBytes)
                          : '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_downloadTotalBytes!)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildStoryMetaPanel(isDark),
                  if (_story.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildGenreChips(),
                  ],
                ],
              ),
            ),
          ),

          if (_story.description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Giới thiệu',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _descExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: Text(
                        _story.description,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      secondChild: Text(
                        _story.description,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _descExpanded = !_descExpanded),
                      child: Text(_descExpanded ? 'Thu gọn ▲' : 'Xem thêm ▼'),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white70,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStoryMetaPanel(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceLabel = _story.isFromDrive
        ? 'Google Drive'
        : (_story.isLocal ? 'Thiết bị' : 'Thư viện');
    final statusLabel = _story.localPath.isNotEmpty ? 'Offline' : 'Online';
    final chapterLabel = _story.totalChapters > 1
        ? '${_story.totalChapters}'
        : (_story.savedChapterIndex > 0
              ? '${_story.savedChapterIndex + 1}'
              : '1');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B19) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StoryMetaItem(
                  icon: Icons.source_rounded,
                  label: 'Nguồn',
                  value: sourceLabel,
                  color: colorScheme.primary,
                ),
              ),
              Expanded(
                child: _StoryMetaItem(
                  icon: Icons.article_rounded,
                  label: 'Định dạng',
                  value: _storyFileType.toUpperCase(),
                  color: const Color(0xFF5A7DB8),
                ),
              ),
              Expanded(
                child: _StoryMetaItem(
                  icon: Icons.menu_book_rounded,
                  label: 'Chương',
                  value: chapterLabel,
                  color: const Color(0xFF8A6F34),
                ),
              ),
              Expanded(
                child: _StoryMetaItem(
                  icon: Icons.offline_pin_rounded,
                  label: 'Trạng thái',
                  value: statusLabel,
                  color: const Color(0xFF4E8F7E),
                ),
              ),
            ],
          ),
          if (_story.author.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _story.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenreChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _story.genres.take(10).map((genre) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            genre,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StoryMetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StoryMetaItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
