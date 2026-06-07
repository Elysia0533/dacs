import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/story.dart';
import '../models/reading_marker.dart';
import '../services/api_service.dart';
import '../theme/reading_settings_provider.dart';

class ChapterReaderScreen extends StatefulWidget {
  final Story story;
  const ChapterReaderScreen({super.key, required this.story});

  @override
  State<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<ChapterReaderScreen> {
  List<_Chapter> _chapters = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isPaused = false;

  bool _showBars = true;
  bool _waitingForExtraSwipeAtEnd = false;
  bool _isAdvancingFromEndSwipe = false;
  bool _isCurrentBookmarked = false;
  double _endOverscrollDistance = 0;

  static const double _chapterEndThreshold = 12;
  static const double _extraSwipeThreshold = 24;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.story.savedChapterIndex;
    _loadEpub();
    _initTts();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('vi-VN');
    await _applyTtsSettings();
    _tts.setCompletionHandler(_handleTtsCompleted);
    _tts.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
        });
      }
    });
  }

  Future<void> _applyTtsSettings() async {
    final settings = context.read<ReadingSettingsProvider>();
    await _tts.setSpeechRate(settings.ttsRate);
    await _tts.setPitch(settings.ttsPitch);
    await _tts.setVolume(settings.ttsVolume);
  }

  Future<void> _handleTtsCompleted() async {
    if (!mounted) return;
    final settings = context.read<ReadingSettingsProvider>();
    if (settings.audioAutoNext && _currentIndex < _chapters.length - 1) {
      await _goToChapter(_currentIndex + 1, smooth: false);
      await _speakCurrentChapter();
      return;
    }
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _isPaused = false;
      });
    }
  }

  Future<void> _loadEpub() async {
    setState(() => _isLoading = true);
    try {
      final bytes = await File(widget.story.localPath).readAsBytes();
      final book = await epubx.EpubReader.readBook(bytes);
      final flat = <_Chapter>[];
      _flattenChapters(book.Chapters ?? [], flat);
      if (flat.isNotEmpty) {
        if (_currentIndex >= flat.length) {
          _currentIndex = flat.length - 1;
        }
        if (_currentIndex < 0) {
          _currentIndex = 0;
        }
        await ApiService.saveChapterProgress(
          widget.story.id,
          _currentIndex,
          totalChapters: flat.length,
        );
      }
      if (!mounted) return;
      setState(() {
        _chapters = flat;
        _isLoading = false;
      });
      await _recordCurrentHistory();
      await _refreshBookmarkState();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _flattenChapters(List<epubx.EpubChapter> list, List<_Chapter> out) {
    for (final ch in list) {
      final html = ch.HtmlContent ?? '';
      final plain = _htmlToPlain(html);
      if (plain.trim().isNotEmpty) {
        out.add(
          _Chapter(
            title: ch.Title ?? 'Chương ${out.length + 1}',
            html: html,
            plain: plain,
          ),
        );
      }
      if (ch.SubChapters != null) {
        _flattenChapters(ch.SubChapters!, out);
      }
    }
  }

  String _htmlToPlain(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
            ScrollDirection.reverse &&
        _showBars) {
      setState(() => _showBars = false);
    } else if (_scrollController.position.userScrollDirection ==
            ScrollDirection.forward &&
        !_showBars) {
      setState(() => _showBars = true);
    }

    final position = _scrollController.position;
    if (!_isAtChapterEnd(position)) {
      _waitingForExtraSwipeAtEnd = false;
      _endOverscrollDistance = 0;
    }
  }

  bool _isAtChapterEnd(ScrollMetrics metrics) {
    return metrics.maxScrollExtent <= 0 ||
        metrics.pixels >= metrics.maxScrollExtent - _chapterEndThreshold;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || _chapters.isEmpty) return false;
    if (_currentIndex >= _chapters.length - 1) {
      _waitingForExtraSwipeAtEnd = false;
      _endOverscrollDistance = 0;
      return false;
    }

    if (notification is ScrollEndNotification) {
      _waitingForExtraSwipeAtEnd = _isAtChapterEnd(notification.metrics);
      _endOverscrollDistance = 0;
      return false;
    }

    if (notification is OverscrollNotification) {
      final isPullingPastChapterEnd =
          notification.overscroll > 0 && _isAtChapterEnd(notification.metrics);

      if (!isPullingPastChapterEnd) {
        return false;
      }

      if (!_waitingForExtraSwipeAtEnd || _isAdvancingFromEndSwipe) {
        return false;
      }

      _endOverscrollDistance += notification.overscroll;
      if (_endOverscrollDistance >= _extraSwipeThreshold) {
        _advanceFromEndSwipe();
      }
    }

    return false;
  }

  Future<void> _advanceFromEndSwipe() async {
    if (_isAdvancingFromEndSwipe) return;
    _isAdvancingFromEndSwipe = true;
    _waitingForExtraSwipeAtEnd = false;
    _endOverscrollDistance = 0;
    try {
      await _goToChapter(_currentIndex + 1, smooth: false);
    } finally {
      _isAdvancingFromEndSwipe = false;
    }
  }

  Future<void> _goToChapter(int index, {bool smooth = true}) async {
    if (index < 0 || index >= _chapters.length || index == _currentIndex) {
      return;
    }
    _waitingForExtraSwipeAtEnd = false;
    _endOverscrollDistance = 0;
    await _stopTts();
    setState(() => _currentIndex = index);
    ApiService.saveChapterProgress(
      widget.story.id,
      index,
      totalChapters: _chapters.length,
    );
    await _recordCurrentHistory();
    await _refreshBookmarkState();
    if (smooth) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _recordCurrentHistory() {
    if (_chapters.isEmpty) return Future.value();
    return ApiService.recordReadingHistory(
      widget.story,
      chapterIndex: _currentIndex,
      chapterTitle: _chapters[_currentIndex].title,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
    );
  }

  Future<void> _refreshBookmarkState() async {
    final bookmarked = await ApiService.isBookmarked(
      widget.story.id,
      chapterIndex: _currentIndex,
    );
    if (!mounted) return;
    setState(() => _isCurrentBookmarked = bookmarked);
  }

  Future<void> _toggleBookmark() async {
    if (_chapters.isEmpty) return;
    final added = await ApiService.toggleBookmark(
      widget.story,
      chapterIndex: _currentIndex,
      chapterTitle: _chapters[_currentIndex].title,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
    );
    if (!mounted) return;
    setState(() => _isCurrentBookmarked = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Đã thêm bookmark' : 'Đã bỏ bookmark'),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _showBookmarks() async {
    final bookmarks = await ApiService.getReadingBookmarks(
      storyId: widget.story.id,
    );
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookmarksSheet(
        bookmarks: bookmarks,
        onSelect: (marker) {
          Navigator.pop(context);
          _goToChapter(marker.chapterIndex);
        },
        onRemove: (marker) async {
          await ApiService.removeBookmark(marker.id);
          await _refreshBookmarkState();
          if (!mounted) return;
          Navigator.pop(context);
          _showBookmarks();
        },
      ),
    );
  }

  Future<void> _toggleTts() async {
    if (_chapters.isEmpty) return;
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      setState(() => _isPaused = true);
    } else if (_isPaused) {
      await _speakCurrentChapter();
    } else {
      await _speakCurrentChapter();
    }
  }

  Future<void> _speakCurrentChapter() async {
    await _applyTtsSettings();
    await _tts.speak(_chapters[_currentIndex].plain);
    if (!mounted) return;
    setState(() {
      _isSpeaking = true;
      _isPaused = false;
    });
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _isPaused = false;
    });
  }

  void _showToc() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SettingsSheet(),
    );
  }

  void _handleReaderMenuAction(String action) {
    switch (action) {
      case 'bookmarks':
        _showBookmarks();
        break;
      case 'settings':
        _showSettings();
        break;
      case 'audio':
        _toggleTts();
        break;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReadingSettingsProvider>();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: settings.bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Lỗi: $_error')));
    }
    if (_chapters.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Không tìm thấy nội dung')),
      );
    }

    final ch = _chapters[_currentIndex];
    final progress = (_currentIndex + 1) / _chapters.length;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: settings.bgColor,
      drawer: _TocDrawer(
        chapters: _chapters,
        currentIndex: _currentIndex,
        onSelect: (i) {
          Navigator.pop(context);
          _goToChapter(i);
        },
      ),
      body: GestureDetector(
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          final dx = details.globalPosition.dx;
          if (dx < width * 0.25) {
            _scaffoldKey.currentState?.openDrawer();
          } else if (dx > width * 0.75) {
            if (_currentIndex < _chapters.length - 1) {
              _goToChapter(_currentIndex + 1);
            }
          } else {
            setState(() => _showBars = !_showBars);
          }
        },
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: _showBars ? 100 : 60),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Text(
                            ch.title,
                            style: settings.bodyTextStyle.copyWith(
                              fontSize: settings.fontSize + 4,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Html(
                            data: ch.html,
                            style: {
                              'body': Style(
                                fontSize: FontSize(settings.fontSize),
                                fontFamily: settings.bodyTextStyle.fontFamily,
                                lineHeight: LineHeight(settings.lineHeight),
                                color: settings.textColor,
                                margin: Margins.zero,
                              ),
                              'p': Style(margin: Margins.only(bottom: 12)),
                              'img': Style(display: Display.none),
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 32, 20, 120),
                          child: _ChapterEndCard(
                            currentTitle: ch.title,
                            nextTitle: _currentIndex < _chapters.length - 1
                                ? _chapters[_currentIndex + 1].title
                                : null,
                            textColor: settings.textColor,
                            accentColor: Theme.of(context).primaryColor,
                            onNext: _currentIndex < _chapters.length - 1
                                ? () => _goToChapter(_currentIndex + 1)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              offset: _showBars ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showBars ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: settings.bgColor.withValues(alpha: 0.98),
                    border: Border(
                      bottom: BorderSide(
                        color: settings.textColor.withValues(alpha: 0.08),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              color: settings.textColor,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.story.title,
                                  style: settings.bodyTextStyle.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ch.title,
                                  style: TextStyle(
                                    color: settings.textColor.withValues(
                                      alpha: 0.58,
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.menu_book_outlined,
                              color: settings.textColor,
                            ),
                            tooltip: 'Mục lục',
                            onPressed: _showToc,
                          ),
                          IconButton(
                            icon: Icon(
                              _isCurrentBookmarked
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: _isCurrentBookmarked
                                  ? Theme.of(context).primaryColor
                                  : settings.textColor,
                            ),
                            tooltip: _isCurrentBookmarked
                                ? 'Bỏ bookmark'
                                : 'Thêm bookmark',
                            onPressed: _toggleBookmark,
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Tác vụ đọc',
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: settings.textColor,
                            ),
                            onSelected: _handleReaderMenuAction,
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'bookmarks',
                                child: _ReaderMenuItem(
                                  icon: Icons.bookmarks_outlined,
                                  label: 'Danh sách bookmark',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'settings',
                                child: _ReaderMenuItem(
                                  icon: Icons.text_fields_rounded,
                                  label: 'Cài đặt chữ',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'audio',
                                child: _ReaderMenuItem(
                                  icon: _isSpeaking && !_isPaused
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline,
                                  label: _isSpeaking && !_isPaused
                                      ? 'Tạm dừng audio'
                                      : 'Đọc bằng audio',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                offset: _showBars ? Offset.zero : const Offset(0, 1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showBars ? 1 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: settings.bgColor.withValues(alpha: 0.98),
                      border: Border(
                        top: BorderSide(
                          color: settings.textColor.withValues(alpha: 0.08),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 2,
                            backgroundColor: settings.textColor.withValues(
                              alpha: 0.10,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    color: settings.textColor.withValues(
                                      alpha: _currentIndex > 0 ? 1 : 0.3,
                                    ),
                                  ),
                                  onPressed: _currentIndex > 0
                                      ? () => _goToChapter(_currentIndex - 1)
                                      : null,
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Chương ${_currentIndex + 1}/${_chapters.length}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: settings.textColor
                                                    .withValues(alpha: 0.68),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${(progress * 100).round()}%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).primaryColor,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                        ),
                                        child: Slider(
                                          value: progress,
                                          onChanged: (v) => _goToChapter(
                                            (v * (_chapters.length - 1))
                                                .round(),
                                          ),
                                          activeColor: Theme.of(
                                            context,
                                          ).primaryColor,
                                          inactiveColor: settings.textColor
                                              .withValues(alpha: 0.2),
                                        ),
                                      ),
                                      Text(
                                        ch.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: settings.textColor.withValues(
                                            alpha: 0.48,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: settings.textColor.withValues(
                                      alpha:
                                          _currentIndex < _chapters.length - 1
                                          ? 1
                                          : 0.3,
                                    ),
                                  ),
                                  onPressed:
                                      _currentIndex < _chapters.length - 1
                                      ? () => _goToChapter(_currentIndex + 1)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          if (_isSpeaking)
                            _ReaderAudioBar(
                              isPaused: _isPaused,
                              textColor: settings.textColor,
                              chapterLabel:
                                  'Chương ${_currentIndex + 1}/${_chapters.length}',
                              onToggle: _toggleTts,
                              onStop: _stopTts,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderAudioBar extends StatelessWidget {
  final bool isPaused;
  final Color textColor;
  final String chapterLabel;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  const _ReaderAudioBar({
    required this.isPaused,
    required this.textColor,
    required this.chapterLabel,
    required this.onToggle,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            IconButton(
              onPressed: onToggle,
              tooltip: isPaused ? 'Tiếp tục nghe' : 'Tạm dừng',
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              color: accent,
            ),
            Expanded(
              child: Text(
                isPaused
                    ? 'Audio tạm dừng - $chapterLabel'
                    : 'Đang nghe - $chapterLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onStop,
              tooltip: 'Dừng audio',
              icon: const Icon(Icons.stop_rounded),
              color: textColor.withValues(alpha: 0.72),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ReaderMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReaderMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _ChapterEndCard extends StatelessWidget {
  final String currentTitle;
  final String? nextTitle;
  final Color textColor;
  final Color accentColor;
  final VoidCallback? onNext;

  const _ChapterEndCard({
    required this.currentTitle,
    required this.nextTitle,
    required this.textColor,
    required this.accentColor,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final hasNext = nextTitle != null && onNext != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasNext
                ? Icons.keyboard_double_arrow_down_rounded
                : Icons.check_circle_outline_rounded,
            color: hasNext ? accentColor : textColor.withValues(alpha: 0.54),
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            hasNext ? 'Hết chương' : 'Đã đọc hết truyện',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasNext) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  nextTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BookmarksSheet extends StatelessWidget {
  final List<ReadingMarker> bookmarks;
  final ValueChanged<ReadingMarker> onSelect;
  final ValueChanged<ReadingMarker> onRemove;

  const _BookmarksSheet({
    required this.bookmarks,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bookmark',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${bookmarks.length}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                child: Column(
                  children: [
                    Icon(
                      Icons.bookmark_border_rounded,
                      size: 44,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chưa có bookmark cho truyện này',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: bookmarks.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: colorScheme.outline.withValues(alpha: 0.12),
                  ),
                  itemBuilder: (context, index) {
                    final marker = bookmarks[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        child: Icon(
                          Icons.bookmark_rounded,
                          color: colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        marker.chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Chương ${marker.chapterIndex + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelect(marker),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Xóa bookmark',
                        onPressed: () => onRemove(marker),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chapter {
  final String title;
  final String html;
  final String plain;
  _Chapter({required this.title, required this.html, required this.plain});
}

class _TocDrawer extends StatefulWidget {
  final List<_Chapter> chapters;
  final int currentIndex;
  final void Function(int) onSelect;
  const _TocDrawer({
    required this.chapters,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  State<_TocDrawer> createState() => _TocDrawerState();
}

class _TocDrawerState extends State<_TocDrawer> {
  late final ScrollController _scrollController;
  final double _itemHeight = 52.0;

  @override
  void initState() {
    super.initState();
    double offset = widget.currentIndex * _itemHeight;
    offset = offset - 200 > 0 ? offset - 200 : 0;
    _scrollController = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final accent = Theme.of(context).primaryColor;

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Mục lục',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.chapters.length} chương',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.chapters.length,
                itemExtent: _itemHeight,
                itemBuilder: (_, i) {
                  final isCur = i == widget.currentIndex;
                  return InkWell(
                    onTap: () => widget.onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: isCur
                            ? accent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        border: Border(
                          left: BorderSide(
                            color: isCur ? accent : Colors.transparent,
                            width: 4,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.chapters[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isCur
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: isCur ? accent : null,
                              ),
                            ),
                          ),
                          if (isCur)
                            Icon(
                              Icons.play_arrow_rounded,
                              color: accent,
                              size: 22,
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
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReadingSettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            'Cỡ chữ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => settings.setFontSize(settings.fontSize - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  label: settings.fontSize.toInt().toString(),
                  onChanged: settings.setFontSize,
                ),
              ),
              IconButton(
                onPressed: () => settings.setFontSize(settings.fontSize + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${settings.fontSize.toInt()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            'Dãn dòng',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    settings.setLineHeight(settings.lineHeight - 0.1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Slider(
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 2.2,
                  divisions: 10,
                  label: settings.lineHeight.toStringAsFixed(1),
                  onChanged: settings.setLineHeight,
                ),
              ),
              IconButton(
                onPressed: () =>
                    settings.setLineHeight(settings.lineHeight + 0.1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  settings.lineHeight.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Phông chữ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReadingSettingsProvider.availableFonts.map((f) {
              final isSelected = settings.fontFamily == f['name'];
              return ChoiceChip(
                label: Text(f['label']!),
                selected: isSelected,
                onSelected: (_) => settings.setFontFamily(f['name']!),
                selectedColor: Theme.of(context).primaryColor,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : textColor,
                  fontSize: 13,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          Text(
            'Màu nền',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ReadingSettingsProvider.bgColors.map((c) {
              final colorVal = c['value'] as int;
              final isSelected = settings.bgColor.toARGB32() == colorVal;
              return GestureDetector(
                onTap: () => settings.setBgColor(colorVal),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: Color(c['textColor'] as int),
                          size: 20,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
