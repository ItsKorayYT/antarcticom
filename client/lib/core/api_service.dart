import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// Default auth hub URL — used for login/register when no override is provided.
const String kDefaultAuthHubUrl = 'http://antarctis.xyz:8443';

/// HTTP API client for an Antarcticom server instance.
///
/// Each instance targets a single base URL.  Create one for the auth hub
/// and one per community server the user has joined.
class ApiService {
  final String _baseUrl;

  final Dio _dio;
  final void Function()? onUnauthorized;

  ApiService({String? baseUrl, this.onUnauthorized})
      : _baseUrl = _stripTrailingSlash(baseUrl ?? kDefaultAuthHubUrl),
        _dio = Dio(BaseOptions(
          baseUrl: _stripTrailingSlash(baseUrl ?? kDefaultAuthHubUrl),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call();
          }
          return handler.next(error);
        },
      ),
    );
  }

  static String _stripTrailingSlash(String url) {
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Create an ApiService for a specific community server, copying the auth token.
  factory ApiService.forServer(String serverUrl, {String? token}) {
    final api = ApiService(baseUrl: serverUrl);
    if (token != null) {
      api.setToken(token);
    }
    return api;
  }

  /// Set the auth token for subsequent requests.
  void setToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // ─── Instance Discovery ──────────────────────────────────────────────

  /// Fetch instance info from a server. Returns mode, name, version.
  Future<Map<String, dynamic>> getInstanceInfo() async {
    final response = await _dio.get('/api/instance/info');
    return response.data as Map<String, dynamic>;
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

  Future<void> joinServer(String serverId) async {
    await _dio.post('/api/servers/$serverId/join');
  }

  Future<void> leaveServer(String serverId) async {
    await _dio.post('/api/servers/$serverId/leave');
  }

  // ─── Roles ──────────────────────────────────────────────────────────

  Future<List<dynamic>> listRoles(String serverId) async {
    final response = await _dio.get('/api/servers/$serverId/roles');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createRole(
    String serverId,
    String name,
    int permissions,
    int color,
    int position,
  ) async {
    final response = await _dio.post(
      '/api/servers/$serverId/roles',
      data: {
        'name': name,
        'permissions': permissions,
        'color': color,
        'position': position,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRole(
    String serverId,
    String roleId,
    String name,
    int permissions,
    int color,
    int position,
  ) async {
    final response = await _dio.patch(
      '/api/servers/$serverId/roles/$roleId',
      data: {
        'name': name,
        'permissions': permissions,
        'color': color,
        'position': position,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteRole(String serverId, String roleId) async {
    await _dio.delete('/api/servers/$serverId/roles/$roleId');
  }

  Future<void> assignRole(String serverId, String userId, String roleId) async {
    await _dio.put('/api/servers/$serverId/members/$userId/roles/$roleId');
  }

  Future<void> removeRole(String serverId, String userId, String roleId) async {
    await _dio.delete('/api/servers/$serverId/members/$userId/roles/$roleId');
  }

  Future<List<dynamic>> getMembers(String serverId) async {
    final response = await _dio.get('/api/servers/$serverId/members');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getMember(String serverId, String userId) async {
    final response = await _dio.get('/api/servers/$serverId/members/$userId');
    return response.data as Map<String, dynamic>;
  }

  Future<void> kickMember(String serverId, String userId) async {
    await _dio.delete('/api/servers/$serverId/members/$userId');
  }

  Future<void> banMember(String serverId, String userId,
      {String? reason}) async {
    await _dio.post(
      '/api/servers/$serverId/bans/$userId',
      data: {'reason': reason},
    );
  }

  // ─── Channels ───────────────────────────────────────────────────────

  Future<List<dynamic>> listChannels(String serverId) async {
    final response = await _dio.get('/api/servers/$serverId/channels');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createChannel(
      String serverId, String name, String type) async {
    final response = await _dio.post(
      '/api/servers/$serverId/channels',
      data: {'name': name, 'channel_type': type},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteChannel(String serverId, String channelId) async {
    await _dio.delete('/api/servers/$serverId/channels/$channelId');
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

  Future<void> deleteMessage(String channelId, int messageId) async {
    await _dio.delete('/api/channels/$channelId/messages/$messageId');
  }

  // ─── Avatars ─────────────────────────────────────────────────────────

  /// Upload an avatar image file. Returns the new avatar hash.
  Future<String> uploadAvatar(List<int> bytes, String filename) async {
    final formData = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.put(
      '/api/users/@me/avatar',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return (response.data as Map<String, dynamic>)['avatar_hash'] as String;
  }

  /// Build the full avatar URL for a user.
  String avatarUrl(String userId, String hash) =>
      '$_baseUrl/api/avatars/$userId/$hash';

  // ─── Voice ──────────────────────────────────────────────────────────

  /// Join a voice channel. Returns the current participant list.
  Future<List<dynamic>> joinVoiceChannel(String channelId,
      {bool? muted, bool? deafened}) async {
    final response = await _dio.post(
      '/api/voice/$channelId/join',
      data: {
        if (muted != null) 'muted': muted,
        if (deafened != null) 'deafened': deafened,
      },
    );
    return response.data as List<dynamic>;
  }

  /// Leave a voice channel.
  Future<void> leaveVoiceChannel(String channelId) async {
    await _dio.post('/api/voice/$channelId/leave');
  }

  /// Update mute/deafen state in a voice channel.
  Future<void> updateVoiceState(String channelId,
      {bool? muted, bool? deafened}) async {
    await _dio.patch('/api/voice/$channelId/state', data: {
      if (muted != null) 'muted': muted,
      if (deafened != null) 'deafened': deafened,
    });
  }

  /// Get participants in a voice channel.
  Future<List<dynamic>> getVoiceParticipants(String channelId) async {
    final response = await _dio.get('/api/voice/$channelId/participants');
    return response.data as List<dynamic>;
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

/// The primary (auth hub) API service provider.
final Provider<ApiService> apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    onUnauthorized: () {
      // Defer the logout to avoid state modification during build phase
      Future.microtask(() {
        ref.read(authProvider.notifier).logout();
      });
    },
  );
});
