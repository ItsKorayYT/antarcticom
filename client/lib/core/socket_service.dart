import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'api_service.dart';

/// Represents a message event from the WebSocket.
class WsEvent {
  final String type;
  final Map<String, dynamic>? data;

  WsEvent(this.type, this.data);

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    return WsEvent(
      json['type'] as String,
      json['data'] as Map<String, dynamic>?,
    );
  }
}

/// Service to handle WebSocket connection and events.
class SocketService {
  final ApiService _api;
  WebSocketChannel? _channel;
  final _eventController = StreamController<WsEvent>.broadcast();

  String? _token;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  /// Max backoff delay in seconds.
  static const int _maxBackoffSec = 30;

  SocketService(this._api);

  Stream<WsEvent> get events => _eventController.stream;

  bool get isConnected => _channel != null;

  /// Connect to the WebSocket gateway.
  void connect(String token) {
    if (_channel != null || _disposed) return;
    _token = token;
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _token == null) return;
    if (_channel != null) return;

    final wsUrl = _api.wsUrl;
    final uri = Uri.parse('$wsUrl/ws');

    debugPrint('Connecting to WebSocket: $uri');

    try {
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          // Successful data means we're connected – reset backoff
          _reconnectAttempts = 0;
          try {
            final json = jsonDecode(message as String);
            final event = WsEvent.fromJson(json);
            _eventController.add(event);
            debugPrint('WS Event: ${event.type}');
          } catch (e) {
            debugPrint('WS Parse Error: $e');
          }
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _channel = null;
          _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _channel = null;
          _scheduleReconnect();
        },
      );

      _sendIdentify(_token!);
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// Schedule a reconnect with exponential backoff.
  void _scheduleReconnect() {
    if (_disposed || _token == null) return;
    _reconnectTimer?.cancel();

    final delaySec = (_reconnectAttempts < 1) ? 1 : (1 << _reconnectAttempts);
    final capped = delaySec.clamp(1, _maxBackoffSec);
    _reconnectAttempts++;

    debugPrint('WS reconnect in ${capped}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: capped), _doConnect);
  }

  void _sendIdentify(String token) {
    final payload = {
      'type': 'Identify',
      'data': {'token': token}
    };
    send(payload);
  }

  void send(Map<String, dynamic> payload) {
    if (_channel != null) {
      final text = jsonEncode(payload);
      _channel!.sink.add(text);
    }
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _token = null;
    _reconnectAttempts = 0;
    if (_channel != null) {
      _channel!.sink.close(status.goingAway);
      _channel = null;
    }
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final api = ref.watch(apiServiceProvider);
  return SocketService(api);
});
