import 'dart:io';
import 'package:flutter/material.dart';
import '../models/story.dart';
import '../services/api_service.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<_StoryWithSize> _items = [];
  bool _isLoading = true;
  int _totalBytes = 0;
  final Set<String> _selectedIds = {};
  bool _selectMode = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final stories = await ApiService.fetchPersonalStories();

    // Chỉ lấy truyện có file local
    final items = <_StoryWithSize>[];
    int total = 0;

    for (final story in stories) {
      int fileSize = 0;
      int coverSize = 0;

      if (story.localPath.isNotEmpty) {
        final f = File(story.localPath);
        if (await f.exists()) fileSize = await f.length();
      }
      if (story.iconUrl.isNotEmpty && !story.iconUrl.startsWith('http')) {
        final f = File(story.iconUrl);
        if (await f.exists()) coverSize = await f.length();
      }

      final totalSize = fileSize + coverSize;
      items.add(_StoryWithSize(
        story: story,
        fileBytes: fileSize,
        coverBytes: coverSize,
        totalBytes: totalSize,
      ));
      total += totalSize;
    }

    // Sắp xếp theo dung lượng giảm dần
    items.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    if (mounted) {
      setState(() {
        _items = items;
        _totalBytes = total;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _deleteStory(_StoryWithSize item) async {
    final confirmed = await _showDeleteConfirm(item.story.title, single: true);
    if (!confirmed) return;

    await _doDelete([item]);
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final selected = _items.where((i) => _selectedIds.contains(i.story.id)).toList();
    final confirmed = await _showDeleteConfirm('${selected.length} truyện', single: false);
    if (!confirmed) return;
    await _doDelete(selected);
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
  }

  Future<void> _deleteAll() async {
    final localItems = _items.where((i) => i.fileBytes > 0).toList();
    if (localItems.isEmpty) return;
    final confirmed = await _showDeleteConfirm('tất cả ${localItems.length} truyện', single: false);
    if (!confirmed) return;
    await _doDelete(localItems);
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
  }

  Future<void> _doDelete(List<_StoryWithSize> items) async {
    for (final item in items) {
      // Xóa file EPUB/PDF/TXT
      if (item.story.localPath.isNotEmpty) {
        try {
          final f = File(item.story.localPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      // Xóa ảnh bìa local (không xóa nếu là URL online)
      if (item.story.iconUrl.isNotEmpty && !item.story.iconUrl.startsWith('http')) {
        try {
          final f = File(item.story.iconUrl);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      // Cập nhật metadata: xóa localPath, isLocal=false
      final updated = item.story.copyWith(
        localPath: '',
        isLocal: false,
        iconUrl: item.story.isFromDrive ? item.story.iconUrl : '',
      );
      await ApiService.updateLocalStory(updated);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa ${items.length} truyện khỏi bộ nhớ.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    await _loadData();
  }

  Future<bool> _showDeleteConfirm(String name, {required bool single}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Xóa file của $name khỏi bộ nhớ thiết bị?\n\nThông tin sách vẫn được giữ trong kệ, chỉ xóa file để giải phóng dung lượng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final localItems = _items.where((i) => i.fileBytes > 0).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selectedIds.clear();
                }),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
        title: _selectMode
            ? Text(
                '${_selectedIds.length} đã chọn',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text(
                'Lưu trữ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
        actions: _selectMode
            ? [
                if (_selectedIds.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteSelected,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Xóa', style: TextStyle(color: Colors.red)),
                  ),
              ]
            : [
                if (localItems.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'select') {
                        setState(() => _selectMode = true);
                      } else if (val == 'deleteAll') {
                        _deleteAll();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'select',
                        child: Row(children: [
                          Icon(Icons.checklist_rounded),
                          SizedBox(width: 10),
                          Text('Chọn nhiều'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'deleteAll',
                        child: Row(children: [
                          Icon(Icons.delete_sweep_rounded, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Xóa tất cả file', style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                  ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? _buildEmpty(isDark)
          : Column(
              children: [
                // ── Header dung lượng ──
                _buildStorageHeader(isDark, primary, localItems),
                // ── Danh sách ──
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) => _buildItem(_items[i], isDark, primary),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStorageHeader(bool isDark, Color primary, List<_StoryWithSize> localItems) {
    final localBytes = localItems.fold<int>(0, (s, i) => s + i.totalBytes);
    final pct = _totalBytes > 0 ? localBytes / _totalBytes : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage_rounded, color: primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Dung lượng sách',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                _formatSize(localBytes),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatChip(
                icon: Icons.download_done_rounded,
                label: '${localItems.length} có file',
                color: primary,
                isDark: isDark,
              ),
              _buildStatChip(
                icon: Icons.library_books_rounded,
                label: '${_items.length} tổng',
                color: Colors.grey,
                isDark: isDark,
              ),
              _buildStatChip(
                icon: Icons.cloud_off_rounded,
                label: '${_items.length - localItems.length} chưa tải',
                color: Colors.orange,
                isDark: isDark,
              ),
            ],
          ),
          if (localItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${localItems.length} sách chiếm ${_formatSize(localBytes)} bộ nhớ',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildItem(_StoryWithSize item, bool isDark, Color primary) {
    final isSelected = _selectedIds.contains(item.story.id);
    final hasFile = item.fileBytes > 0;
    final ext = item.story.localPath.isNotEmpty
        ? item.story.localPath.split('.').last.toUpperCase()
        : '—';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            _selectMode = true;
            _selectedIds.add(item.story.id);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withValues(alpha: 0.12)
                : isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: primary, width: 2)
                : Border.all(color: Colors.transparent),
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: _selectMode
                ? () => setState(() {
                      if (isSelected) {
                        _selectedIds.remove(item.story.id);
                        if (_selectedIds.isEmpty) _selectMode = false;
                      } else {
                        _selectedIds.add(item.story.id);
                      }
                    })
                : null,
            leading: _buildCoverThumbnail(item, isDark, primary, isSelected),
            title: Text(
              item.story.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (hasFile) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ext,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSize(item.totalBytes),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Chưa có file',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                    if (item.story.savedChapterIndex > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.bookmark_rounded, size: 12, color: primary),
                      Text(
                        ' Ch.${item.story.savedChapterIndex}',
                        style: TextStyle(fontSize: 12, color: primary),
                      ),
                    ],
                  ],
                ),
                if (item.story.author.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.story.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
            trailing: _selectMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => setState(() {
                      if (isSelected) {
                        _selectedIds.remove(item.story.id);
                        if (_selectedIds.isEmpty) _selectMode = false;
                      } else {
                        _selectedIds.add(item.story.id);
                      }
                    }),
                  )
                : hasFile
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteStory(item),
                        tooltip: 'Xóa file',
                      )
                    : const Icon(Icons.cloud_off_outlined, color: Colors.orange, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverThumbnail(_StoryWithSize item, bool isDark, Color primary, bool isSelected) {
    final iconUrl = item.story.iconUrl;
    ImageProvider? img;
    if (iconUrl.isNotEmpty) {
      if (iconUrl.startsWith('http')) {
        img = NetworkImage(iconUrl);
      } else if (File(iconUrl).existsSync()) {
        img = FileImage(File(iconUrl));
      }
    }

    return Stack(
      children: [
        Container(
          width: 52,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            image: img != null
                ? DecorationImage(image: img, fit: BoxFit.cover)
                : null,
          ),
          child: img == null
              ? Icon(Icons.menu_book_rounded,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  size: 28)
              : null,
        ),
        if (isSelected)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Kệ sách trống',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thêm sách từ tab Khám phá hoặc nhập file',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _StoryWithSize {
  final Story story;
  final int fileBytes;
  final int coverBytes;
  final int totalBytes;

  const _StoryWithSize({
    required this.story,
    required this.fileBytes,
    required this.coverBytes,
    required this.totalBytes,
  });
}
