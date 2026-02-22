import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'socket_service.dart';
import 'connection_manager.dart';
import 'auth_provider.dart';

// ─── Models ─────────────────────────────────────────────────────────────

class VoiceParticipant {
  final String userId;
  final String channelId;
  final bool muted;
  final bool deafened;
  final String? displayName;
  final String? avatarHash;

  const VoiceParticipant({
    required this.userId,
    required this.channelId,
    this.muted = false,
    this.deafened = false,
    this.displayName,
    this.avatarHash,
  });

  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return VoiceParticipant(
      userId: json['user_id'] as String,
      channelId: json['channel_id'] as String,
      muted: json['muted'] as bool? ?? false,
      deafened: json['deafened'] as bool? ?? false,
      displayName: user?['display_name'] as String?,
      avatarHash: user?['avatar_hash'] as String?,
    );
  }
}

// ─── State ──────────────────────────────────────────────────────────────

class VoiceState {
  /// Channel ID the current user is connected to (null = not in voice).
  final String? currentChannelId;

  /// Current user's mute state.
  final bool muted;

  /// Current user's deafen state.
  final bool deafened;

  /// All voice participants across channels: channel_id → list of participants.
  final Map<String, List<VoiceParticipant>> participants;

  const VoiceState({
    this.currentChannelId,
    this.muted = false,
    this.deafened = false,
    this.participants = const {},
  });

  VoiceState copyWith({
    String? currentChannelId,
    bool clearChannel = false,
    bool? muted,
    bool? deafened,
    Map<String, List<VoiceParticipant>>? participants,
  }) {
    return VoiceState(
      currentChannelId:
          clearChannel ? null : (currentChannelId ?? this.currentChannelId),
      muted: muted ?? this.muted,
      deafened: deafened ?? this.deafened,
      participants: participants ?? this.participants,
    );
  }

  /// Get participants for a specific channel.
  List<VoiceParticipant> participantsFor(String channelId) =>
      participants[channelId] ?? const [];
}

// ─── Notifier ───────────────────────────────────────────────────────────

class VoiceNotifier extends StateNotifier<VoiceState> {
  final ApiService _api;
  final SocketService _primarySocket;
  final ConnectionManager _connMgr;
  final String? _currentUserId;
  final List<StreamSubscription> _subs = [];

  VoiceNotifier(
      this._api, this._primarySocket, this._connMgr, this._currentUserId)
      : super(const VoiceState()) {
    // Listen to the primary (auth hub / standalone) socket
    _subs.add(_primarySocket.events.listen(_handleEvent));

    // Also listen to all community server sockets
    for (final host in _connMgr.hosts) {
      final socket = _connMgr.getSocketForHost(host.url);
      if (socket != null && socket != _primarySocket) {
        _subs.add(socket.events.listen(_handleEvent));
      }
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _handleEvent(WsEvent event) {
    if (event.type == 'VoiceStateUpdate' && event.data != null) {
      _handleVoiceUpdate(event.data!);
    }
  }

  /// Handle a VoiceStateUpdate event from the WebSocket.
  void _handleVoiceUpdate(Map<String, dynamic> data) {
    final channelId = data['channel_id'] as String?;
    final userId = data['user_id'] as String?;
    final joined = data['joined'] as bool? ?? false;
    if (channelId == null || userId == null) return;

    final newParticipants =
        Map<String, List<VoiceParticipant>>.from(state.participants);

    if (joined) {
      final user = data['user'] as Map<String, dynamic>?;
      final participant = VoiceParticipant(
        userId: userId,
        channelId: channelId,
        muted: data['muted'] as bool? ?? false,
        deafened: data['deafened'] as bool? ?? false,
        displayName: user?['display_name'] as String?,
        avatarHash: user?['avatar_hash'] as String?,
      );

      final list =
          List<VoiceParticipant>.from(newParticipants[channelId] ?? []);
      list.removeWhere((p) => p.userId == userId);
      list.add(participant);
      newParticipants[channelId] = list;
    } else {
      // Remove participant
      final list =
          List<VoiceParticipant>.from(newParticipants[channelId] ?? []);
      list.removeWhere((p) => p.userId == userId);
      if (list.isEmpty) {
        newParticipants.remove(channelId);
      } else {
        newParticipants[channelId] = list;
      }
    }

    // If the server sent a leave event for the current user (e.g. on WS
    // disconnect), clear our local voice state so the UI doesn't keep
    // showing "Voice Connected".
    final isCurrentUser = _currentUserId != null && userId == _currentUserId;
    if (!joined && isCurrentUser && state.currentChannelId == channelId) {
      state = state.copyWith(
        clearChannel: true,
        muted: false,
        deafened: false,
        participants: newParticipants,
      );
    } else {
      state = state.copyWith(participants: newParticipants);
    }
  }

  /// Join a voice channel (or toggle off if already in the same channel).
  Future<void> joinChannel(String channelId) async {
    if (state.currentChannelId == channelId) {
      await leaveChannel();
      return;
    }

    try {
      final data = await _api.joinVoiceChannel(channelId);
      final participants = data
          .map((e) => VoiceParticipant.fromJson(e as Map<String, dynamic>))
          .toList();

      final newParticipants =
          Map<String, List<VoiceParticipant>>.from(state.participants);
      newParticipants[channelId] = participants;

      state = state.copyWith(
        currentChannelId: channelId,
        muted: false,
        deafened: false,
        participants: newParticipants,
      );
    } catch (e) {
      debugPrint('Failed to join voice channel: $e');
    }
  }

  /// Leave the current voice channel.
  Future<void> leaveChannel() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    try {
      await _api.leaveVoiceChannel(channelId);
    } catch (e) {
      debugPrint('Failed to leave voice channel: $e');
    }

    state = state.copyWith(
      clearChannel: true,
      muted: false,
      deafened: false,
    );
  }

  /// Toggle mute state.
  Future<void> toggleMute() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    final newMuted = !state.muted;
    state = state.copyWith(muted: newMuted);

    try {
      await _api.updateVoiceState(channelId, muted: newMuted);
    } catch (e) {
      state = state.copyWith(muted: !newMuted);
      debugPrint('Failed to update mute: $e');
    }
  }

  /// Toggle deafen state.
  Future<void> toggleDeafen() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    // Capture old state for revert on failure
    final oldMuted = state.muted;
    final oldDeafened = state.deafened;

    final newDeafened = !oldDeafened;
    final newMuted = newDeafened ? true : oldMuted;
    state = state.copyWith(deafened: newDeafened, muted: newMuted);

    try {
      await _api.updateVoiceState(channelId,
          deafened: newDeafened, muted: newMuted);
    } catch (e) {
      // Revert to the prior state, not an inverted state
      state = state.copyWith(deafened: oldDeafened, muted: oldMuted);
      debugPrint('Failed to update deafen: $e');
    }
  }
}

// ─── Provider ───────────────────────────────────────────────────────────

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final socket = ref.watch(socketServiceProvider);
  final connMgr = ref.read(connectionManagerProvider);
  final userId = ref.watch(authProvider).user?.id;
  return VoiceNotifier(api, socket, connMgr, userId);
});
