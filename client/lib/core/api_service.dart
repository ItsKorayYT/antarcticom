import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// HTTP API client for the Antarcticom server.
class ApiService {
  static const String _baseUrl = 'http://antarctis.xyz:8443';

  final Dio _dio;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
        ));

  /// Set the auth token for subsequent requests.
  void setToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // ─── Auth ───────────────────────────────────────────────────────────

  /// Login and return {token, user}.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Register and return {token, user}.
  Future<Map<String, dynamic>> register(
    String username,
    String password, {
    String? displayName,
  }) async {
    final response = await _dio.post('/api/auth/register', data: {
      'username': username,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    });
    return response.data as Map<String, dynamic>;
  }

  // ─── Servers ────────────────────────────────────────────────────────

  Future<List<dynamic>> listServers() async {
    final response = await _dio.get('/api/servers');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createServer(String name) async {
    final response = await _dio.post('/api/servers', data: {'name': name});
    return response.data as Map<String, dynamic>;
  }

  // ─── Channels ───────────────────────────────────────────────────────

  Future<List<dynamic>> listChannels(String serverId) async {
    final response = await _dio.get('/api/servers/$serverId/channels');
    return response.data as List<dynamic>;
  }

  // ─── Messages ───────────────────────────────────────────────────────

  Future<List<dynamic>> getMessages(String channelId, {int limit = 50}) async {
    final response = await _dio.get(
      '/api/channels/$channelId/messages',
      queryParameters: {'limit': limit},
    );
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> sendMessage(
      String channelId, String content) async {
    final response = await _dio.post(
      '/api/channels/$channelId/messages',
      data: {'content': content},
    );
    return response.data as Map<String, dynamic>;
  }

  // ─── Getters ────────────────────────────────────────────────────────
  String get baseUrl => _baseUrl;
  String get wsUrl => _baseUrl.replaceFirst('http', 'ws');

  // ─── Health ─────────────────────────────────────────────────────────

  Future<bool> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
