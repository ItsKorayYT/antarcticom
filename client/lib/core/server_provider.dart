import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'connection_manager.dart';

// ─── Server Model ───────────────────────────────────────────────────────

class ServerInfo {
  final String id;
  final String name;
  final String? iconHash;
  final String ownerId;

  /// The base URL of the community host this server lives on.
  /// `null` means the default auth hub / standalone server.
  final String? hostUrl;

  const ServerInfo({
    required this.id,
    required this.name,
    this.iconHash,
    required this.ownerId,
    this.hostUrl,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json, {String? hostUrl}) {
    return ServerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      iconHash: json['icon_hash'] as String?,
      ownerId: json['owner_id'] as String,
      hostUrl: hostUrl,
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
  final ConnectionManager _connMgr;

  ServersNotifier(this._api, this._connMgr) : super(const ServersState());

  /// Fetch servers from the auth hub / standalone AND all community hosts.
  Future<void> fetchServers() async {
    state = const ServersState(isLoading: true);
    try {
      final allServers = <ServerInfo>[];
      final seenServerIds = <String>{};

      // 1. Fetch from primary (auth hub / standalone)
      try {
        final data = await _api.listServers();
        for (final e in data) {
          final server = ServerInfo.fromJson(e as Map<String, dynamic>);
          if (seenServerIds.add(server.id)) {
            allServers.add(server);
          }
        }
      } catch (e) {
        debugPrint('Primary server list failed: $e');
      }

      // 2. Fetch from each connected community host
      for (final host in _connMgr.hosts) {
        // Skip fetching from community host if it's the EXACT same URL as the primary API
        // This avoids duplicating servers in Standalone mode where the host is added manually.
        final uriA = Uri.tryParse(_api.baseUrl);
        final uriB = Uri.tryParse(host.url);
        if (uriA != null &&
            uriB != null &&
            uriA.host == uriB.host &&
            uriA.port == uriB.port) {
          continue;
        }

        final communityApi = _connMgr.getApiForHost(host.url);
        if (communityApi == null) continue;
        try {
          final data = await communityApi.listServers();
          for (final e in data) {
            final server = ServerInfo.fromJson(e as Map<String, dynamic>,
                hostUrl: host.url);
            if (seenServerIds.add(server.id)) {
              allServers.add(server);
            }
          }
        } catch (e) {
          debugPrint('Community host ${host.url} list failed: $e');
        }
      }

      state = ServersState(servers: allServers);
    } catch (e) {
      state = const ServersState(error: 'Failed to load servers');
    }
  }

  /// Create a server on a specific host (or the primary).
  Future<ServerInfo?> createServer(String name, {String? hostUrl}) async {
    try {
      final api =
          hostUrl != null ? _connMgr.getApiForHost(hostUrl) ?? _api : _api;
      final data = await api.createServer(name);
      final server = ServerInfo.fromJson(data, hostUrl: hostUrl);
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
  final connMgr = ref.watch(connectionManagerProvider);
  return ServersNotifier(api, connMgr);
});

/// Currently selected server ID.
final selectedServerIdProvider = StateProvider<String?>((ref) => null);
