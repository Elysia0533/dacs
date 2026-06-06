import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../theme/user_provider.dart';
import '../widgets/app_state_widgets.dart';
import 'story_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Story> _serverStories = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _loadError;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    if (message.contains('GOOGLE_DRIVE_API_KEY')) {
      return 'Chưa cấu hình khóa truy cập Drive. Hãy kiểm tra tham số chạy app trước khi build APK demo.';
    }
    if (message.contains('GOOGLE_DRIVE_FOLDER_URL')) {
      return 'Chưa cấu hình thư mục truyện trên Drive. Hãy kiểm tra link thư mục dùng cho bản demo.';
    }
    return message;
  }

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

    if (!_allGenres.contains(_selectedGenre)) {
      _selectedGenre = 'Tất cả';
    }
  }

  List<Story> get _displayStories {
    return _serverStories.where((s) {
      final genreMatch =
          _selectedGenre == 'Tất cả' ||
          s.genres.any((g) => g.trim() == _selectedGenre);

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
          title: const Text('Quét thư mục Google Drive'),
          content: TextField(
            controller: urlController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText:
                  'Dán một hoặc nhiều link Drive, mỗi link một dòng hoặc cách nhau bằng dấu phẩy',
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Hủy'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              child: const Text('Quét'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                setState(() => _isLoading = true);
                try {
                  final driveStories =
                      await ApiService.fetchDriveStoriesFromFolder(
                        urlController.text,
                      );
                  _serverStories = driveStories;
                  _buildGenreList();
                  _loadError = null;
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã tải ${driveStories.length} truyện từ Google Drive!',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  _serverStories = [];
                  _buildGenreList();
                  _loadError = _formatLoadError(e);
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                  }
                }
                if (mounted) setState(() => _isLoading = false);
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
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = colorScheme.primary;
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 16,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Tên truyện hoặc tác giả...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceContainerHighest
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.menu_book, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Khám phá',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  if (userProvider.isAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        'Admin',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
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
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshServerStories,
              tooltip: 'Làm mới Drive',
            ),
            if (userProvider.isAdmin)
              IconButton(
                icon: const Icon(Icons.add_link),
                onPressed: _importFromDriveDialog,
                tooltip: 'Quét thư mục Drive',
              ),
          ],
        ],
      ),
      body: _isLoading
          ? const AppLoadingState(message: 'Đang tải danh sách truyện...')
          : _loadError != null && _serverStories.isEmpty
          ? _buildLoadErrorState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_allGenres.length > 1)
                  _GenreChipBar(
                    genres: _allGenres,
                    selected: _selectedGenre,
                    accentColor: accentColor,
                    isDark: isDark,
                    onSelect: (genre) => setState(() => _selectedGenre = genre),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: _buildResultHeader(isDark, accentColor),
                ),

                Expanded(child: _buildStoryGrid(isDark)),
              ],
            ),
    );
  }

  Widget _buildLoadErrorState() {
    return AppErrorState(
      icon: Icons.cloud_off_rounded,
      title: 'Không tải được danh sách truyện',
      message: _loadError ?? 'Vui lòng kiểm tra kết nối hoặc cấu hình Drive.',
      actionLabel: 'Thử lại',
      onAction: _loadServerStories,
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
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Không tìm thấy truyện',
        message: _searchQuery.isNotEmpty
            ? 'Thử tìm bằng tên truyện, tác giả hoặc bỏ bớt bộ lọc.'
            : 'Thể loại này hiện chưa có truyện trong danh sách.',
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
