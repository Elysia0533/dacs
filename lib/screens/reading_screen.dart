import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/story.dart';
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

  // Scroll
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isPaused = false;
  final double _ttsRate = 0.5;

  @override
  void initState() {
    super.initState();
    _initTts();
    _restoreScrollPosition();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(_ttsRate);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() { _isSpeaking = false; _isPaused = false; });
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() { _isSpeaking = false; _isPaused = false; });
    });
  }

  Future<void> _restoreScrollPosition() async {
    final offset = await ApiService.getScrollOffset(widget.story.id);
    if (offset > 0 && _scrollController.hasClients) {
      _scrollController.jumpTo(offset);
    } else {
      // Dùng addPostFrameCallback để đảm bảo scroll đã sẵn sàng
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
    // Lưu vị trí cuộn mỗi khi thay đổi (debounced thông qua setState)
    ApiService.saveScrollOffset(widget.story.id, current);
  }

  String get _currentContent =>
      _showEnglish && widget.story.contentEng.isNotEmpty
          ? widget.story.contentEng
          : widget.story.content;

  // ── TTS ──
  Future<void> _toggleTts() async {
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      setState(() => _isPaused = true);
    } else if (_isPaused) {
      await _tts.speak(_currentContent);
      setState(() => _isPaused = false);
    } else {
      await _tts.speak(_currentContent);
      setState(() { _isSpeaking = true; _isPaused = false; });
    }
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() { _isSpeaking = false; _isPaused = false; });
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

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: GestureDetector(
        onTap: () => setState(() => _showToolbar = !_showToolbar),
        child: Stack(
          children: [
            // ── Nội dung ──
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
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
                  Center(
                    child: Text(
                      '🎉 Hết nội dung',
                      style: TextStyle(
                        color: settings.textColor.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // ── Top AppBar ──
            AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              offset: _showToolbar ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showToolbar ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: settings.bgColor,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_ios_new, color: settings.textColor, size: 20),
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
                          // Nút chuyển ngôn ngữ (nếu có bản dịch)
                          if (widget.story.contentEng.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.language, color: _showEnglish ? Theme.of(context).primaryColor : settings.textColor),
                              tooltip: _showEnglish ? 'Xem tiếng Việt' : 'Xem tiếng Anh',
                              onPressed: () => setState(() => _showEnglish = !_showEnglish),
                            ),
                          IconButton(
                            icon: Icon(Icons.text_fields_rounded, color: settings.textColor),
                            onPressed: _showSettings,
                          ),
                          IconButton(
                            icon: Icon(
                              _isSpeaking && !_isPaused
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              color: _isSpeaking ? Theme.of(context).primaryColor : settings.textColor,
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

            // ── Bottom bar với progress ──
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                offset: _showToolbar ? Offset.zero : const Offset(0, 1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showToolbar ? 1 : 0,
                  child: Container(
                    color: settings.bgColor,
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Row(
                              children: [
                                Text(
                                  '${(_scrollProgress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: settings.textColor.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    ),
                                    child: Slider(
                                      value: _scrollProgress.clamp(0.0, 1.0),
                                      onChanged: (v) {
                                        final max = _scrollController.position.maxScrollExtent;
                                        _scrollController.jumpTo(v * max);
                                      },
                                      activeColor: Theme.of(context).primaryColor,
                                      inactiveColor: settings.textColor.withValues(alpha: 0.2),
                                    ),
                                  ),
                                ),
                                Text(
                                  'Cuộn để đọc',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: settings.textColor.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // TTS controls
                          if (_isSpeaking)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _toggleTts,
                                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                                    label: Text(_isPaused ? 'Tiếp tục' : 'Tạm dừng'),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: _stopTts,
                                    icon: const Icon(Icons.stop),
                                    label: const Text('Dừng'),
                                  ),
                                ],
                              ),
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

// ── Settings Bottom Sheet (dùng lại từ chapter_reader_screen) ──
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
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Font size
          Text('Cỡ chữ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
          Row(
            children: [
              IconButton(onPressed: () => settings.setFontSize(settings.fontSize - 1), icon: const Icon(Icons.remove_circle_outline)),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12, max: 28, divisions: 16,
                  label: settings.fontSize.toInt().toString(),
                  onChanged: settings.setFontSize,
                ),
              ),
              IconButton(onPressed: () => settings.setFontSize(settings.fontSize + 1), icon: const Icon(Icons.add_circle_outline)),
              SizedBox(
                width: 36,
                child: Text('${settings.fontSize.toInt()}', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Line height
          Text('Dãn dòng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
          Row(
            children: [
              IconButton(onPressed: () => settings.setLineHeight(settings.lineHeight - 0.1), icon: const Icon(Icons.remove_circle_outline)),
              Expanded(
                child: Slider(
                  value: settings.lineHeight,
                  min: 1.2, max: 2.2, divisions: 10,
                  label: settings.lineHeight.toStringAsFixed(1),
                  onChanged: settings.setLineHeight,
                ),
              ),
              IconButton(onPressed: () => settings.setLineHeight(settings.lineHeight + 0.1), icon: const Icon(Icons.add_circle_outline)),
              SizedBox(
                width: 36,
                child: Text(settings.lineHeight.toStringAsFixed(1), textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Font family
          Text('Phông chữ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: ReadingSettingsProvider.availableFonts.map((f) {
              final isSelected = settings.fontFamily == f['name'];
              return ChoiceChip(
                label: Text(f['label']!),
                selected: isSelected,
                onSelected: (_) => settings.setFontFamily(f['name']!),
                selectedColor: Theme.of(context).primaryColor,
                labelStyle: TextStyle(color: isSelected ? Colors.white : textColor, fontSize: 13),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Background color
          Text('Màu nền', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ReadingSettingsProvider.bgColors.map((c) {
              final colorVal = c['value'] as int;
              final isSelected = settings.bgColor.toARGB32() == colorVal;
              return GestureDetector(
                onTap: () => settings.setBgColor(colorVal),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected ? Icon(Icons.check, color: Color(c['textColor'] as int), size: 20) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
