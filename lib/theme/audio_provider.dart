import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AudioProvider extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  bool _isPaused = false;
  double _speechRate = 0.5;

  String _currentStoryTitle = '';
  String _currentChapterTitle = '';
  String _currentText = '';

  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  bool get isActive => _isSpeaking || _isPaused; // Khi player được bật (đang nói hoặc đang tạm dừng)

  String get storyTitle => _currentStoryTitle;
  String get chapterTitle => _currentChapterTitle;
  double get speechRate => _speechRate;

  AudioProvider() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _isPaused = false;
      notifyListeners();
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      _isPaused = false;
      notifyListeners();
    });
  }

  Future<void> speak(String text, {required String storyTitle, required String chapterTitle}) async {
    _currentStoryTitle = storyTitle;
    _currentChapterTitle = chapterTitle;
    _currentText = text;

    await _tts.stop();
    await _tts.speak(_currentText);
    
    _isSpeaking = true;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_isSpeaking && !_isPaused) {
      await _tts.pause();
      _isPaused = true;
      notifyListeners();
    }
  }

  Future<void> resume() async {
    if (_isPaused && _currentText.isNotEmpty) {
      await _tts.speak(_currentText); // resume by speaking the text again? Wait, flutter_tts resume functionality on Android is slightly different. Let's just use `speak` or `resume`? Actually, pause/speak or pause/resume depends on platform. Wait, if we use pause(), we can resume() or speak(). But on Android, sometimes `pause()` requires synthesizeToFile, or the platform supports it natively now. Let's stick to what was in chapter_reader_screen.dart: it did `await _tts.speak(_chapters[_currentIndex].plain);` to resume.
      _isPaused = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isSpeaking && !_isPaused) {
      await pause();
    } else if (_isPaused) {
      await resume();
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
    _isPaused = false;
    _currentStoryTitle = '';
    _currentChapterTitle = '';
    _currentText = '';
    notifyListeners();
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    await _tts.setSpeechRate(rate);
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
