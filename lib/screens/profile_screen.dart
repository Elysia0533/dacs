import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import '../theme/user_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
          title: Text(isLogin ? 'Đăng nhập backend' : 'Đăng ký tài khoản'),
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
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
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
                    isLogin
                        ? 'Chưa có tài khoản? Đăng ký'
                        : 'Đã có tài khoản? Đăng nhập',
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
                        setDialogState(
                          () => errorText = 'Vui lòng nhập email và mật khẩu.',
                        );
                        return;
                      }
                      if (!isLogin && displayName.isEmpty) {
                        setDialogState(
                          () => errorText = 'Vui lòng nhập tên hiển thị.',
                        );
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
                              isLogin
                                  ? 'Đăng nhập backend thành công!'
                                  : 'Đăng ký backend thành công!',
                            ),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = e.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
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
        content: const Text('Bạn có chắc muốn đăng xuất khỏi backend?'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final sectionBgColor = isDark
        ? const Color(0xFF1C1C1E)
        : Colors.grey.shade100;
    final textColor = isDark ? Colors.white : Colors.black87;
    final userProvider = context.watch<UserProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 0,
        title: Text(
          'Cá nhân',
          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        ),
        actions: [
          if (userProvider.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
              child: OutlinedButton(
                onPressed: () => _showLogoutDialog(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red, width: 1),
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text(
                  'Đăng xuất',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            userProvider.isLoggedIn
                ? _buildSignedInHeader(
                    context,
                    userProvider,
                    bgColor,
                    textColor,
                  )
                : _buildGuestHeader(context, isDark, textColor),
            const Divider(height: 1),
            _buildSectionHeader('Ứng dụng', sectionBgColor, textColor),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              title: Text(
                'Giao diện',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              trailing: Switch(
                value: isDark,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
            ),
            _buildListTile(Icons.book_outlined, 'Lưu trữ', isDark),
            _buildListTile(
              Icons.bar_chart_rounded,
              'Thống kê đọc sách',
              isDark,
            ),
            _buildListTile(Icons.sync_rounded, 'Đồng bộ backend', isDark),
            _buildSectionHeader('Kết nối', sectionBgColor, textColor),
            _buildListTile(Icons.share_outlined, 'Mời bạn bè sử dụng', isDark),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Phiên bản 1.1.0',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedInHeader(
    BuildContext context,
    UserProvider userProvider,
    Color bgColor,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showLoginDialog(context),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: userProvider.avatarColor,
              child: Text(
                userProvider.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userProvider.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userProvider.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: userProvider.isAdmin
                          ? Colors.orange
                          : Colors.blue.shade300,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    userProvider.isAdmin ? 'Admin backend' : 'Thành viên',
                    style: TextStyle(
                      color: userProvider.isAdmin
                          ? Colors.orange
                          : Colors.blue.shade300,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestHeader(BuildContext context, bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: isDark
                ? Colors.grey.shade800
                : Colors.grey.shade300,
            child: Icon(
              Icons.person,
              size: 50,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khách',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _showLoginDialog(context),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Đăng nhập backend'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color bgColor, Color textColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: bgColor,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: textColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
    );
  }
}
