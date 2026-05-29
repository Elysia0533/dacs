class CommunityMessage {
  final String id;
  final String userId;
  final String displayName;
  final String avatarUrl;
  final String text;
  final String createdAt;

  const CommunityMessage({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.text,
    this.avatarUrl = '',
    this.createdAt = '',
  });

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    return CommunityMessage(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      displayName:
          json['displayName']?.toString() ??
          json['display_name']?.toString() ??
          'Ẩn danh',
      avatarUrl:
          json['avatarUrl']?.toString() ?? json['avatar_url']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }
}
