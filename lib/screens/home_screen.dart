import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import '../models/story.dart';
import '../models/reading_marker.dart';
import '../services/api_service.dart';
import '../theme/theme_provider.dart';
import '../utils/file_name_utils.dart';
import '../widgets/story_cover_image.dart';
import 'story_detail_screen.dart';
import 'explore_screen.dart';
import 'community_screen.dart';
import 'profile_screen.dart';

enum _LibrarySort { recent, title, progress }

const String _showReadingHistoryKey = 'home_show_reading_history';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget?> _lazyTabs = List<Widget?>.filled(4, null);
  List<Story> _personalStories = [];
  List<Story> _filteredStories = [];
  List<ReadingMarker> _readingHistory = [];
  bool _isLoading = true;

  bool _isGridView = true;
  int _columnCount = 2;
  _LibrarySort _sortMode = _LibrarySort.recent;
  bool _showReadingHistory = false;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Story? _lastReadStory;

  @override
  void initState() {
    super.initState();
    _loadHomePreferences();
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
    _readingHistory = await ApiService.getReadingHistory();
    _readingHistory = _readingHistory
        .where((marker) => _storyForMarker(marker) != null)
        .toList();
    _lastReadStory = await ApiService.getLastReadStory();
    _applySearch();
    setState(() => _isLoading = false);
  }

  Future<void> _loadHomePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showReadingHistory = prefs.getBool(_showReadingHistoryKey) ?? false;
    });
  }

  Future<void> _setReadingHistoryVisible(bool visible) async {
    setState(() => _showReadingHistory = visible);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showReadingHistoryKey, visible);
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
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.history_rounded),
                    title: const Text('Hiển thị lịch sử đọc'),
                    subtitle: const Text('Tắt để Kệ sách gọn hơn'),
                    value: _showReadingHistory,
                    onChanged: (value) {
                      _setReadingHistoryVisible(value);
                      setModalState(() {});
                    },
                  ),
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
      final rawExtension =
          result.files.single.extension ??
          (fileName.contains('.') ? fileName.split('.').last : '');
      final extension = FileNameUtils.normalizeExtension(
        rawExtension,
        fallback: 'txt',
      );
      final titleFromFileName = fileName.replaceAll(
        RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
        '',
      );

      String savedPath = srcPath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final uuid = const Uuid().v4();
        final storageName = FileNameUtils.storageFileName(
          title: titleFromFileName,
          uniqueId: uuid,
          extension: extension,
        );
        final destFile = File('${appDir.path}/$storageName');
        await File(srcPath).copy(destFile.path);
        savedPath = destFile.path;
      } catch (_) {
        savedPath = srcPath;
      }

      String displayTitle = titleFromFileName;
      String coverPath = '';
      String description = '';
      String author = '';
      List<String> genres = [];
      int totalChapters = 1;

      if (extension == 'epub') {
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
        fileType: extension.toLowerCase(),
      );

      if (extension == 'txt') {
        newStory = Story(
          id: newStory.id,
          title: displayTitle,
          content: await File(savedPath).readAsString(),
          localPath: savedPath,
          isLocal: true,
          iconUrl: coverPath,
          fileType: extension.toLowerCase(),
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
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openStory(story),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        height: 112,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171B19) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: double.infinity,
                child: StoryCoverImage(
                  imagePath: story.iconUrl,
                  driveFileId: story.driveFileId,
                  fileType: story.fileType,
                  width: 76,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  backgroundColor: isDark ? Colors.black26 : Colors.white,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_rounded,
                            color: colorScheme.primary,
                            size: 17,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Đọc tiếp',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        story.title,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getProgressLabel(story),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: colorScheme.onSurfaceVariant,
                            size: 14,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShelfDashboard(bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingCount = _personalStories
        .where((story) => story.savedChapterIndex > 0)
        .length;
    final downloadedCount = _personalStories
        .where((story) => story.localPath.isNotEmpty)
        .length;
    final driveCount = _personalStories
        .where((story) => story.isFromDrive)
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kệ sách của bạn',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Truyện đã tải, đang đọc và lịch sử gần đây',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ShelfStatPill(
                  label: 'Tổng',
                  value: '${_personalStories.length}',
                  icon: Icons.library_books_rounded,
                  color: colorScheme.primary,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ShelfStatPill(
                  label: 'Đọc',
                  value: '$readingCount',
                  icon: Icons.timeline_rounded,
                  color: colorScheme.secondary,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ShelfStatPill(
                  label: 'Offline',
                  value: '$downloadedCount',
                  icon: Icons.download_done_rounded,
                  color: const Color(0xFF4E8F7E),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ShelfStatPill(
                  label: 'Drive',
                  value: '$driveCount',
                  icon: Icons.cloud_done_rounded,
                  color: const Color(0xFF5A7DB8),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Story? _storyForMarker(ReadingMarker marker) {
    for (final story in _personalStories) {
      if (story.id == marker.storyId) return story;
    }
    return null;
  }

  Widget _buildHistoryStrip(bool isDark) {
    if (_readingHistory.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    if (!_showReadingHistory) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Material(
          color: isDark
              ? const Color(0xFF151A18)
              : colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setReadingHistoryVisible(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 19,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Lịch sử đọc',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_readingHistory.length}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final markers = _readingHistory.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              const Text(
                'Lịch sử đọc',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _setReadingHistoryVisible(false),
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                label: const Text('Ẩn'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: markers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final marker = markers[index];
              final story = _storyForMarker(marker);
              if (story == null) return const SizedBox.shrink();

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openStory(story),
                child: SizedBox(
                  width: 76,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            StoryCoverImage(
                              imagePath: story.iconUrl,
                              driveFileId: story.driveFileId,
                              fileType: story.fileType,
                              width: double.infinity,
                              height: double.infinity,
                              borderRadius: BorderRadius.circular(8),
                              backgroundColor: isDark
                                  ? const Color(0xFF222624)
                                  : Colors.grey.shade200,
                            ),
                            Positioned(
                              left: 5,
                              right: 5,
                              bottom: 5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    marker.chapterTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        story.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStoryCard(Story story, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressLabel = _getProgressLabel(story);
    final hasProgress = story.savedChapterIndex > 0;

    if (!_isGridView) {
      return GestureDetector(
        onTap: () => _openStory(story),
        onLongPress: () => _confirmDeleteStory(story),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.12),
              ),
            ),
          ),
          child: Row(
            children: [
              StoryCoverImage(
                imagePath: story.iconUrl,
                driveFileId: story.driveFileId,
                fileType: story.fileType,
                width: 52,
                height: 72,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: isDark
                    ? const Color(0xFF222624)
                    : Colors.grey.shade200,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
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
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
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

    return GestureDetector(
      onTap: () => _openStory(story),
      onLongPress: () => _confirmDeleteStory(story),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                StoryCoverImage(
                  imagePath: story.iconUrl,
                  driveFileId: story.driveFileId,
                  fileType: story.fileType,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: isDark
                      ? const Color(0xFF222624)
                      : Colors.grey.shade200,
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      progressLabel,
                      style: TextStyle(
                        color: hasProgress
                            ? const Color(0xFFB8F3D2)
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
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_personalStories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'Thư viện trống',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm EPUB/PDF/TXT hoặc tải truyện từ Khám phá',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => setState(() => _currentIndex = 1),
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Khám phá'),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        _buildShelfDashboard(isDark),
        _buildLastReadBanner(isDark),
        _buildHistoryStrip(isDark),

        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            _readingHistory.isEmpty ? 16 : 10,
            16,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _searchQuery.isEmpty ? 'Thư viện' : 'Kết quả',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_filteredStories.length} truyện',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _isGridView = !_isGridView);
                },
                tooltip: _isGridView ? 'Danh sách' : 'Lưới',
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
              ),
              IconButton(
                onPressed: () => _showSettingsBottomSheet(context),
                tooltip: 'Cài đặt kệ',
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),

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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _columnCount,
                    childAspectRatio: _columnCount == 2 ? 0.62 : 0.58,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
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

  Widget _buildLazyTab(int index) {
    if (index == 0) return _buildLibraryTab();

    if (_currentIndex == index) {
      _lazyTabs[index] ??= switch (index) {
        1 => const ExploreScreen(),
        2 => const CommunityScreen(),
        3 => const ProfileScreen(),
        _ => const SizedBox.shrink(),
      };
    }

    return _lazyTabs[index] ?? const SizedBox.shrink();
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(4, _buildLazyTab),
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
                  : const Text('Kệ sách'),
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
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'Nhập truyện',
                    onPressed: _importStory,
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
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() {
            _currentIndex = i;
            if (i == 0) _loadStories();
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Kệ sách',
          ),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Khám phá'),
          NavigationDestination(icon: Icon(Icons.forum), label: 'Cộng đồng'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Cá nhân'),
        ],
      ),
    );
  }
}

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
          borderRadius: BorderRadius.circular(8),
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

class _ShelfStatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _ShelfStatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B19) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
