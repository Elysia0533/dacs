import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/audio_provider.dart';
import '../theme/reading_settings_provider.dart';

class MiniAudioPlayer extends StatelessWidget {
  const MiniAudioPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    if (!audioProvider.isActive) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade100;
    final textColor = isDark ? Colors.white : Colors.black87;
    final accent = Theme.of(context).primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.audiotrack, color: accent),
              ),
              const SizedBox(width: 12),
              
              // Thông tin truyện
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      audioProvider.storyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    if (audioProvider.chapterTitle.isNotEmpty)
                      Text(
                        audioProvider.chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Điều khiển Play/Pause
              IconButton(
                icon: Icon(
                  audioProvider.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 32,
                  color: accent,
                ),
                onPressed: () => audioProvider.togglePlayPause(),
              ),
              
              // Stop
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 24),
                color: textColor.withValues(alpha: 0.5),
                onPressed: () => audioProvider.stop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
