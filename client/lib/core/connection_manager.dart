import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'socket_service.dart';

/// Persisted record of a community server the user has joined.
class CommunityHost {
  final String url;
  final String name;

  CommunityHost({required this.url, required this.name});

  Map<String, dynamic> toJson() => {'url': url, 'name': name};

  factory CommunityHost.fromJson(Map<String, dynamic> json) => CommunityHost(
        url: json['url'] as String,
        name: json['name'] as String,
      );

  @override
  bool operator ==(Object other) => other is CommunityHost && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Manages connections (API + WebSocket) to the auth hub and to each
/// community server the user has joined.
class ConnectionManager extends ChangeNotifier {
  /// API client for the auth hub (login / register).
  final ApiService authApi;

  /// Per-community-server API clients, keyed by normalised host URL.
  final Map<String, ApiService> _communityApis = {};

  /// Per-community-server WebSocket services.
  final Map<String, SocketService> _communitySockets = {};

  /// Known community hosts (persisted).
  final List<CommunityHost> _hosts = [];

  List<CommunityHost> get hosts => List.unmodifiable(_hosts);

  String? _token;

  ConnectionManager({ApiService? authApi}) : authApi = authApi ?? ApiService();

  // ─── Lifecycle ──────────────────────────────────────────────────────

  /// Restore saved hosts from SharedPreferences and create connections.
  Future<void> restoreHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('community_hosts') ?? [];
    for (final entry in raw) {
      try {
        final host =
            CommunityHost.fromJson(jsonDecode(entry) as Map<String, dynamic>);
        if (!_hosts.contains(host)) {
          _hosts.add(host);
          _createConnection(host.url);
        }
      } catch (e) {
        debugPrint('Failed to restore host: $e');
      }
    }
    notifyListeners();
  }

  /// Persist hosts to SharedPreferences.
  Future<void> _persistHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _hosts.map((h) => jsonEncode(h.toJson())).toList();
    await prefs.setStringList('community_hosts', encoded);
  }

  // ─── Token ──────────────────────────────────────────────────────────

  /// Set the auth token on the auth hub and all community connections.
  void setToken(String? token) {
    _token = token;
    authApi.setToken(token);
    for (final api in _communityApis.values) {
      api.setToken(token);
    }
  }

  // ─── Add / Remove Servers ────────────────────────────────────────────

  /// Add a community server by URL. Verifies it's reachable first.
  /// Returns the instance info on success, or throws on failure.
  Future<Map<String, dynamic>> addServer(String url) async {
    // Normalise
    var normalised = url.trim();
    if (!normalised.startsWith('http://') &&
        !normalised.startsWith('https://')) {
      normalised = 'http://$normalised';
    }
    while (normalised.endsWith('/')) {
      normalised = normalised.substring(0, normalised.length - 1);
    }

    // Check if already added
    if (_hosts.any((h) => h.url == normalised)) {
      throw Exception('Server already added');
    }

    // Probe instance info
    final probeApi = ApiService(baseUrl: normalised);
    final info = await probeApi.getInstanceInfo();

    final mode = info['mode'] as String? ?? '';
    if (mode != 'community' && mode != 'standalone') {
      throw Exception('Server is in "$mode" mode — not a community server');
    }

    final name = info['name'] as String? ?? normalised;
    final host = CommunityHost(url: normalised, name: name);

    _hosts.add(host);
    _createConnection(normalised);
    await _persistHosts();

    // Auto-join the default server if we have a token
    final defaultServerId = info['default_server_id'] as String?;
    if (defaultServerId != null && _token != null) {
      try {
        final api = _communityApis[normalised];
        if (api != null) {
          await api.joinServer(defaultServerId);
        }
      } catch (e) {
        debugPrint('Failed to auto-join default server: $e');
      }
    }

    notifyListeners();
    return info;
  }

  /// Remove a community server connection.
  Future<void> removeServer(String url) async {
    _hosts.removeWhere((h) => h.url == url);
    _communityApis.remove(url);
    _communitySockets[url]?.disconnect();
    _communitySockets.remove(url);
    await _persistHosts();
    notifyListeners();
  }

  // ─── Connection Helpers ──────────────────────────────────────────────

  void _createConnection(String url) {
    final api = ApiService.forServer(url, token: _token);
    _communityApis[url] = api;

    final socket = SocketService(api);
    _communitySockets[url] = socket;

    // Auto-connect WebSocket if we have a token
    if (_token != null) {
      socket.connect(_token!);
    }
  }

  /// Get the API service for a specific community host URL.
  ApiService? getApiForHost(String hostUrl) => _communityApis[hostUrl];

  /// Get all active community API services.
  List<ApiService> get allCommunityApis => _communityApis.values.toList();

  /// Get the WebSocket service for a specific community host URL.
  SocketService? getSocketForHost(String hostUrl) => _communitySockets[hostUrl];

  /// Connect all community WebSockets (e.g., after login).
  void connectAll(String token) {
    _token = token;
    for (final entry in _communitySockets.entries) {
      entry.value.connect(token);
    }
  }

  /// Disconnect all community WebSockets (e.g., on logout).
  void disconnectAll() {
    _token = null;
    for (final socket in _communitySockets.values) {
      socket.disconnect();
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────

final connectionManagerProvider =
    ChangeNotifierProvider<ConnectionManager>((ref) {
  final authApi = ref.watch(apiServiceProvider);
  return ConnectionManager(authApi: authApi);
});
