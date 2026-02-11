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

  SocketService(this._api);

  Stream<WsEvent> get events => _eventController.stream;

  bool get isConnected => _channel != null;

  /// Connect to the WebSocket gateway.
  void connect(String token) {
    if (_channel != null) return;

    final wsUrl = _api.wsUrl; // e.g. ws://host:port
    final uri = Uri.parse('$wsUrl/ws');

    debugPrint('Connecting to WebSocket: $uri');

    try {
      _channel = WebSocketChannel.connect(uri);

      // Listen for messages
      _channel!.stream.listen(
        (message) {
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
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _channel = null;
        },
      );

      // Send Identify payload immediately
      _sendIdentify(token);
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _channel = null;
    }
  }

  void _sendIdentify(String token) {
    final payload = {
      'type': 'Identify', // Capitalized to match server expected enum variant?
      // Server uses serde(tag="type", content="data"). Enum variants are Identify, Heartbeat, etc.
      // Usually serde implies "Identify" string unless rename_all is set.
      // models.rs: enum WsEvent ... Identify { token: String }
      // So type="Identify", data={token: ...}
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
