import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/story.dart';
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
                          child: _currentIndex < _chapters.length - 1
                              ? FilledButton.icon(
                                  onPressed: () =>
                                      _goToChapter(_currentIndex + 1),
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  label: Text(
                                    'Chương tiếp: ${_chapters[_currentIndex + 1].title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    'Đã đọc hết truyện',
                                    style: TextStyle(
                                      color: settings.textColor.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 16,
                                    ),
                                  ),
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
                    color: settings.bgColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
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
                            child: Text(
                              widget.story.title,
                              style: settings.bodyTextStyle.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.menu_book_outlined,
                              color: settings.textColor,
                            ),
                            onPressed: _showToc,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.text_fields_rounded,
                              color: settings.textColor,
                            ),
                            onPressed: _showSettings,
                          ),
                          IconButton(
                            icon: Icon(
                              _isSpeaking && !_isPaused
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              color: _isSpeaking
                                  ? Theme.of(context).primaryColor
                                  : settings.textColor,
                            ),
                            onPressed: _toggleTts,
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
                    color: settings.bgColor,
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                                        'Chương ${_currentIndex + 1} / ${_chapters.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: settings.textColor.withValues(
                                            alpha: 0.6,
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
