import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api_service.dart';
import 'socket_service.dart';
import 'connection_manager.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

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

// ─── WebRTC Configuration ───────────────────────────────────────────────

const Map<String, dynamic> _rtcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ],
};

const Map<String, dynamic> _mediaConstraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': false,
};

// ─── Notifier ───────────────────────────────────────────────────────────

class VoiceNotifier extends StateNotifier<VoiceState> {
  final ApiService _api;
  final SocketService _primarySocket;
  final ConnectionManager _connMgr;
  final String? _currentUserId;
  final AppSettings _settings;
  final List<StreamSubscription> _subs = [];

  /// Local audio stream from the microphone.
  MediaStream? _localStream;

  /// Single peer connection to the SFU (Server).
  RTCPeerConnection? _serverConnection;

  /// Remote audio streams for playback, keyed by track ID.
  final Map<String, MediaStream> _remoteStreams = {};

  static const String serverId = '00000000-0000-0000-0000-000000000000';

  VoiceNotifier(this._api, this._primarySocket, this._connMgr,
      this._currentUserId, this._settings)
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
    _cleanupWebRTC();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _handleEvent(WsEvent event) {
    if (event.type == 'VoiceStateUpdate' && event.data != null) {
      _handleVoiceUpdate(event.data!);
    } else if (event.type == 'WebRTCSignal' && event.data != null) {
      _handleWebRTCSignal(event.data!);
    }
  }

  // ─── WebRTC Signal Handling ─────────────────────────────────────────

  Future<void> _handleWebRTCSignal(Map<String, dynamic> data) async {
    final fromUserId = data['from_user_id'] as String?;
    final channelId = data['channel_id'] as String?;
    final signalType = data['signal_type'] as String?;
    final payload = data['payload'];

    if (fromUserId == null ||
        channelId == null ||
        signalType == null ||
        payload == null) {
      return;
    }
    if (channelId != state.currentChannelId) {
      return; // ignore signals for other channels
    }

    // Only handle signals from the server (serverId or nil)
    if (fromUserId != serverId &&
        fromUserId != '00000000-0000-0000-0000-000000000000') {
      return;
    }

    debugPrint('WebRTC SFU signal from server: $signalType');

    switch (signalType) {
      case 'answer':
        await _handleAnswer(payload);
        break;
      case 'ice':
        await _handleIceCandidate(payload);
        break;
    }
  }

  Future<void> _handleAnswer(dynamic payload) async {
    if (_serverConnection == null) return;

    // Server payload is just the SDP string in our current implementation
    final String sdp = payload is String ? payload : payload['sdp'];
    await _serverConnection!
        .setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _handleIceCandidate(dynamic payload) async {
    if (_serverConnection == null) return;

    final String? candidateStr =
        payload is String ? payload : payload['candidate'];
    if (candidateStr != null) {
      await _serverConnection!
          .addCandidate(RTCIceCandidate(candidateStr, null, null));
    }
  }

  // ─── Peer Connection Management ─────────────────────────────────────

  Future<RTCPeerConnection> _getOrCreateServerConnection() async {
    if (_serverConnection != null) return _serverConnection!;

    final pc = await createPeerConnection(_rtcConfig);
    _serverConnection = pc;

    // Handle incoming remote tracks (from other users, forwarded by SFU)
    pc.onTrack = (RTCTrackEvent event) {
      debugPrint('Remote track received from SFU: ${event.track.id}');
      if (event.streams.isNotEmpty) {
        _remoteStreams[event.track.id!] = event.streams[0];
        // If deafened, mute all remote audio
        if (state.deafened) {
          _muteRemoteStreams(true);
        }
      }
    };

    // Handle ICE candidates — send to server
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (state.currentChannelId != null) {
        _sendSignal(
          toUserId: serverId,
          channelId: state.currentChannelId!,
          signalType: 'ice',
          payload: candidate.candidate!,
        );
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState iceState) {
      debugPrint('ICE state with SFU: $iceState');
    };

    return pc;
  }

  Future<void> _initiateSfuCall(String channelId) async {
    final pc = await _getOrCreateServerConnection();

    // Add local audio tracks
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // Wait for ICE gathering to complete so the SDP contains all candidates.
    // This avoids sending an incomplete offer to the SFU.
    final completer = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState gatheringState) {
      debugPrint('ICE gathering state: $gatheringState');
      if (gatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    // Timeout after 3 seconds in case gathering never completes
    await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint(
            'ICE gathering timed out, sending offer with available candidates');
      },
    );

    // Use the updated local description which now includes ICE candidates
    final updatedDesc = await pc.getLocalDescription();
    final sdpToSend = updatedDesc?.sdp ?? offer.sdp!;

    debugPrint('Sending SFU offer (${sdpToSend.length} bytes)');
    _sendSignal(
      toUserId: serverId,
      channelId: channelId,
      signalType: 'offer',
      payload: sdpToSend,
    );
  }

