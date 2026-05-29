import 'package:flutter/material.dart';
import 'dart:io';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/google_drive_service.dart';
import 'package:path_provider/path_provider.dart';
import 'chapter_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'reading_screen.dart';

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
      final bytes = await GoogleDriveService.downloadFileBytes(
        _story.driveFileId,
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
      final dir = await getApplicationDocumentsDirectory();

      // Xác định đuôi file dựa trên dữ liệu thực tế của bytes (magic bytes)
      // Mặc định thử epub, nếu không nhận ra thì dùng txt
      String ext = 'epub';
      if (bytes.length >= 4) {
        // PDF magic: %PDF = 0x25 0x50 0x44 0x46
        if (bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46) {
          ext = 'pdf';
          // ZIP/EPUB magic: PK = 0x50 0x4B
        } else if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
          ext = 'epub';
        } else {
          ext = 'txt';
        }
      }

      // Tên file an toàn (xóa ký tự đặc biệt) + đuôi mở rộng đúng
      final safeTitle = _story.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/$safeTitle.$ext');
      await file.writeAsBytes(bytes);

      // Trích xuất metadata nếu là epub
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  void _startReading() {
    final localPath = _story.localPath;
    if (localPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng tải xuống truyện trước khi đọc.'),
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
    final iconUrl = _story.iconUrl;
    ImageProvider? imageProvider;
    if (iconUrl.isNotEmpty) {
      if (iconUrl.startsWith('http')) {
        imageProvider = NetworkImage(iconUrl);
      } else if (File(iconUrl).existsSync()) {
        imageProvider = FileImage(File(iconUrl));
      }
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        image: imageProvider != null
            ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
            : null,
      ),
      child: imageProvider == null
          ? const Center(
              child: Icon(
                Icons.menu_book_rounded,
                size: 64,
                color: Colors.white38,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ─── Sliver App Bar with blurred cover ───
          SliverAppBar(
            expandedHeight: size.height * 0.38,
            pinned: true,
            stretch: true,
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                  // Blurred bg cover
                  Builder(
                    builder: (_) {
                      final iconUrl = _story.iconUrl;
                      ImageProvider? ip;
                      if (iconUrl.isNotEmpty) {
                        if (iconUrl.startsWith('http')) {
                          ip = NetworkImage(iconUrl);
                        } else if (File(iconUrl).existsSync()) {
                          ip = FileImage(File(iconUrl));
                        }
                      }
                      return ip != null
                          ? Image(image: ip, fit: BoxFit.cover)
                          : Container(color: const Color(0xFF2C2C2C));
                    },
                  ),
                  // Gradient overlay
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
                  // Cover + title at bottom
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
                                _story.localPath.isNotEmpty
                                    ? _story.localPath
                                          .split('.')
                                          .last
                                          .toUpperCase()
                                    : 'EPUB',
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

          // ─── Action buttons ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      // Nếu là truyện từ Drive và CHƯA tải về: chỉ hiện nút "Lưu về máy"
                      if (_story.isFromDrive && _story.localPath.isEmpty) ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isDownloading ? null : _downloadStory,
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 20),
                            label: Text(_downloadButtonLabel),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Đã tải về hoặc là truyện local: hiện nút "Đọc ngay"
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
                                borderRadius: BorderRadius.circular(12),
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
                ],
              ),
            ),
          ),

          // ─── Description Section ───
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

          // ─── Bottom padding ───
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
}
