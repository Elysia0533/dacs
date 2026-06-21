import 'dart:math';
import 'package:flutter/material.dart';
import '../models/story.dart';
import '../services/api_service.dart';

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen>
    with SingleTickerProviderStateMixin {
  List<Story> _stories = [];
  bool _isLoading = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final stories = await ApiService.fetchPersonalStories();
    if (mounted) {
      setState(() {
        _stories = stories;
        _isLoading = false;
      });
      _animCtrl.forward();
    }
  }

  // ── Tính toán thống kê ──
  int get _totalBooks => _stories.length;

  int get _booksInProgress =>
      _stories.where((s) => s.savedChapterIndex > 0 && !_isCompleted(s)).length;

  int get _booksCompleted => _stories.where(_isCompleted).length;

  int get _booksNotStarted =>
      _stories.where((s) => s.savedChapterIndex == 0).length;

  bool _isCompleted(Story s) =>
      s.totalChapters > 1 && s.savedChapterIndex >= s.totalChapters - 1;

  int get _totalChaptersRead =>
      _stories.fold(0, (sum, s) => sum + s.savedChapterIndex);

  double get _overallProgress {
    if (_stories.isEmpty) return 0;
    final total = _stories.fold(0, (sum, s) => sum + s.totalChapters);
    final read = _stories.fold(0, (sum, s) => sum + s.savedChapterIndex);
    if (total == 0) return 0;
    return (read / total).clamp(0.0, 1.0);
  }

  Map<String, int> get _genreMap {
    final map = <String, int>{};
    for (final story in _stories) {
      for (final genre in story.genres) {
        final g = genre.trim();
        if (g.isNotEmpty) map[g] = (map[g] ?? 0) + 1;
      }
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  List<Story> get _topBooks {
    final withProgress = _stories.where((s) => s.savedChapterIndex > 0).toList();
    withProgress.sort((a, b) => b.savedChapterIndex.compareTo(a.savedChapterIndex));
    return withProgress.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        title: const Text(
          'Thống kê đọc sách',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stories.isEmpty
          ? _buildEmptyState(isDark)
          : FadeTransition(
              opacity: _fadeAnim,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Overview cards ──
                  _buildOverviewCards(isDark, primary),
                  const SizedBox(height: 20),

                  // ── Overall progress ──
                  _buildOverallProgressCard(isDark, primary),
                  const SizedBox(height: 20),

                  // ── Status breakdown ──
                  _buildStatusBreakdown(isDark, primary),
                  const SizedBox(height: 20),

                  // ── Top sách đọc nhiều nhất ──
                  if (_topBooks.isNotEmpty) ...[
                    _buildTopBooksCard(isDark, primary),
                    const SizedBox(height: 20),
                  ],

                  // ── Phân tích thể loại ──
                  if (_genreMap.isNotEmpty) ...[
                    _buildGenreCard(isDark, primary),
                    const SizedBox(height: 20),
                  ],

                  // ── Danh sách đang đọc ──
                  _buildInProgressList(isDark, primary),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined, size: 80,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Chưa có sách nào',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thêm sách vào kệ để xem thống kê',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards(bool isDark, Color primary) {
    final cards = [
      _StatData('Tổng sách', '$_totalBooks', Icons.library_books_rounded,
          const Color(0xFF6C63FF)),
      _StatData('Đang đọc', '$_booksInProgress', Icons.menu_book_rounded,
          const Color(0xFF2196F3)),
      _StatData('Hoàn thành', '$_booksCompleted', Icons.check_circle_rounded,
          const Color(0xFF4CAF50)),
      _StatData('Chương đọc', '$_totalChaptersRead', Icons.bookmark_rounded,
          const Color(0xFFFF9800)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards
          .map((d) => _buildStatCard(d, isDark))
          .toList(),
    );
  }

  Widget _buildStatCard(_StatData data, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: data.color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                data.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgressCard(bool isDark, Color primary) {
    final pct = (_overallProgress * 100).toInt();
    return _buildCard(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Tiến trình tổng thể',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _overallProgress,
              minHeight: 12,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$_totalChaptersRead / ${_stories.fold(0, (s, b) => s + b.totalChapters)} chương đã đọc',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown(bool isDark, Color primary) {
    if (_totalBooks == 0) return const SizedBox.shrink();
    final items = [
      _BreakdownItem('Hoàn thành', _booksCompleted, const Color(0xFF4CAF50)),
      _BreakdownItem('Đang đọc', _booksInProgress, const Color(0xFF2196F3)),
      _BreakdownItem('Chưa đọc', _booksNotStarted, Colors.grey),
    ];

    return _buildCard(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_large_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Phân loại sách',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Mini donut chart
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _DonutPainter(
                    values: items.map((i) => i.count.toDouble()).toList(),
                    colors: items.map((i) => i.color).toList(),
                    total: _totalBooks.toDouble(),
                  ),
                  child: Center(
                    child: Text(
                      '$_totalBooks',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: items.map((item) {
                    final pct = _totalBooks > 0
                        ? (item.count / _totalBooks * 100).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade300 : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            '${item.count} ($pct%)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: item.color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopBooksCard(bool isDark, Color primary) {
    return _buildCard(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Sách đọc nhiều nhất',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._topBooks.asMap().entries.map((entry) {
            final i = entry.key;
            final story = entry.value;
            final progress = story.totalChapters > 0
                ? (story.savedChapterIndex / story.totalChapters).clamp(0.0, 1.0)
                : 0.0;
            final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(medals[i], style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ch.${story.savedChapterIndex}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGenreCard(bool isDark, Color primary) {
    final genres = _genreMap.entries.take(6).toList();
    final maxVal = genres.isEmpty ? 1 : genres.first.value;
    final genreColors = [
      const Color(0xFF6C63FF),
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFFE91E63),
      const Color(0xFF009688),
    ];

    return _buildCard(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Thể loại yêu thích',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...genres.asMap().entries.map((entry) {
            final i = entry.key;
            final genre = entry.value;
            final barWidth = maxVal > 0 ? genre.value / maxVal : 0.0;
            final color = genreColors[i % genreColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      genre.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: barWidth,
                        minHeight: 18,
                        backgroundColor: color.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${genre.value}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInProgressList(bool isDark, Color primary) {
    final inProgress = _stories
        .where((s) => s.savedChapterIndex > 0 && !_isCompleted(s))
        .toList()
      ..sort((a, b) => b.savedChapterIndex.compareTo(a.savedChapterIndex));

    if (inProgress.isEmpty) return const SizedBox.shrink();

    return _buildCard(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Đang đọc dở (${inProgress.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...inProgress.map((story) {
            final progress = story.totalChapters > 1
                ? (story.savedChapterIndex / story.totalChapters).clamp(0.0, 1.0)
                : 0.0;
            final pct = (progress * 100).round();

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.menu_book_rounded, color: primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 5,
                                  backgroundColor: isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade200,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$pct%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Chương ${story.savedChapterIndex} / ${story.totalChapters}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCard(bool isDark, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

// ── Data classes ──
class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatData(this.label, this.value, this.icon, this.color);
}

class _BreakdownItem {
  final String label;
  final int count;
  final Color color;
  const _BreakdownItem(this.label, this.count, this.color);
}

// ── Custom Donut Chart Painter ──
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double total;

  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = 18.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -pi / 2;
    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweepAngle = 2 * pi * (values[i] / total);
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle + 0.04, sweepAngle - 0.08, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
