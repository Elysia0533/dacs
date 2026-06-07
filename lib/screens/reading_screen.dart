import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../models/story.dart';
import '../models/reading_marker.dart';
import '../services/api_service.dart';
import '../theme/reading_settings_provider.dart';

class ReadingScreen extends StatefulWidget {
  final Story story;

  const ReadingScreen({super.key, required this.story});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  bool _showEnglish = false;
  bool _showToolbar = false;
  bool _isBookmarked = false;

  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;
  Timer? _historySaveTimer;

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _restoreScrollPosition();
    _loadBookmarkState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordHistory());
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('vi-VN');
    await _applyTtsSettings();
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _isPaused = false;
        });
      }
    });
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

  Future<void> _restoreScrollPosition() async {
    final offset = await ApiService.getScrollOffset(widget.story.id);
    if (offset > 0 && _scrollController.hasClients) {
      _scrollController.jumpTo(offset);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final savedOffset = await ApiService.getScrollOffset(widget.story.id);
        if (savedOffset > 0 && _scrollController.hasClients) {
          _scrollController.jumpTo(
            savedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  void _onScroll() {
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (max > 0) {
      setState(() => _scrollProgress = current / max);
    }
    ApiService.saveScrollOffset(widget.story.id, current);
    _scheduleHistorySave(current);
  }

  String get _currentContent =>
      _showEnglish && widget.story.contentEng.isNotEmpty
      ? widget.story.contentEng
      : widget.story.content;

  Future<void> _toggleTts() async {
    await _applyTtsSettings();
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      setState(() => _isPaused = true);
    } else if (_isPaused) {
      await _tts.speak(_currentContent);
      setState(() => _isPaused = false);
    } else {
      await _tts.speak(_currentContent);
      setState(() {
        _isSpeaking = true;
        _isPaused = false;
      });
    }
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() {
      _isSpeaking = false;
      _isPaused = false;
    });
  }

  Future<void> _loadBookmarkState() async {
    final bookmarked = await ApiService.isBookmarked(widget.story.id);
    if (!mounted) return;
    setState(() => _isBookmarked = bookmarked);
  }

  void _scheduleHistorySave(double offset) {
    _historySaveTimer?.cancel();
    _historySaveTimer = Timer(
      const Duration(milliseconds: 700),
      () => _recordHistory(offset: offset),
    );
  }

  Future<void> _recordHistory({double? offset}) {
    return ApiService.recordReadingHistory(
      widget.story,
      chapterTitle: 'Vị trí ${(_scrollProgress * 100).round()}%',
      scrollOffset:
          offset ??
          (_scrollController.hasClients ? _scrollController.offset : 0),
    );
  }

  Future<void> _toggleBookmark() async {
    final added = await ApiService.toggleBookmark(
      widget.story,
      chapterTitle: 'Vị trí ${(_scrollProgress * 100).round()}%',
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
    );
    if (!mounted) return;
    setState(() => _isBookmarked = added);
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
      builder: (_) => _TextBookmarksSheet(
        bookmarks: bookmarks,
        onSelect: (marker) {
          Navigator.pop(context);
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(
            marker.scrollOffset.clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
          );
        },
        onRemove: (marker) async {
          await ApiService.removeBookmark(marker.id);
          await _loadBookmarkState();
          if (!mounted) return;
          Navigator.pop(context);
          _showBookmarks();
        },
      ),
    );
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
      case 'language':
        setState(() => _showEnglish = !_showEnglish);
        break;
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
    _historySaveTimer?.cancel();
    if (_scrollController.hasClients) {
      _recordHistory(offset: _scrollController.offset);
    }
    _tts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReadingSettingsProvider>();

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: GestureDetector(
        onTap: () => setState(() => _showToolbar = !_showToolbar),
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 50),
                      Text(
                        widget.story.title,
                        style: settings.bodyTextStyle.copyWith(
                          fontSize: settings.fontSize + 4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(_currentContent, style: settings.bodyTextStyle),
                      const SizedBox(height: 80),
                      _TextEndCard(
                        textColor: settings.textColor,
                        accentColor: Theme.of(context).primaryColor,
                        progress: _scrollProgress,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),

            AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              offset: _showToolbar ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showToolbar ? 1 : 0,
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
                                  _showEnglish ? 'Bản tiếng Anh' : 'Văn bản',
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
                              _isBookmarked
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: _isBookmarked
                                  ? Theme.of(context).primaryColor
                                  : settings.textColor,
                            ),
                            tooltip: _isBookmarked
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
                              if (widget.story.contentEng.isNotEmpty)
                                PopupMenuItem(
                                  value: 'language',
                                  child: _TextReaderMenuItem(
                                    icon: Icons.language,
                                    label: _showEnglish
                                        ? 'Xem tiếng Việt'
                                        : 'Xem tiếng Anh',
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'bookmarks',
                                child: _TextReaderMenuItem(
                                  icon: Icons.bookmarks_outlined,
                                  label: 'Danh sách bookmark',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'settings',
                                child: _TextReaderMenuItem(
                                  icon: Icons.text_fields_rounded,
                                  label: 'Cài đặt chữ',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'audio',
                                child: _TextReaderMenuItem(
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
                offset: _showToolbar ? Offset.zero : const Offset(0, 1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showToolbar ? 1 : 0,
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
                            value: _scrollProgress.clamp(0.0, 1.0),
                            minHeight: 2,
                            backgroundColor: settings.textColor.withValues(
                              alpha: 0.10,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _showEnglish
                                            ? 'Bản tiếng Anh'
                                            : 'Văn bản',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: settings.textColor.withValues(
                                            alpha: 0.68,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${(_scrollProgress * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                  ),
                                  child: Slider(
                                    value: _scrollProgress.clamp(0.0, 1.0),
                                    onChanged: (v) {
                                      final max = _scrollController
                                          .position
                                          .maxScrollExtent;
                                      _scrollController.jumpTo(v * max);
                                    },
                                    activeColor: Theme.of(context).primaryColor,
                                    inactiveColor: settings.textColor
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isSpeaking)
                            _ReaderAudioBar(
                              isPaused: _isPaused,
                              textColor: settings.textColor,
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
  final VoidCallback onToggle;
  final VoidCallback onStop;

  const _ReaderAudioBar({
    required this.isPaused,
    required this.textColor,
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
                isPaused ? 'Audio đang tạm dừng' : 'Đang đọc bằng giọng nói',
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

class _TextReaderMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TextReaderMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _TextEndCard extends StatelessWidget {
  final Color textColor;
  final Color accentColor;
  final double progress;

  const _TextEndCard({
    required this.textColor,
    required this.accentColor,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
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
            Icons.check_circle_outline_rounded,
            color: progress >= 0.98
                ? accentColor
                : textColor.withValues(alpha: 0.54),
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Hết nội dung',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tiến độ ${((progress.clamp(0.0, 1.0)) * 100).round()}%',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextBookmarksSheet extends StatelessWidget {
  final List<ReadingMarker> bookmarks;
  final ValueChanged<ReadingMarker> onSelect;
  final ValueChanged<ReadingMarker> onRemove;

  const _TextBookmarksSheet({
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
      constraints: const BoxConstraints(maxHeight: 380),
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
                        'Vị trí đã lưu',
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
