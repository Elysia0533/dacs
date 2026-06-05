import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_backend_service.dart';
import '../theme/reading_settings_provider.dart';
import '../theme/theme_provider.dart';
import '../theme/user_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showAccountUnavailableDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đồng bộ chưa sẵn sàng'),
        content: const Text(
          'Bản demo hiện tại chưa bật cấu hình đăng nhập. Bạn vẫn có thể đọc truyện, tải truyện và dùng thư viện offline bình thường.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  String _formatAccountError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    final lower = message.toLowerCase();

    if (lower.contains('permission-denied') ||
        lower.contains('permission_denied') ||
        lower.contains('cloud_firestore')) {
      return 'Tài khoản đã đăng nhập nhưng chưa có quyền đồng bộ dữ liệu. Hãy kiểm tra quyền truy cập cho bản demo.';
    }
    if (lower.contains('network') ||
        lower.contains('unavailable') ||
        lower.contains('timeout')) {
      return 'Không kết nối được dịch vụ đăng nhập. Hãy kiểm tra mạng rồi thử lại.';
    }
    if (lower.contains('firebase')) {
      return 'Dịch vụ đăng nhập chưa sẵn sàng. Hãy kiểm tra cấu hình bản demo.';
    }
    return message;
  }

  void _showLoginDialog(BuildContext context) {
    if (!FirebaseBackendService.isConfigured ||
        !FirebaseBackendService.isInitialized) {
      _showAccountUnavailableDialog(context);
      return;
    }

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
                    'Một số tài khoản được cấp quyền quản trị bởi hệ thống.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                  if (isLogin &&
                      (errorText!.toLowerCase().contains('xac nhan') ||
                          errorText!.toLowerCase().contains('xác nhận'))) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: isSubmitting
                          ? null
                          : () {
                              final email = emailController.text.trim();
                              if (email.isEmpty) return;
                              Navigator.pop(ctx);
                              _showVerifyEmailDialog(
                                context,
                                email: email,
                                colorValue: selectedColor,
                              );
                            },
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('Nhập mã xác nhận'),
                    ),
                  ],
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
                          final result = await provider.registerWithBackend(
                            email: email,
                            password: password,
                            displayName: displayName,
                            colorValue: selectedColor,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          if (result.emailVerificationRequired) {
                            _showVerifyEmailDialog(
                              context,
                              email: email,
                              colorValue: selectedColor,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã gửi link xác nhận. Hãy mở email, bấm link rồi quay lại app.',
                                ),
                              ),
                            );
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đăng ký thành công!'),
                            ),
                          );
                          return;
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isLogin
                                  ? 'Đăng nhập thành công!'
                                  : 'Đăng ký thành công!',
                            ),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = _formatAccountError(e);
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

  void _showVerifyEmailDialog(
    BuildContext context, {
    required String email,
    required int colorValue,
  }) {
    bool isSubmitting = false;
    bool isResending = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Xác nhận email'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đã gửi link xác nhận tới $email. Mở hộp thư, bấm link xác nhận, sau đó quay lại app và bấm nút bên dưới.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mark_email_read_outlined, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nếu không thấy email, hãy kiểm tra Spam/Quảng cáo rồi bấm Gửi lại email.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting || isResending
                  ? null
                  : () => Navigator.pop(ctx),
              child: const Text('Để sau'),
            ),
            TextButton(
              onPressed: isSubmitting || isResending
                  ? null
                  : () async {
                      setDialogState(() {
                        isResending = true;
                        errorText = null;
                      });
                      try {
                        final result = await context
                            .read<UserProvider>()
                            .resendVerificationCode(email);
                        if (!ctx.mounted) return;
                        if (result.alreadyVerified) {
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Email đã xác nhận. Hãy đăng nhập lại.',
                              ),
                            ),
                          );
                          return;
                        }
                        setDialogState(() {
                          isResending = false;
                        });
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã gửi lại email xác nhận.'),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          isResending = false;
                          errorText = _formatAccountError(e);
                        });
                      }
                    },
              child: isResending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Gửi lại email'),
            ),
            FilledButton(
              onPressed: isSubmitting || isResending
                  ? null
                  : () async {
                      setDialogState(() {
                        isSubmitting = true;
                        errorText = null;
                      });
                      try {
                        await context
                            .read<UserProvider>()
                            .verifyEmailWithBackend(
                              email: email,
                              code: '',
                              colorValue: colorValue,
                            );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Xác nhận email thành công!'),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = _formatAccountError(e);
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tôi đã xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi tài khoản này?'),
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
    final colorScheme = Theme.of(context).colorScheme;
    final sectionBgColor = colorScheme.surfaceContainerHighest.withValues(
      alpha: isDark ? 0.46 : 0.72,
    );
    final textColor = colorScheme.onSurface;
    final userProvider = context.watch<UserProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final readingSettings = context.watch<ReadingSettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cá nhân'),
        actions: [
          if (userProvider.isLoggedIn)
            IconButton(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Đăng xuất',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            userProvider.isLoggedIn
                ? _buildSignedInHeader(context, userProvider, textColor)
                : _buildGuestHeader(context, isDark, textColor),
            const Divider(height: 1),
            _buildSectionHeader('Ứng dụng', sectionBgColor, textColor),
            _buildThemeTile(context, isDark, themeProvider),
            _buildSettingsTile(
              context,
              icon: Icons.bookmark_border_rounded,
              title: 'Lưu trữ',
              subtitle: 'EPUB, PDF, TXT offline',
            ),
            _buildSettingsTile(
              context,
              icon: Icons.insights_rounded,
              title: 'Thống kê đọc sách',
              subtitle: 'Tiến trình và lịch sử đọc',
            ),
            _buildSettingsTile(
              context,
              icon: Icons.sync_rounded,
              title: 'Đồng bộ tài khoản',
              subtitle: _syncStatusText(userProvider),
              onTap: userProvider.isLoggedIn
                  ? null
                  : () => _showLoginDialog(context),
              trailing: _buildSyncStatusIcon(context, userProvider),
            ),
            _buildAudioSection(context, readingSettings, sectionBgColor),
            _buildSectionHeader('Kết nối', sectionBgColor, textColor),
            _buildSettingsTile(
              context,
              icon: Icons.share_outlined,
              title: 'Mời bạn bè sử dụng',
              subtitle: 'Chia sẻ vBook',
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Phiên bản 1.1.0',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
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

  String _syncStatusText(UserProvider userProvider) {
    if (!FirebaseBackendService.isConfigured) {
      return 'Chưa bật cho bản demo hiện tại';
    }
    if (!FirebaseBackendService.isInitialized) {
      return 'Đang chờ kết nối';
    }
    if (userProvider.isLoggedIn) {
      return userProvider.email;
    }
    return 'Sẵn sàng đăng nhập và đồng bộ';
  }

  Widget _buildSyncStatusIcon(BuildContext context, UserProvider userProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady =
        FirebaseBackendService.isConfigured &&
        FirebaseBackendService.isInitialized;

    if (userProvider.isLoggedIn && isReady) {
      return Icon(Icons.verified_rounded, color: colorScheme.primary);
    }
    if (isReady) {
      return Icon(
        Icons.login_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 22,
      );
    }
    return Icon(
      Icons.cloud_off_rounded,
      color: colorScheme.onSurfaceVariant,
      size: 22,
    );
  }

  Widget _buildSignedInHeader(
    BuildContext context,
    UserProvider userProvider,
    Color textColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
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
                          ? colorScheme.secondary
                          : colorScheme.primary,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    userProvider.isAdmin ? 'Quản trị viên' : 'Thành viên',
                    style: TextStyle(
                      color: userProvider.isAdmin
                          ? colorScheme.secondary
                          : colorScheme.primary,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                  label: const Text('Đăng nhập'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đồng bộ thư viện và cộng đồng',
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
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor.withValues(alpha: 0.62),
        ),
      ),
    );
  }

  Widget _buildThemeTile(
    BuildContext context,
    bool isDark,
    ThemeProvider themeProvider,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      title: const Text(
        'Giao diện',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(isDark ? 'Tối' : 'Sáng'),
      trailing: Switch(
        value: isDark,
        onChanged: (_) => themeProvider.toggleTheme(),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      onTap: onTap,
      leading: Icon(icon),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildAudioSection(
    BuildContext context,
    ReadingSettingsProvider settings,
    Color sectionBgColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final rateLabel = '${(settings.ttsRate * 100).round()}%';
    final pitchLabel = settings.ttsPitch.toStringAsFixed(1);
    final volumeLabel = '${(settings.ttsVolume * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Audio đọc truyện',
          sectionBgColor,
          colorScheme.onSurface,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 2,
          ),
          leading: const Icon(Icons.graphic_eq_rounded),
          title: const Text(
            'Tự chuyển chương',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Khi nghe hết chương hiện tại'),
          trailing: Switch(
            value: settings.audioAutoNext,
            onChanged: settings.setAudioAutoNext,
          ),
        ),
        _buildAudioSlider(
          context,
          icon: Icons.speed_rounded,
          title: 'Tốc độ',
          valueLabel: rateLabel,
          value: settings.ttsRate,
          min: 0.25,
          max: 0.85,
          divisions: 12,
          onChanged: settings.setTtsRate,
        ),
        _buildAudioSlider(
          context,
          icon: Icons.record_voice_over_rounded,
          title: 'Cao độ',
          valueLabel: pitchLabel,
          value: settings.ttsPitch,
          min: 0.7,
          max: 1.3,
          divisions: 12,
          onChanged: settings.setTtsPitch,
        ),
        _buildAudioSlider(
          context,
          icon: Icons.volume_up_rounded,
          title: 'Âm lượng',
          valueLabel: volumeLabel,
          value: settings.ttsVolume,
          min: 0.2,
          max: 1.0,
          divisions: 8,
          onChanged: settings.setTtsVolume,
        ),
      ],
    );
  }

  Widget _buildAudioSlider(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          SizedBox(
            width: 76,
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
