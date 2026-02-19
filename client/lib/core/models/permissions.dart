class Permissions {
  static const int manageChannels = 1 << 0; // 1
  static const int manageServer = 1 << 1; // 2
  static const int kickMembers = 1 << 2; // 4
  static const int banMembers = 1 << 3; // 8
  static const int sendMessages = 1 << 4; // 16
  static const int administrator = 1 << 5; // 32

  final int value;

  const Permissions(this.value);

  bool has(int permission) {
    return (value & administrator) != 0 || (value & permission) != 0;
  }

  /// Combine multiple permissions
  static int combine(List<int> permissions) {
    return permissions.fold(0, (prev, element) => prev | element);
  }
}
