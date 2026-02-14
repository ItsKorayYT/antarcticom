import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'models/user.dart';

// ─── Auth State ─────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final User? user;
  final String? token;
  final String? error;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.user,
    this.token,
    this.error,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    User? user,
    String? token,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      token: token ?? this.token,
      error: error,
    );
  }
}

// ─── Auth Notifier ──────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;
  final SocketService _socket;

  AuthNotifier(this._api, this._socket) : super(const AuthState()) {
    _tryRestoreSession();
  }

  /// Try to restore a saved JWT token on app start.
  Future<void> _tryRestoreSession() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final username = prefs.getString('username');
      final displayName = prefs.getString('display_name');
      final userId = prefs.getString('user_id');

      if (token != null && username != null && userId != null) {
        _api.setToken(token);
        _socket.connect(token);

        state = AuthState(
          isAuthenticated: true,
          token: token,
          user: User(
            id: userId,
            username: username,
            displayName: displayName ?? username,
          ),
        );
      } else {
        state = const AuthState();
      }
    } catch (_) {
      state = const AuthState();
    }
  }

  /// Login with username + password.
  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.login(username, password);
      final token = data['token'] as String;
      final user = User.fromJson(data['user'] as Map<String, dynamic>);

      _api.setToken(token);
      _socket.connect(token);
      await _saveSession(token, user);

      state = AuthState(
        isAuthenticated: true,
        token: token,
        user: user,
      );
      return true;
    } catch (e) {
      final message = _extractError(e);
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  /// Register a new account.
  Future<bool> register(
    String username,
    String password, {
    String? displayName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.register(
        username,
        password,
        displayName: displayName,
      );
      final token = data['token'] as String;
      final user = User.fromJson(data['user'] as Map<String, dynamic>);

      _api.setToken(token);
      _socket.connect(token);
      await _saveSession(token, user);

      state = AuthState(
        isAuthenticated: true,
        token: token,
        user: user,
      );
      return true;
    } catch (e) {
      final message = _extractError(e);
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  /// Log out and clear stored credentials.
  Future<void> logout() async {
    _api.setToken(null);
    _socket.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    state = const AuthState();
  }

  Future<void> _saveSession(String token, User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', user.id);
    await prefs.setString('username', user.username);
    await prefs.setString('display_name', user.displayName);
  }

  String _extractError(dynamic e) {
    if (e is DioException) {
      if (e.response?.data is Map) {
        return (e.response!.data as Map)['message']?.toString() ??
            'Request failed';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return 'Cannot reach server. Check your connection.';
      }
      if (e.response?.statusCode == 401) {
        return 'Invalid username or password';
      }
      if (e.response?.statusCode == 409) {
        return 'Username already taken';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}

// ─── Providers ──────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final socket = ref.watch(socketServiceProvider);
  return AuthNotifier(api, socket);
});