  void _sendSignal({
    required String toUserId,
    required String channelId,
    required String signalType,
    required dynamic payload,
  }) {
    _primarySocket.sendWebRTCSignal(
      toUserId: toUserId,
      channelId: channelId,
      signalType: signalType,
      payload: payload,
    );

    for (final host in _connMgr.hosts) {
      final socket = _connMgr.getSocketForHost(host.url);
      if (socket != null && socket != _primarySocket) {
        socket.sendWebRTCSignal(
          toUserId: toUserId,
          channelId: channelId,
          signalType: signalType,
          payload: payload,
        );
      }
    }
  }

  Future<void> _cleanupWebRTC() async {
    await _serverConnection?.close();
    _serverConnection = null;
    _remoteStreams.clear();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
  }

  Future<void> _startLocalAudio() async {
    try {
      final constraints = Map<String, dynamic>.from(_mediaConstraints);
      if (_settings.selectedInputDeviceId != null) {
        final audioConstraints = constraints['audio'];
        if (audioConstraints is Map) {
          constraints['audio'] = {
            ...audioConstraints,
            'deviceId': {'exact': _settings.selectedInputDeviceId},
          };
        } else {
          constraints['audio'] = {
            'deviceId': {'exact': _settings.selectedInputDeviceId},
          };
        }
      }

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      debugPrint('Local audio stream started: ${_localStream!.id}');
    } catch (e) {
      debugPrint('Failed to get microphone: $e');
    }
  }

  void _muteLocalAudio(bool mute) {
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !mute;
      }
    }
  }

  void _muteRemoteStreams(bool mute) {
    for (final stream in _remoteStreams.values) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !mute;
      }
    }
  }

  // ─── Voice State (Signaling) Updates ─────────────────────────────────

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
      final list =
          List<VoiceParticipant>.from(newParticipants[channelId] ?? []);
      list.removeWhere((p) => p.userId == userId);
      if (list.isEmpty) {
        newParticipants.remove(channelId);
      } else {
        newParticipants[channelId] = list;
      }
    }

    final isCurrentUser = _currentUserId != null && userId == _currentUserId;
    if (!joined && isCurrentUser && state.currentChannelId == channelId) {
      _cleanupWebRTC();
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

  Future<void> joinChannel(String channelId) async {
    if (state.currentChannelId == channelId) {
      await leaveChannel();
      return;
    }

    try {
      await _startLocalAudio();

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

      // In SFU mode, we only initiate ONE call to the server
      await _initiateSfuCall(channelId);
    } catch (e) {
      debugPrint('Failed to join voice channel: $e');
      await _cleanupWebRTC();
    }
  }

  Future<void> leaveChannel() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    try {
      await _api.leaveVoiceChannel(channelId);
    } catch (e) {
      debugPrint('Failed to leave voice channel: $e');
    }

    await _cleanupWebRTC();

    state = state.copyWith(
      clearChannel: true,
      muted: false,
      deafened: false,
    );
  }

  Future<void> toggleMute() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    final newMuted = !state.muted;
    state = state.copyWith(muted: newMuted);
    _muteLocalAudio(newMuted);

    try {
      await _api.updateVoiceState(channelId, muted: newMuted);
    } catch (e) {
      state = state.copyWith(muted: !newMuted);
      _muteLocalAudio(!newMuted);
      debugPrint('Failed to update mute: $e');
    }
  }

  Future<void> toggleDeafen() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    final oldMuted = state.muted;
    final oldDeafened = state.deafened;

    final newDeafened = !oldDeafened;
    final newMuted = newDeafened ? true : oldMuted;
    state = state.copyWith(deafened: newDeafened, muted: newMuted);

    _muteLocalAudio(newMuted);
    _muteRemoteStreams(newDeafened);

    try {
      await _api.updateVoiceState(channelId,
          deafened: newDeafened, muted: newMuted);
    } catch (e) {
      state = state.copyWith(deafened: oldDeafened, muted: oldMuted);
      _muteLocalAudio(oldMuted);
      _muteRemoteStreams(oldDeafened);
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
  final settings = ref.watch(settingsProvider);
  return VoiceNotifier(api, socket, connMgr, userId, settings);
});
