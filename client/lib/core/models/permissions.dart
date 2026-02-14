class Permissions {
  static const int MANAGE_CHANNELS = 1 << 0; // 1
  static const int MANAGE_SERVER = 1 << 1; // 2
  static const int KICK_MEMBERS = 1 << 2; // 4
  static const int BAN_MEMBERS = 1 << 3; // 8
  static const int SEND_MESSAGES = 1 << 4; // 16
  static const int ADMINISTRATOR = 1 << 5; // 32

  final int value;

  const Permissions(this.value);

  bool has(int permission) {
    return (value & ADMINISTRATOR) != 0 || (value & permission) != 0;
  }

  /// Combine multiple permissions
  static int combine(List<int> permissions) {
    return permissions.fold(0, (prev, element) => prev | element);
  }
}
