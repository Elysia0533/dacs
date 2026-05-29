import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'dart:io';
import '../models/story.dart';
import '../services/google_drive_service.dart';
import 'dart:typed_data';

class EpubReaderScreen extends StatefulWidget {
  final Story story;

  const EpubReaderScreen({super.key, required this.story});

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  EpubController? _epubController;
  bool _isLoading = false;
  String? _error;
  String _currentChapterTitle = '';

  @override
  void initState() {
    super.initState();
    _initEpub();
  }

  Future<void> _initEpub() async {
    setState(() => _isLoading = true);
    try {
      if (widget.story.isFromDrive && widget.story.localPath.isEmpty) {
        Uint8List bytes = await GoogleDriveService.downloadFileBytes(
          widget.story.driveFileId,
        );
        _epubController = EpubController(
          document: EpubDocument.openData(bytes),
        );
      } else {
        _epubController = EpubController(
          document: EpubDocument.openFile(File(widget.story.localPath)),
        );
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _epubController?.dispose();
    super.dispose();
  }

  void _showTableOfContents() {
    if (_epubController == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TocBottomSheet(
        controller: _epubController!,
        currentChapterTitle: _currentChapterTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F0E8),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? Colors.white : Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: _epubController == null
            ? Text(
                widget.story.title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : EpubViewActualChapter(
                controller: _epubController!,
                builder: (chapterValue) {
                  final title =
                      chapterValue?.chapter?.Title
                          ?.replaceAll('\n', '')
                          .trim() ??
                      widget.story.title;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _currentChapterTitle = title);
                  });
                  return Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
        actions: [
          if (_epubController != null)
            IconButton(
              icon: Icon(
                Icons.menu_book_outlined,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              tooltip: 'Mục lục',
              onPressed: _showTableOfContents,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Không thể mở file',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : EpubView(
              controller: _epubController!,
              builders: EpubViewBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                chapterDividerBuilder: (chapter) => Divider(
                  color: isDark ? Colors.white10 : Colors.black12,
                  height: 1,
                ),
              ),
            ),
      floatingActionButton: _epubController != null
          ? FloatingActionButton.small(
              onPressed: _showTableOfContents,
              tooltip: 'Mục lục',
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.list, color: Colors.white),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Table of Contents bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _TocBottomSheet extends StatefulWidget {
  final EpubController controller;
  final String currentChapterTitle;

  const _TocBottomSheet({
    required this.controller,
    required this.currentChapterTitle,
  });

  @override
  State<_TocBottomSheet> createState() => _TocBottomSheetState();
}

class _TocBottomSheetState extends State<_TocBottomSheet> {
  final List<_FlatChapter> _flatChapters = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    final book = await widget.controller.document;
    if (!mounted) return;
    setState(() {
      _flatChapters.addAll(_flattenChapters(book.Chapters ?? [], 0));
      _isLoading = false;
    });
  }

  List<_FlatChapter> _flattenChapters(
    List<epubx.EpubChapter> chapters,
    int depth,
  ) {
    final result = <_FlatChapter>[];
    for (final ch in chapters) {
      result.add(
        _FlatChapter(
          title: ch.Title ?? 'Không có tiêu đề',
          contentFileName: ch.ContentFileName ?? '',
          anchor: ch.Anchor,
          depth: depth,
        ),
      );
      if (ch.SubChapters != null && ch.SubChapters!.isNotEmpty) {
        result.addAll(_flattenChapters(ch.SubChapters!, depth + 1));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black45;
    final accentColor = Theme.of(context).primaryColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accentColor,
                            accentColor.withValues(alpha: 0.5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Mục lục',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    if (_flatChapters.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_flatChapters.length} chương',
                          style: TextStyle(
                            fontSize: 12,
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(
                color: isDark ? Colors.white12 : Colors.black12,
                height: 1,
              ),
              // Chapter list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _flatChapters.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book,
                              size: 56,
                              color: subTextColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Không tìm thấy mục lục',
                              style: TextStyle(
                                color: subTextColor,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _flatChapters.length,
                        separatorBuilder: (context, index) => Divider(
                          color: isDark ? Colors.white12 : Colors.black12,
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                        ),
                        itemBuilder: (context, index) {
                          final ch = _flatChapters[index];
                          final isMainChapter = ch.depth == 0;
                          final isCurrent =
                              ch.title == widget.currentChapterTitle;

                          return InkWell(
                            onTap: () {
                              // Navigate using CFI or content file
                              final cfiAnchor = ch.anchor != null
                                  ? '#${ch.anchor}'
                                  : '';
                              widget.controller.gotoEpubCfi(
                                'epubcfi(/6/${ch.contentFileName}$cfiAnchor)',
                              );
                              Navigator.pop(context);
                            },
                            child: Container(
                              color: isCurrent
                                  ? accentColor.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              padding: EdgeInsets.only(
                                left: 20.0 + ch.depth * 16.0,
                                right: 20,
                                top: isMainChapter ? 14 : 10,
                                bottom: isMainChapter ? 14 : 10,
                              ),
                              child: Row(
                                children: [
                                  if (isCurrent)
                                    Container(
                                      width: 3,
                                      height: 20,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      ch.title,
                                      style: TextStyle(
                                        fontSize: isMainChapter ? 15 : 13,
                                        fontWeight: isMainChapter
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isCurrent
                                            ? accentColor
                                            : isMainChapter
                                            ? textColor
                                            : subTextColor,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!isMainChapter)
                                    const SizedBox(width: 4)
                                  else
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: isCurrent
                                          ? accentColor
                                          : subTextColor,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FlatChapter {
  final String title;
  final String contentFileName;
  final String? anchor;
  final int depth;

  _FlatChapter({
    required this.title,
    required this.contentFileName,
    this.anchor,
    required this.depth,
  });
}
