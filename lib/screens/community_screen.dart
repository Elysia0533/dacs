import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/community_message.dart';
import '../services/api_service.dart';
import '../theme/user_provider.dart';

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
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
          : _buildLoginPrompt(context, isDark, textColor),
    );
  }

  Widget _buildLoginPrompt(BuildContext context, bool isDark, Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 64,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Cần đăng nhập backend',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vào tab Cá nhân để đăng ký hoặc đăng nhập, sau đó bạn có thể gửi tin nhắn cộng đồng thật qua backend.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
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
                      'Đang dùng backend: ${ApiService.apiBaseUrl}',
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
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildErrorState(isDark)
              : _messages.isEmpty
              ? _buildEmptyState(isDark)
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

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Không tải được tin nhắn.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadMessages,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Text(
        'Chưa có tin nhắn nào',
        style: TextStyle(
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        ),
      ),
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
