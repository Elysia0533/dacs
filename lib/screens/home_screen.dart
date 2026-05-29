import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/story.dart';
import '../services/api_service.dart';
import '../theme/theme_provider.dart';
import 'story_detail_screen.dart';
import 'explore_screen.dart';
import 'community_screen.dart';
import 'profile_screen.dart';

enum _LibrarySort { recent, title, progress }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Story> _personalStories = [];
  List<Story> _filteredStories = [];
  bool _isLoading = true;

  // Kệ sách settings
  bool _isGridView = true;
  int _columnCount = 2;
  _LibrarySort _sortMode = _LibrarySort.recent;

  // Tìm kiếm
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Banner - truyện đọc gần nhất
  Story? _lastReadStory;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    setState(() => _isLoading = true);
    _personalStories = await ApiService.fetchPersonalStories();
    _lastReadStory = await ApiService.getLastReadStory();
    _applySearch();
    setState(() => _isLoading = false);
  }

  void _applySearch() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredStories = List.from(_personalStories);
    } else {
      _filteredStories = _personalStories
          .where(
            (s) =>
                s.title.toLowerCase().contains(query) ||
                s.author.toLowerCase().contains(query) ||
                s.genres.any((genre) => genre.toLowerCase().contains(query)),
          )
          .toList();
    }
    _sortFilteredStories();
  }

  void _sortFilteredStories() {
    switch (_sortMode) {
      case _LibrarySort.recent:
        break;
      case _LibrarySort.title:
        _filteredStories.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case _LibrarySort.progress:
        _filteredStories.sort(
          (a, b) => b.savedChapterIndex.compareTo(a.savedChapterIndex),
        );
        break;
    }
  }

  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // Dùng StatefulBuilder để cập nhật UI bên trong bottom sheet
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Cài đặt kệ sách',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  // Import
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text(
                        'Nhập truyện từ máy (EPUB / PDF / TXT)',
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _importStory();
                      },
                    ),
                  ),
                  const Divider(height: 28),
                  const Text(
                    'Sắp xếp',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<_LibrarySort>(
                    initialValue: _sortMode,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _LibrarySort.recent,
                        child: Text('Mới thêm'),
                      ),
                      DropdownMenuItem(
                        value: _LibrarySort.title,
                        child: Text('Tên A-Z'),
                      ),
                      DropdownMenuItem(
                        value: _LibrarySort.progress,
                        child: Text('Đang đọc trước'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _sortMode = value;
                        _applySearch();
                      });
                      setModalState(() {});
                    },
                  ),
                  const Divider(height: 28),
                  // Kiểu hiển thị
                  const Text(
                    'Kiểu hiển thị',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ViewToggleButton(
                          icon: Icons.grid_view,
                          label: 'Lưới',
                          selected: _isGridView,
                          onTap: () {
                            setModalState(() {});
                            setState(() => _isGridView = true);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ViewToggleButton(
                          icon: Icons.list,
                          label: 'Danh sách',
                          selected: !_isGridView,
                          onTap: () {
                            setModalState(() {});
                            setState(() => _isGridView = false);
                          },
                        ),
                      ),
                    ],
                  ),
                  // Số cột (chỉ hiện khi dạng lưới)
                  if (_isGridView) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Số cột',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _columnCount > 2
                              ? () {
                                  setState(() => _columnCount--);
                                  setModalState(() {});
                                }
                              : null,
                        ),
                        Text(
                          '$_columnCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _columnCount < 4
                              ? () {
                                  setState(() => _columnCount++);
                                  setModalState(() {});
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _importStory() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final srcPath = result.files.single.path!;
      final fileName = result.files.single.name;
      final extension = result.files.single.extension ?? '';

      String savedPath = srcPath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final uuid = const Uuid().v4();
        final destFile = File('${appDir.path}/${uuid}_$fileName');
        await File(srcPath).copy(destFile.path);
        savedPath = destFile.path;
      } catch (_) {
        savedPath = srcPath;
      }

      String displayTitle = fileName.replaceAll(
        RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
        '',
      );
      String coverPath = '';
      String description = '';
      String author = '';
      List<String> genres = [];
      int totalChapters = 1;

      if (extension.toLowerCase() == 'epub') {
        try {
          final metadata = await ApiService.extractEpubMetadata(savedPath);
          if (metadata['title'] != null && metadata['title']!.isNotEmpty) {
            displayTitle = metadata['title']!;
          }
          if (metadata['coverPath'] != null &&
              metadata['coverPath']!.isNotEmpty) {
            coverPath = metadata['coverPath']!;
          }
          if (metadata['description'] != null) {
            description = metadata['description']!;
          }
          final metadataAuthor = metadata['author'];
          if (metadataAuthor is String) {
            author = metadataAuthor;
          }
          final metadataGenres = metadata['genres'];
          if (metadataGenres is List) {
            genres = metadataGenres.map((genre) => genre.toString()).toList();
          }
          final metadataChapterCount = metadata['chapterCount'];
          if (metadataChapterCount is int && metadataChapterCount > 0) {
            totalChapters = metadataChapterCount;
          }
        } catch (e) {
          debugPrint('Không thể đọc metadata EPUB: $e');
        }
      }

      Story newStory = Story(
        id: const Uuid().v4(),
        title: displayTitle,
        description: description,
        author: author,
        genres: genres,
        totalChapters: totalChapters,
        localPath: savedPath,
        isLocal: true,
        iconUrl: coverPath,
      );

      if (extension.toLowerCase() == 'txt') {
        newStory = Story(
          id: newStory.id,
          title: displayTitle,
          content: await File(savedPath).readAsString(),
          localPath: savedPath,
          isLocal: true,
          iconUrl: coverPath,
        );
      }

      await ApiService.importLocalStory(newStory);
      if (mounted) _loadStories();
    }
  }

  Future<void> _openStory(Story story) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryDetailScreen(story: story)),
    );
    _loadStories();
  }

  Future<void> _confirmDeleteStory(Story story) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa truyện'),
        content: Text('Bạn có chắc muốn xóa "${story.title}" khỏi thư viện?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiService.deleteLocalStory(story.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã xóa "${story.title}"')));
        _loadStories();
      }
    }
  }

  // Tính % tiến trình đọc
  String _getProgressLabel(Story story) {
    if (story.totalChapters > 1 && story.savedChapterIndex > 0) {
      final pct = ((story.savedChapterIndex / story.totalChapters) * 100)
          .round();
      return '$pct% đã đọc';
    }
    if (story.savedChapterIndex > 0) {
      return 'Ch.${story.savedChapterIndex + 1}';
    }
    return 'Chưa đọc';
  }

  Widget _buildLastReadBanner(bool isDark) {
    if (_lastReadStory == null) return const SizedBox.shrink();
    final story = _lastReadStory!;

    ImageProvider? coverImage;
    if (story.iconUrl.isNotEmpty) {
      if (story.iconUrl.startsWith('http')) {
        coverImage = NetworkImage(story.iconUrl);
      } else if (File(story.iconUrl).existsSync()) {
        coverImage = FileImage(File(story.iconUrl));
      }
    }

    return GestureDetector(
      onTap: () => _openStory(story),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E3A2F), const Color(0xFF0D2218)]
                : [const Color(0xFF2E7D52), const Color(0xFF1B5E38)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ảnh bìa
            Container(
              margin: const EdgeInsets.all(12),
              width: 65,
              height: 86,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: 0.15),
                image: coverImage != null
                    ? DecorationImage(image: coverImage, fit: BoxFit.cover)
                    : null,
              ),
              child: coverImage == null
                  ? const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white54,
                      size: 32,
                    )
                  : null,
            ),
            // Thông tin
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ĐỌC TIẾP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getProgressLabel(story),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryCard(Story story, bool isDark) {
    ImageProvider? coverImage;
    if (story.iconUrl.isNotEmpty) {
      if (story.iconUrl.startsWith('http')) {
        coverImage = NetworkImage(story.iconUrl);
      } else if (File(story.iconUrl).existsSync()) {
        coverImage = FileImage(File(story.iconUrl));
      }
    }

    final progressLabel = _getProgressLabel(story);
    final hasProgress = story.savedChapterIndex > 0;

    if (!_isGridView) {
      // ── Dạng danh sách ──
      return GestureDetector(
        onTap: () => _openStory(story),
        onLongPress: () => _confirmDeleteStory(story),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 52,
                  height: 72,
                  color: Colors.grey.shade700,
                  child: coverImage != null
                      ? Image(image: coverImage, fit: BoxFit.cover)
                      : const Icon(Icons.book, color: Colors.white38, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: hasProgress
                            ? Theme.of(context).primaryColor
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.red,
                ),
                onPressed: () => _confirmDeleteStory(story),
              ),
            ],
          ),
        ),
      );
    }

    // ── Dạng lưới ──
    return GestureDetector(
      onTap: () => _openStory(story),
      onLongPress: () => _confirmDeleteStory(story),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey.shade800,
                    child: coverImage != null
                        ? Image(
                            image: coverImage,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (ctx, e, st) => const Icon(
                              Icons.book,
                              color: Colors.white38,
                              size: 40,
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.insert_drive_file,
                              size: 50,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                ),
                // Progress badge
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      progressLabel,
                      style: TextStyle(
                        color: hasProgress
                            ? const Color(0xFF90EE90)
                            : Colors.white70,
                        fontSize: 10,
                        fontWeight: hasProgress
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            story.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_personalStories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Thư viện trống',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hãy sang tab Khám phá để tìm truyện!',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _currentIndex = 1),
              child: const Text('Đi đến Khám phá'),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Banner truyện đọc gần nhất
        _buildLastReadBanner(isDark),

        // Thanh tìm kiếm + header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _searchQuery.isEmpty
                      ? 'Thư viện (${_personalStories.length})'
                      : 'Kết quả (${_filteredStories.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Danh sách truyện
        Expanded(
          child: _filteredStories.isEmpty
              ? Center(
                  child: Text(
                    'Không tìm thấy "$_searchQuery"',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : _isGridView
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columnCount,
                    childAspectRatio: _columnCount == 2 ? 0.62 : 0.58,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _filteredStories.length,
                  itemBuilder: (context, index) =>
                      _buildStoryCard(_filteredStories[index], isDark),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _filteredStories.length,
                  itemBuilder: (context, index) =>
                      _buildStoryCard(_filteredStories[index], isDark),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _currentIndex == 0
          ? AppBar(
              title: _isSearching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Tìm trong thư viện...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey : Colors.black54,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _applySearch();
                        });
                      },
                    )
                  : const Text(
                      'Kệ sách',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                        _applySearch();
                      } else {
                        _isSearching = true;
                      }
                    });
                  },
                ),
                if (!_isSearching) ...[
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showSettingsBottomSheet(context),
                  ),
                  IconButton(
                    icon: Icon(
                      themeProvider.themeMode == ThemeMode.dark
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                    onPressed: () => themeProvider.toggleTheme(),
                  ),
                ],
              ],
            )
          : null,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildLibraryTab(),
          const ExploreScreen(),
          const CommunityScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          setState(() {
            _currentIndex = i;
            if (i == 0) _loadStories();
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Kệ sách',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Khám phá'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Cộng đồng'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}

// ── Widget con: nút toggle xem lưới/danh sách ──
class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Theme.of(context).primaryColor : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Theme.of(context).primaryColor : Colors.grey,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
