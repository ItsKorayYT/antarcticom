class User {
  final String id;
  final String username;
  final String displayName;
  final String? avatarHash;

  const User({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarHash,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      avatarHash: json['avatar_hash'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_hash': avatarHash,
    };
  }
}
