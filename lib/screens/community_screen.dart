import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/community_message.dart';
import '../services/api_service.dart';
import '../theme/user_provider.dart';
import '../widgets/app_state_widgets.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<CommunityMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  String? _loadedToken;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<UserProvider>();
    if (user.isLoggedIn && _loadedToken != user.token) {
      _loadedToken = user.token;
      _loadMessages();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final messages = await ApiService.fetchCommunityMessages();
      if (!mounted) return;
      setState(() => _messages = messages);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _formatError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final message = await ApiService.sendCommunityMessage(text);
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _messages = [..._messages, message];
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_formatError(e))));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('FIREBASE_') ||
        message.toLowerCase().contains('đồng bộ') ||
        message.toLowerCase().contains('dong bo')) {
      return 'Không tải được cộng đồng đám mây. Bạn vẫn có thể dùng tài khoản và tin nhắn local trên thiết bị.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final appBarColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        title: Text(
          'Cộng đồng',
          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        ),
        actions: [
          if (userProvider.isLoggedIn)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: textColor),
              onPressed: _loadMessages,
              tooltip: 'Làm mới',
            ),
        ],
      ),
      body: userProvider.isLoggedIn
          ? _buildChat(context, isDark, textColor, userProvider)
          : _buildLoginPrompt(),
    );
  }

  Widget _buildLoginPrompt() {
    return const AppEmptyState(
      icon: Icons.forum_outlined,
      title: 'Đăng nhập để tham gia',
      message:
          'Sau khi đăng nhập ở tab Cá nhân, bạn có thể đọc và gửi tin nhắn cộng đồng.',
    );
  }

  Widget _buildChat(
    BuildContext context,
    bool isDark,
    Color textColor,
    UserProvider user,
  ) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: user.avatarColor,
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Sẵn sàng trò chuyện',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const AppLoadingState(message: 'Đang tải tin nhắn...')
              : _error != null
              ? _buildErrorState()
              : _messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isMine = message.userId == user.id;
                    return _MessageBubble(
                      message: message,
                      isMine: isMine,
                      isDark: isDark,
                      mineColor: user.avatarColor,
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  tooltip: 'Gửi',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return AppErrorState(
      icon: Icons.cloud_off_rounded,
      title: 'Không tải được cộng đồng',
      message: _error ?? 'Không tải được tin nhắn. Vui lòng thử lại.',
      actionLabel: 'Thử lại',
      onAction: _loadMessages,
    );
  }

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Chưa có tin nhắn',
      message:
          'Hãy bắt đầu cuộc trò chuyện đầu tiên trong cộng đồng đọc truyện.',
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final CommunityMessage message;
  final bool isMine;
  final bool isDark;
  final Color mineColor;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    required this.mineColor,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? mineColor
        : (isDark ? const Color(0xFF242426) : Colors.grey.shade100);
    final textColor = isMine
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.displayName,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
