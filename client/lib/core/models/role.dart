class Role {
  final String id;
  final String serverId;
  final String name;
  final int permissions;
  final int color;
  final int position;

  const Role({
    required this.id,
    required this.serverId,
    required this.name,
    required this.permissions,
    required this.color,
    required this.position,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as String,
      serverId: json['server_id'] as String,
      name: json['name'] as String,
      permissions: json['permissions'] is int
          ? json['permissions'] as int
          : int.parse(json['permissions'].toString()),
      color: json['color'] as int,
      position: json['position'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'server_id': serverId,
      'name': name,
      'permissions': permissions,
      'color': color,
      'position': position,
    };
  }
}
