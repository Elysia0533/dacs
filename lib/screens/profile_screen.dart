import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import '../theme/user_provider.dart';
import 'reading_stats_screen.dart';
import 'storage_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showLoginDialog(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController();
    int selectedColor = 0xFF4CAF50;
    bool isLogin = true;
    bool isSubmitting = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isLogin ? 'Đăng nhập' : 'Đăng ký tài khoản'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'admin@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                if (!isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị',
                      hintText: 'Nhập tên của bạn...',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Màu avatar',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: UserProvider.avatarColors.map((c) {
                      final val = c['value'] as int;
                      final isSelected = val == selectedColor;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = val),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(val),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Color(val).withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tài khoản đầu tiên trên backend sẽ tự thành admin.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => setDialogState(() {
                            isLogin = !isLogin;
                            errorText = null;
                          }),
                  child: Text(
                    isLogin ? 'Chưa có tài khoản? Đăng ký' : 'Đã có tài khoản? Đăng nhập',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      final password = passwordController.text;
                      final displayName = displayNameController.text.trim();
                      if (email.isEmpty || password.isEmpty) {
                        setDialogState(() => errorText = 'Vui lòng nhập email và mật khẩu.');
                        return;
                      }
                      if (!isLogin && displayName.isEmpty) {
                        setDialogState(() => errorText = 'Vui lòng nhập tên hiển thị.');
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                        errorText = null;
                      });
                      try {
                        final provider = context.read<UserProvider>();
                        if (isLogin) {
                          await provider.loginWithBackend(
                            email: email,
                            password: password,
                            colorValue: selectedColor,
                          );
                        } else {
                          await provider.registerWithBackend(
                            email: email,
                            password: password,
                            displayName: displayName,
                            colorValue: selectedColor,
                          );
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isLogin ? 'Đăng nhập thành công!' : 'Đăng ký thành công!',
                            ),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLogin ? 'Đăng nhập' : 'Đăng ký'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      emailController.dispose();
      passwordController.dispose();
      displayNameController.dispose();
    });
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              context.read<UserProvider>().logout();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userProvider = context.watch<UserProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final primaryColor = Theme.of(context).primaryColor;

    // Màu gradient header
    final headerTop = isDark ? const Color(0xFF1B2A3A) : const Color(0xFF1A73E8);
    final headerBot = isDark ? const Color(0xFF0F1923) : const Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF4F6FA),
      body: CustomScrollView(
        slivers: [
          // ─── Header ───
          SliverToBoxAdapter(
            child: _buildHeader(context, isDark, userProvider, headerTop, headerBot),
          ),

          // ─── Stats row ───
          SliverToBoxAdapter(
            child: _buildStatsRow(context, isDark, userProvider),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ─── Tủ sách section ───
          SliverToBoxAdapter(
            child: _buildShelfSection(context, isDark),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ─── Settings section ───
          SliverToBoxAdapter(
            child: _buildSettingsSection(context, isDark, userProvider, themeProvider, primaryColor),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ─── Kết nối section ───
          SliverToBoxAdapter(
            child: _buildConnectSection(context, isDark),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'VBook • Phiên bản 1.1.0',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    UserProvider user,
    Color top,
    Color bottom,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            children: [
              // Top row: title + logout
              Row(
                children: [
                  const Text(
                    'Cá nhân',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (user.isLoggedIn)
                    GestureDetector(
                      onTap: () => _showLogoutDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.logout_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Đăng xuất',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Avatar + info
              Row(
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: () => _showLoginDialog(context),
                    child: Stack(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 35,
                            backgroundColor: user.isLoggedIn
                                ? user.avatarColor
                                : Colors.grey.shade600,
                            child: user.isLoggedIn
                                ? Text(
                                    user.initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : const Icon(Icons.person, color: Colors.white, size: 36),
                          ),
                        ),
                        // Badge vai trò
                        if (user.isLoggedIn && user.isAdmin)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Name + email + login button
                  Expanded(
                    child: user.isLoggedIn
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user.email,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  user.isAdmin ? '👑 Quản trị viên' : '📚 Thành viên',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Chào bạn!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Đăng nhập để đồng bộ dữ liệu',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _showLoginDialog(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1A73E8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Đăng nhập',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  Widget _buildStatsRow(BuildContext context, bool isDark, UserProvider user) {
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      transform: Matrix4.translationValues(0, -20, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            _buildStatItem(
              icon: Icons.auto_stories_rounded,
              iconColor: const Color(0xFF1A73E8),
              label: 'Đang đọc',
              value: '0',
              isDark: isDark,
            ),
            _buildStatDivider(isDark),
            _buildStatItem(
              icon: Icons.bookmark_rounded,
              iconColor: const Color(0xFFF59E0B),
              label: 'Đánh dấu',
              value: '0',
              isDark: isDark,
            ),
            _buildStatDivider(isDark),
            _buildStatItem(
              icon: Icons.download_done_rounded,
              iconColor: const Color(0xFF10B981),
              label: 'Đã tải',
              value: '0',
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(
      width: 1,
      height: 44,
      color: isDark ? Colors.white10 : Colors.black08,
    );
  }

  // ─── Tủ sách section ──────────────────────────────────────────────────────

  Widget _buildShelfSection(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.library_books_rounded, size: 20, color: Color(0xFF1A73E8)),
                const SizedBox(width: 8),
                Text(
                  'TỦ SÁCH',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                _buildShelfTab('Lịch sử', Icons.history_rounded, true, isDark),
                const SizedBox(width: 10),
                _buildShelfTab('Theo dõi', Icons.favorite_border_rounded, false, isDark),
                const SizedBox(width: 10),
                _buildShelfTab('Tải xuống', Icons.download_rounded, false, isDark),
              ],
            ),
          ),
          // Empty state
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book_outlined, size: 32,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                const SizedBox(width: 10),
                Text(
                  'Chưa có truyện nào',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfTab(String label, IconData icon, bool isActive, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF1A73E8).withValues(alpha: 0.12)
            : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(20),
        border: isActive
            ? Border.all(color: const Color(0xFF1A73E8).withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive
                ? const Color(0xFF1A73E8)
                : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? const Color(0xFF1A73E8)
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Settings section ────────────────────────────────────────────────────

  Widget _buildSettingsSection(
    BuildContext context,
    bool isDark,
    UserProvider user,
    ThemeProvider themeProvider,
    Color primaryColor,
  ) {
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuRow(
            icon: Icons.bar_chart_rounded,
            iconBg: const Color(0xFF3B82F6),
            label: 'Thống kê đọc sách',
            subtitle: 'Xem lịch sử và tiến trình',
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReadingStatsScreen()),
            ),
          ),
          _buildDivider(isDark),
          _buildMenuRow(
            icon: Icons.save_alt_rounded,
            iconBg: const Color(0xFF10B981),
            label: 'Lưu trữ',
            subtitle: 'Quản lý sách đã tải về máy',
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StorageScreen()),
            ),
          ),
          _buildDivider(isDark),
          _buildMenuRow(
            icon: Icons.sync_rounded,
            iconBg: const Color(0xFF8B5CF6),
            label: 'Đăng nhập tài khoản',
            subtitle: user.isLoggedIn ? user.email : 'Chưa đăng nhập',
            isDark: isDark,
            onTap: () => _showLoginDialog(context),
          ),
          _buildDivider(isDark),
          // Toggle dark mode
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.brightness_6_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDark ? 'Chế độ tối' : 'Chế độ sáng',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Chuyển đổi giao diện',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isDark,
                  onChanged: (_) => themeProvider.toggleTheme(),
                  activeColor: const Color(0xFF1A73E8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Kết nối section ─────────────────────────────────────────────────────

  Widget _buildConnectSection(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMenuRow(
            icon: Icons.share_outlined,
            iconBg: const Color(0xFFEC4899),
            label: 'Mời bạn bè sử dụng',
            isDark: isDark,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tính năng chia sẻ sắp ra mắt!')),
            ),
          ),
          _buildDivider(isDark),
          _buildMenuRow(
            icon: Icons.info_outline_rounded,
            iconBg: const Color(0xFF6B7280),
            label: 'Về ứng dụng VBook',
            isDark: isDark,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'VBook',
              applicationVersion: '1.1.0',
              applicationLegalese: '© 2025 VBook Team',
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _buildMenuRow({
    required IconData icon,
    required Color iconBg,
    required String label,
    String? subtitle,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 66,
      endIndent: 16,
      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
    );
  }
}
