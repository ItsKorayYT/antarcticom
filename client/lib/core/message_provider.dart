import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'models/user.dart';

// ─── Message Model ──────────────────────────────────────────────────────

class MessageInfo {
  final int id; // snowflake
  final String channelId;
  final String authorId;
  final String content;
  final String createdAt;
  final String? editedAt;
  final bool isDeleted;
  final User? author;

  const MessageInfo({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.editedAt,
    this.isDeleted = false,
    this.author,
  });

  factory MessageInfo.fromJson(Map<String, dynamic> json) {
    return MessageInfo(
      id: json['id'] as int,
      channelId: json['channel_id'] as String,
      authorId: json['author_id'] as String,
      content: json['content'] as String,
      createdAt: json['created_at'] as String,
      editedAt: json['edited_at'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      author: json['author'] != null
          ? User.fromJson(json['author'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Format the timestamp for display.
  String get formattedTime {
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays == 0) {
        return 'Today at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return 'Yesterday at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
    } catch (_) {
      return createdAt;
    }
  }

  MessageInfo copyWith({
    String? content,
    String? editedAt,
    bool? isDeleted,
  }) {
    return MessageInfo(
      id: id,
      channelId: channelId,
      authorId: authorId,
      content: content ?? this.content,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      author: author,
    );
  }
}

// ─── State ──────────────────────────────────────────────────────────────

class MessagesState {
  final bool isLoading;
  final List<MessageInfo> messages;
  final String? error;

  const MessagesState({
    this.isLoading = false,
    this.messages = const [],
    this.error,
  });
}

// ─── Notifier ───────────────────────────────────────────────────────────

class MessagesNotifier extends StateNotifier<MessagesState> {
  final ApiService _api;
  final SocketService _socket;
  String? _currentChannelId;

  MessagesNotifier(this._api, this._socket) : super(const MessagesState()) {
    _socket.events.listen(_handleEvent);
  }

  Future<void> fetchMessages(String channelId) async {
    _currentChannelId = channelId;
    state = const MessagesState(isLoading: true);
    try {
      final data = await _api.getMessages(channelId);
      final messages = data
          .map((e) => MessageInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      // API returns newest first — reverse for display (oldest at top)
      state = MessagesState(messages: messages.reversed.toList());
    } catch (_) {
      state = const MessagesState(error: 'Failed to load messages');
    }
  }

  Future<bool> sendMessage(String channelId, String content) async {
    try {
      // Optimistic update could go here, but let's wait for WS or API response
      final data = await _api.sendMessage(channelId, content);

      // If WS is working, we might get the message via WS too.
      // To avoid duplicates, we could check IDs, or just rely on WS if we trust it.
      // But for now, let's append it from API response to be responsive.
      // If WS comes later with same ID, we should deduplicate.

      final msg = MessageInfo.fromJson(data);
      _addMessage(msg);

      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleEvent(WsEvent event) {
    if (event.type == 'MessageCreate' && event.data != null) {
      try {
        final msg = MessageInfo.fromJson(event.data!);
        _addMessage(msg);
      } catch (e) {
        // print('Error parsing message: $e');
      }
    } else if (event.type == 'MessageDelete' && event.data != null) {
      try {
        final messageId = event.data!['message_id'] as int;
        // Instead of removing it completely, we update it as deleted
        _markMessageDeleted(messageId);
      } catch (e) {
        // print('Error processing MessageDelete: $e');
      }
    } else if (event.type == 'UserUpdate' && event.data != null) {
      try {
        final updatedUser =
            User.fromJson(event.data!['user'] as Map<String, dynamic>);

        // Scan the active message list for any sent by this user, and manually re-graft the fresh profile.
        final newMsgs = state.messages.map((m) {
          if (m.authorId == updatedUser.id) {
            return MessageInfo(
              id: m.id,
              channelId: m.channelId,
              authorId: m.authorId,
              content: m.content,
              createdAt: m.createdAt,
              editedAt: m.editedAt,
              isDeleted: m.isDeleted,
              author: updatedUser,
            );
          }
          return m;
        }).toList();

        if (newMsgs != state.messages) {
          state = MessagesState(
              messages: newMsgs,
              isLoading: state.isLoading,
              error: state.error);
        }
      } catch (e) {
        // print('Error processing UserUpdate: $e');
      }
    }
  }

  void _addMessage(MessageInfo msg) {
    if (_currentChannelId != msg.channelId) return;

    // Deduplicate
    if (state.messages.any((m) => m.id == msg.id)) return;

    state = MessagesState(messages: [...state.messages, msg]);
  }

  void _markMessageDeleted(int messageId) {
    state = MessagesState(
      messages: state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(isDeleted: true, content: '');
        }
        return m;
      }).toList(),
      isLoading: state.isLoading,
      error: state.error,
    );
  }

  Future<bool> deleteMessage(String channelId, int messageId) async {
    try {
      await _api.deleteMessage(channelId, messageId);
      // The socket event will trigger the actual removal
      return true;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    _currentChannelId = null;
    state = const MessagesState();
  }
}

// ─── Providers ──────────────────────────────────────────────────────────

final messagesProvider =
    StateNotifierProvider<MessagesNotifier, MessagesState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final socket = ref.watch(socketServiceProvider);
  return MessagesNotifier(api, socket);
});
