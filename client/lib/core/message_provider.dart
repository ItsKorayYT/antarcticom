import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'api_service.dart';

// ─── Message Model ──────────────────────────────────────────────────────

class MessageInfo {
  final int id; // snowflake
  final String channelId;
  final String authorId;
  final String content;
  final String createdAt;
  final String? editedAt;

  const MessageInfo({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.editedAt,
  });

  factory MessageInfo.fromJson(Map<String, dynamic> json) {
    return MessageInfo(
      id: json['id'] as int,
      channelId: json['channel_id'] as String,
      authorId: json['author_id'] as String,
      content: json['content'] as String,
      createdAt: json['created_at'] as String,
      editedAt: json['edited_at'] as String?,
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

  MessagesNotifier(this._api) : super(const MessagesState());

  Future<void> fetchMessages(String channelId) async {
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
      final data = await _api.sendMessage(channelId, content);
      final msg = MessageInfo.fromJson(data);
      state = MessagesState(messages: [...state.messages, msg]);
      return true;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    state = const MessagesState();
  }
}

// ─── Providers ──────────────────────────────────────────────────────────

final messagesProvider =
    StateNotifierProvider<MessagesNotifier, MessagesState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return MessagesNotifier(api);
});
