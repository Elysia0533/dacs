import 'package:flutter/material.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/google_drive_service.dart';
import 'story_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Story> _serverStories = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isSearching = false;
  String? _loadError;

  // Tìm kiếm theo tên + tác giả
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Lọc theo thể loại
  String _selectedGenre = 'Tất cả';
  List<String> _allGenres = ['Tất cả'];

  @override
  void initState() {
    super.initState();
    _loadServerStories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadServerStories() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _serverStories = await ApiService.fetchServerStories();
      _buildGenreList();
    } catch (e) {
      _serverStories = [];
      _allGenres = ['Tất cả'];
      _selectedGenre = 'Tất cả';
      _loadError = _formatLoadError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshServerStories() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _serverStories = await ApiService.refreshServerStories();
      _buildGenreList();
      _loadError = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã làm mới danh sách truyện!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi làm mới: $e')));
      }
      _loadError = _formatLoadError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _formatLoadError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('backend')) {
      return '$message\n\nHãy chạy backend bằng: cd backend && python server.py';
    }
    if (message.contains('GOOGLE_DRIVE_API_KEY')) {
      return 'Thiếu Google Drive API key. Hãy chạy app với --dart-define=GOOGLE_DRIVE_API_KEY=your_key.';
    }
    return message;
  }

  /// Thu thập tất cả thể loại duy nhất từ danh sách truyện
  void _buildGenreList() {
    final genreSet = <String>{};
    for (final story in _serverStories) {
      for (final genre in story.genres) {
        final trimmed = genre.trim();
        if (trimmed.isNotEmpty) genreSet.add(trimmed);
      }
    }
    final sorted = genreSet.toList()..sort();
    _allGenres = ['Tất cả', ...sorted];

    // Reset lại nếu thể loại đang chọn không còn tồn tại
    if (!_allGenres.contains(_selectedGenre)) {
      _selectedGenre = 'Tất cả';
    }
  }

  /// Lọc kết hợp: theo thể loại VÀ tìm kiếm text (tên + tác giả)
  List<Story> get _displayStories {
    return _serverStories.where((s) {
      // Lọc thể loại
      final genreMatch =
          _selectedGenre == 'Tất cả' ||
          s.genres.any((g) => g.trim() == _selectedGenre);

      // Tìm kiếm text
      final q = _searchQuery.trim().toLowerCase();
      final textMatch =
          q.isEmpty ||
          s.title.toLowerCase().contains(q) ||
          s.author.toLowerCase().contains(q);

      return genreMatch && textMatch;
    }).toList();
  }

  void _importFromDriveDialog() {
    TextEditingController urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Thêm Thư mục Drive vào Server'),
          content: TextField(
            controller: urlController,
            decoration: const InputDecoration(
              hintText: 'https://drive.google.com/...',
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Hủy'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              child: const Text('Quét & Thêm'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                setState(() => _isLoading = true);
                try {
                  List<Story> driveStories =
                      await GoogleDriveService.fetchStoriesFromFolder(
                        urlController.text,
                      );
                  await ApiService.addServerStories(driveStories);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã thêm ${driveStories.length} truyện từ Drive vào Server!',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                  }
                }
                _loadServerStories();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF4CAF82)
        : const Color(0xFF2E7D52);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Tên truyện hoặc tác giả...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey : Colors.black45,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : GestureDetector(
                onLongPress: () {
                  setState(() => _isAdmin = !_isAdmin);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isAdmin
                            ? 'Đã bật chế độ Admin'
                            : 'Đã tắt chế độ Admin',
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.menu_book, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Khám phá',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching)
            IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
          if (_isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshServerStories,
              tooltip: 'Làm mới danh sách',
            ),
            IconButton(
              icon: const Icon(Icons.add_link),
              onPressed: _importFromDriveDialog,
              tooltip: 'Thêm truyện từ Drive',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _serverStories.isEmpty
          ? _buildLoadErrorState(isDark, accentColor)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hàng chip thể loại ──
                if (_allGenres.length > 1)
                  _GenreChipBar(
                    genres: _allGenres,
                    selected: _selectedGenre,
                    accentColor: accentColor,
                    isDark: isDark,
                    onSelect: (genre) => setState(() => _selectedGenre = genre),
                  ),

                // ── Header kết quả ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _buildResultHeader(isDark, accentColor),
                ),

                // ── Danh sách truyện ──
                Expanded(child: _buildStoryGrid(isDark)),
              ],
            ),
    );
  }

  Widget _buildLoadErrorState(bool isDark, Color accentColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 76,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Không tải được danh sách truyện',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? 'Vui lòng kiểm tra kết nối hoặc cấu hình Drive.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadServerStories,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: FilledButton.styleFrom(backgroundColor: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultHeader(bool isDark, Color accentColor) {
    final stories = _displayStories;
    final isFiltered =
        _searchQuery.trim().isNotEmpty || _selectedGenre != 'Tất cả';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFiltered ? 'Kết quả tìm kiếm' : 'Mới cập nhật',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${stories.length} truyện${_selectedGenre != 'Tất cả' ? ' · $_selectedGenre' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        // Nút xóa bộ lọc nếu đang lọc
        if (isFiltered)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
                _selectedGenre = 'Tất cả';
                _isSearching = false;
              });
            },
            icon: const Icon(Icons.filter_alt_off, size: 16),
            label: const Text('Xóa lọc', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: accentColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
      ],
    );
  }

  Widget _buildStoryGrid(bool isDark) {
    final stories = _displayStories;

    if (stories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 72,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'Không tìm thấy truyện nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Thử tìm với từ khóa khác'
                  : 'Không có truyện thuộc thể loại này',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.54,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _StoryCard(story: story, isDark: isDark);
      },
    );
  }
}

// ── Widget: Hàng chip thể loại ──
class _GenreChipBar extends StatelessWidget {
  final List<String> genres;
  final String selected;
  final Color accentColor;
  final bool isDark;
  final ValueChanged<String> onSelect;

  const _GenreChipBar({
    required this.genres,
    required this.selected,
    required this.accentColor,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: genres.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final genre = genres[index];
          final isSelected = genre == selected;
          return GestureDetector(
            onTap: () => onSelect(genre),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor
                    : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? accentColor
                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                  width: 1,
                ),
              ),
              child: Text(
                genre,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Widget: Card truyện ──
class _StoryCard extends StatelessWidget {
  final Story story;
  final bool isDark;

  const _StoryCard({required this.story, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StoryDetailScreen(story: story)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ảnh bìa
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: story.iconUrl.isNotEmpty
                  ? Image.network(
                      story.iconUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (ctx, err, stack) =>
                          _PlaceholderCover(isDark: isDark),
                    )
                  : _PlaceholderCover(isDark: isDark),
            ),
          ),
          const SizedBox(height: 6),
          // Tên truyện
          Text(
            story.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.25,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // Tên tác giả (nếu có)
          if (story.author.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              story.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  final bool isDark;
  const _PlaceholderCover({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      child: Center(
        child: Icon(
          Icons.book,
          size: 40,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }
}
