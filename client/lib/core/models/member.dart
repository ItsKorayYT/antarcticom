import 'user.dart';

class Member {
  final String userId;
  final String serverId;
  final String? nickname;
  final DateTime joinedAt;
  final List<String> roles;
  final User? user;
  final String status;

  const Member({
    required this.userId,
    required this.serverId,
    this.nickname,
    required this.joinedAt,
    required this.roles,
    this.user,
    this.status = 'offline',
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      userId: json['user_id'] as String,
      serverId: json['server_id'] as String,
      nickname: json['nickname'] as String?,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      roles:
          (json['roles'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      user: json['user'] != null
          ? User.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      status: json['status'] as String? ?? 'offline',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'server_id': serverId,
      'nickname': nickname,
      'joined_at': joinedAt.toIso8601String(),
      'roles': roles,
      'status': status,
    };
  }

  Member copyWith({
    String? nickname,
    List<String>? roles,
    User? user,
    String? status,
  }) {
    return Member(
      userId: userId,
      serverId: serverId,
      nickname: nickname ?? this.nickname,
      joinedAt: joinedAt,
      roles: roles ?? this.roles,
      user: user ?? this.user,
      status: status ?? this.status,
    );
  }
}
