class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String avatarUrl;
  final String role;
  final bool emailVerified;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl = '',
    this.role = 'user',
    this.emailVerified = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawEmailVerified = json['emailVerified'] ?? json['email_verified'];
    return AppUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName:
          json['displayName']?.toString() ??
          json['display_name']?.toString() ??
          '',
      avatarUrl:
          json['avatarUrl']?.toString() ?? json['avatar_url']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      emailVerified:
          rawEmailVerified == true ||
          rawEmailVerified == 1 ||
          rawEmailVerified?.toString().toLowerCase() == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'role': role,
      'emailVerified': emailVerified,
    };
  }
}
