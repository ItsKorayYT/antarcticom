import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

// ─── Server Model ───────────────────────────────────────────────────────

class ServerInfo {
  final String id;
  final String name;
  final String? iconHash;
  final String ownerId;

  const ServerInfo({
    required this.id,
    required this.name,
    this.iconHash,
    required this.ownerId,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      iconHash: json['icon_hash'] as String?,
      ownerId: json['owner_id'] as String,
    );
  }

  /// Short label for the server icon (first 1-3 chars of initials).
  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length == 1) {
      return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
    }
    return words.take(3).map((w) => w[0]).join().toUpperCase();
  }
}

// ─── State ──────────────────────────────────────────────────────────────

class ServersState {
  final bool isLoading;
  final List<ServerInfo> servers;
  final String? error;

  const ServersState({
    this.isLoading = false,
    this.servers = const [],
    this.error,
  });

  ServersState copyWith({
    bool? isLoading,
    List<ServerInfo>? servers,
    String? error,
  }) {
    return ServersState(
      isLoading: isLoading ?? this.isLoading,
      servers: servers ?? this.servers,
      error: error,
    );
  }
}

// ─── Notifier ───────────────────────────────────────────────────────────

class ServersNotifier extends StateNotifier<ServersState> {
  final ApiService _api;

  ServersNotifier(this._api) : super(const ServersState());

  Future<void> fetchServers() async {
    state = const ServersState(isLoading: true);
    try {
      final data = await _api.listServers();
      print('DEBUG: Fetched raw servers: $data');
      final servers = data
          .map((e) => ServerInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      state = ServersState(servers: servers);
      print('DEBUG: Parsed ${servers.length} servers');
    } catch (e, st) {
      print('DEBUG: Failed to fetch servers: $e\n$st');
      state = const ServersState(error: 'Failed to load servers');
    }
  }

  Future<ServerInfo?> createServer(String name) async {
    try {
      final data = await _api.createServer(name);
      final server = ServerInfo.fromJson(data);
      state = state.copyWith(servers: [...state.servers, server]);
      return server;
    } catch (_) {
      return null;
    }
  }
}

// ─── Providers ──────────────────────────────────────────────────────────

final serversProvider =
    StateNotifierProvider<ServersNotifier, ServersState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ServersNotifier(api);
});

/// Currently selected server ID.
final selectedServerIdProvider = StateProvider<String?>((ref) => null);
