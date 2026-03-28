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

  /// Whether the WebRTC connection is currently being established.
  final bool isConnecting;

  /// Current user's mute state.
  final bool muted;

  /// Current user's deafen state.
  final bool deafened;

  /// Set of user IDs currently speaking (audio level above threshold).
  final Set<String> speakingUserIds;

  /// All voice participants across channels: channel_id → list of participants.
  final Map<String, List<VoiceParticipant>> participants;

  const VoiceState({
    this.currentChannelId,
    this.isConnecting = false,
    this.muted = false,
    this.deafened = false,
    this.speakingUserIds = const {},
    this.participants = const {},
  });

  VoiceState copyWith({
    String? currentChannelId,
    bool clearChannel = false,
    bool? isConnecting,
    bool? muted,
    bool? deafened,
    Set<String>? speakingUserIds,
    Map<String, List<VoiceParticipant>>? participants,
  }) {
    return VoiceState(
      currentChannelId:
          clearChannel ? null : (currentChannelId ?? this.currentChannelId),
      isConnecting: isConnecting ?? this.isConnecting,
      muted: muted ?? this.muted,
      deafened: deafened ?? this.deafened,
      speakingUserIds: speakingUserIds ?? this.speakingUserIds,
      participants: participants ?? this.participants,
    );
  }

  /// Check if a specific user is currently speaking.
  bool isSpeaking(String userId) => speakingUserIds.contains(userId);

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

// ─── Notifier ───────────────────────────────────────────────────────────

class VoiceNotifier extends StateNotifier<VoiceState> {
  final ApiService _api;
  final SocketService _primarySocket;
  final ConnectionManager _connMgr;
  final String? _currentUserId;
  final Ref _ref;
  final List<StreamSubscription> _subs = [];

  /// Local audio stream from the microphone.
  MediaStream? _localStream;

  /// Single peer connection to the SFU (Server).
  RTCPeerConnection? _serverConnection;

  /// Remote audio streams for playback, keyed by stream ID.
  final Map<String, MediaStream> _remoteStreams = {};

  /// Audio renderers for remote streams (required on desktop for playback).
  final Map<String, RTCVideoRenderer> _audioRenderers = {};

  /// Map stream IDs to user IDs for speaking detection.
  final Map<String, String> _streamToUserId = {};

  /// Timer for polling audio levels to detect speaking.
  Timer? _speakingTimer;

  /// Audio level threshold to consider someone "speaking" (0.0 - 1.0).
  /// Values below this are considered silence/background noise.
  static const double _speakingThreshold = 0.01;

  static const String serverId = '00000000-0000-0000-0000-000000000000';

  VoiceNotifier(this._api, this._primarySocket, this._connMgr,
      this._currentUserId, this._ref)
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
    _stopSpeakingDetection();
    _cleanupWebRTC();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  String _mungeSdp(String sdp) {
    // Maximum fidelity: stereo 510kbps CBR, 48kHz, 10ms frames, FEC enabled.
    // NOTE: SDP fmtp uses semicolons WITHOUT spaces as separators.
    const voiceParams =
        'useinbandfec=1;stereo=1;sprop-stereo=1;maxaveragebitrate=510000;'
        'maxplaybackrate=48000;sprop-maxcapturerate=48000;cbr=1;usedtx=0;'
        'ptime=10;minptime=10';

    var munged = sdp;

    // Replace existing fmtp opus line with our high-fidelity parameters
    final fmtpRegex = RegExp(r'a=fmtp:(\d+) (.+)', multiLine: true);
    munged = munged.replaceAllMapped(fmtpRegex, (match) {
      final payloadType = match.group(1)!;
      // Only modify Opus lines (check if the corresponding rtpmap is opus)
      if (sdp.contains('a=rtpmap:$payloadType opus/')) {
        return 'a=fmtp:$payloadType $voiceParams';
      }
      return match.group(0)!;
    });

    // Strip comfort noise (CN) codec — it inserts fake hiss during silence
    // that degrades perceived quality. Remove the rtpmap, fmtp, and rtp lines.
    final cnPayloadRegex = RegExp(r'a=rtpmap:(\d+) CN/', multiLine: true);
    final cnPayloads = cnPayloadRegex.allMatches(munged)
        .map((m) => m.group(1)!)
        .toList();
    for (final pt in cnPayloads) {
      // Remove a=rtpmap:<pt> CN/...
      munged = munged.replaceAll(RegExp('a=rtpmap:$pt CN/.*\r?\n'), '');
      // Remove a=fmtp:<pt> ...
      munged = munged.replaceAll(RegExp('a=fmtp:$pt .*\r?\n'), '');
      // Remove <pt> from m= lines (e.g. m=audio 9 UDP/TLS/RTP/SAVPF 111 110 ...)
      munged = munged.replaceAllMapped(
        RegExp(r'(m=audio \S+ \S+)(.+)', multiLine: true),
        (match) {
          final header = match.group(1)!;
          final payloads = match.group(2)!;
          final cleaned = payloads.replaceAll(RegExp(' $pt\\b|\\b$pt '), ' ').trim();
          return '$header $cleaned';
        },
      );
    }

    return munged;
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

    // Only handle signals from the server (serverId or nil UUID)
    if (fromUserId != serverId &&
        fromUserId != '00000000-0000-0000-0000-000000000000') {
      return;
    }

    debugPrint('[Voice] Signal from server: $signalType');

    switch (signalType) {
      case 'answer':
        // Server responding to our initial offer
        await _handleAnswer(payload);
        break;
      case 'offer':
        // Server-initiated renegotiation (new user joined, track added)
        await _handleServerOffer(payload);
        break;
      case 'ice':
        await _handleIceCandidate(payload);
        break;
    }
  }

  /// Handle an answer from the server (response to our initial offer).
  Future<void> _handleAnswer(dynamic payload) async {
    if (_serverConnection == null) return;

    final signalingState = _serverConnection!.signalingState;
    debugPrint('[Voice] handleAnswer: signaling=$signalingState');
    if (signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint(
          '[Voice] Ignoring answer — state is $signalingState, not have-local-offer');
      return;
    }

    final String sdp = payload is String ? payload : payload['sdp'];
    debugPrint('[Voice] Answer SDP length: ${sdp.length}');

    try {
      await _serverConnection!
          .setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      debugPrint('[Voice] Remote description (answer) set OK');
    } catch (e) {
      debugPrint('[Voice] setRemoteDescription (answer) error: $e');
    }
  }

  /// Handle a server-initiated offer (renegotiation — new tracks added).
  /// The server created a new offer because another user joined and their
  /// track was added to our peer connection. We need to set the remote
  /// description and send back an answer.
  Future<void> _handleServerOffer(dynamic payload) async {
    if (_serverConnection == null) {
      debugPrint('[Voice] Ignoring server offer — no peer connection');
      return;
    }

    final String sdp = payload is String ? payload : payload['sdp'];
    debugPrint('[Voice] Server renegotiation offer (${sdp.length} bytes)');

    try {
      await _serverConnection!
          .setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

      final answer = await _serverConnection!.createAnswer();
      final mungedSdp = _mungeSdp(answer.sdp!);
      final modifiedAnswer = RTCSessionDescription(mungedSdp, answer.type);

      await _serverConnection!.setLocalDescription(modifiedAnswer);

      // Send answer immediately (Trickle ICE)
      debugPrint('[Voice] Sending renegotiation answer (${modifiedAnswer.sdp!.length} bytes)');
      _sendSignal(
        toUserId: serverId,
        channelId: state.currentChannelId!,
        signalType: 'answer',
        payload: modifiedAnswer.sdp,
      );
    } catch (e) {
      debugPrint('[Voice] Server offer handling error: $e');
    }
  }

  Future<void> _handleIceCandidate(dynamic payload) async {
    if (_serverConnection == null) return;

    if (payload is Map<String, dynamic>) {
      await _serverConnection!.addCandidate(RTCIceCandidate(
        payload['candidate'],
        payload['sdpMid'],
        payload['sdpMLineIndex'],
      ));
    } else if (payload is String) {
      await _serverConnection!
          .addCandidate(RTCIceCandidate(payload, null, null));
    }
  }

  // ─── Peer Connection Management ─────────────────────────────────────

  Future<RTCPeerConnection> _getOrCreateServerConnection() async {
    if (_serverConnection != null) return _serverConnection!;

    final pc = await createPeerConnection(_rtcConfig);
    _serverConnection = pc;

    // Handle incoming remote tracks (from other users, forwarded by SFU)
    pc.onTrack = (RTCTrackEvent event) async {
      debugPrint('[Voice] onTrack: id=${event.track.id}, '
          'kind=${event.track.kind}, streams=${event.streams.length}, '
          'enabled=${event.track.enabled}');

      // Enable the track for playback (unless deafened)
      event.track.enabled = !state.deafened;

      if (event.streams.isNotEmpty) {
        final stream = event.streams[0];
        _setupRemoteStream(stream);
      }
    };

    // onAddStream is critical for audio playback on desktop platforms.
    // ignore: deprecated_member_use
    pc.onAddStream = (MediaStream stream) {
      debugPrint('[Voice] onAddStream: streamId=${stream.id}, '
          'audioTracks=${stream.getAudioTracks().length}');
      _setupRemoteStream(stream);
    };

    // Handle remote stream removal
    // ignore: deprecated_member_use
    pc.onRemoveStream = (MediaStream stream) {
      debugPrint('[Voice] onRemoveStream: ${stream.id}');
      _teardownRemoteStream(stream.id);
    };

    // Handle ICE candidates — send to server
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (state.currentChannelId != null && candidate.candidate != null) {
        _sendSignal(
          toUserId: serverId,
          channelId: state.currentChannelId!,
          signalType: 'ice',
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState iceState) {
      debugPrint('[Voice] ICE state: $iceState');
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        state = state.copyWith(isConnecting: false);
        _startSpeakingDetection();
      } else if (iceState ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        state = state.copyWith(isConnecting: true);
        _stopSpeakingDetection();
      }
    };

    return pc;
  }

  /// Set up a remote stream for audio playback.
  /// Called from both onTrack and onAddStream — deduplicates by stream ID.
  Future<void> _setupRemoteStream(MediaStream stream) async {
    final streamId = stream.id;

    // Deduplicate — only one renderer per stream
    if (_audioRenderers.containsKey(streamId)) {
      debugPrint('[Voice] Stream $streamId already has a renderer, skipping');
      return;
    }

    _remoteStreams[streamId] = stream;

    // Extract user ID from stream ID (server names them 'stream-{userId}')
    if (streamId.startsWith('stream-')) {
      final userId = streamId.substring(7); // Remove 'stream-' prefix
      _streamToUserId[streamId] = userId;
      debugPrint('[Voice] Mapped stream $streamId to user $userId');
    }

    // Enable all audio tracks
    for (final audioTrack in stream.getAudioTracks()) {
      audioTrack.enabled = !state.deafened;
      debugPrint(
          '[Voice] Audio track ${audioTrack.id} enabled=${audioTrack.enabled}');
    }

    // On desktop (Windows/macOS/Linux), an RTCVideoRenderer is required
    // to activate audio output — even for audio-only streams.
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      _audioRenderers[streamId] = renderer;
      debugPrint('[Voice] Renderer created for stream $streamId '
          '(audioTracks=${stream.getAudioTracks().length})');
    } catch (e) {
      debugPrint('[Voice] Renderer setup error for stream $streamId: $e');
    }
  }

  /// Tear down renderer and stream reference for a removed stream.
  void _teardownRemoteStream(String streamId) {
    _remoteStreams.remove(streamId);
    _streamToUserId.remove(streamId);
    final renderer = _audioRenderers.remove(streamId);
    if (renderer != null) {
      try {
        renderer.srcObject = null;
        renderer.dispose();
      } catch (e) {
        debugPrint('[Voice] Renderer teardown error: $e');
      }
    }
  }

  /// Initiate the SFU call: add local audio tracks, create offer, send to server.
  Future<void> _initiateSfuCall(String channelId) async {
    final pc = await _getOrCreateServerConnection();

    // Add local audio tracks
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    // Force the actual Opus encoder to use max bitrate via setParameters.
    // SDP maxaveragebitrate is only a hint — this directly controls the encoder.
    await _forceEncoderBitrate(pc);

    // Create offer and send to server
    final offer = await pc.createOffer();
    final mungedSdp = _mungeSdp(offer.sdp!);
    final modifiedOffer = RTCSessionDescription(mungedSdp, offer.type);

    await pc.setLocalDescription(modifiedOffer);

    // Send offer immediately (Trickle ICE)
    debugPrint('[Voice] Sending SFU offer (${modifiedOffer.sdp!.length} bytes)');
    _sendSignal(
      toUserId: serverId,
      channelId: channelId,
      signalType: 'offer',
      payload: modifiedOffer.sdp,
    );
  }

  /// Force the Opus encoder bitrate to 510kbps on all audio senders.
  /// This bypasses SDP hints and directly configures the encoder,
  /// guaranteeing the bitrate we want.
  Future<void> _forceEncoderBitrate(RTCPeerConnection pc) async {
    try {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          final params = sender.parameters;
          if (params.encodings != null) {
            for (final encoding in params.encodings!) {
              encoding.maxBitrate = 510000;
            }
            await sender.setParameters(params);
            debugPrint('[Voice] Forced encoder bitrate to 510kbps');
          }
        }
      }
    } catch (e) {
      debugPrint('[Voice] setParameters warning (non-fatal): $e');
    }
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
  }

  Future<void> _cleanupWebRTC() async {
    try {
      await _serverConnection?.close();
    } catch (e) {
      debugPrint('WebRTC close warning (safe to ignore): $e');
    }
    _serverConnection = null;
    _remoteStreams.clear();
    _streamToUserId.clear();
    _stopSpeakingDetection();

    // Dispose audio renderers
    final renderers = _audioRenderers.values.toList();
    _audioRenderers.clear();
    for (final renderer in renderers) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (e) {
        debugPrint('Renderer dispose warning (safe to ignore): $e');
      }
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await track.stop();
        } catch (e) {
          debugPrint('Track stop warning (safe to ignore): $e');
        }
      }
      try {
        await _localStream!.dispose();
      } catch (e) {
        debugPrint('Stream dispose warning (safe to ignore): $e');
      }
      _localStream = null;
    }
  }

  // ─── Speaking Detection ───────────────────────────────────────────────

  /// Start polling audio levels to detect who's speaking.
  void _startSpeakingDetection() {
    _stopSpeakingDetection(); // Cancel any existing timer
    _speakingTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollAudioLevels(),
    );
    debugPrint('[Voice] Speaking detection started');
  }

  /// Stop the speaking detection polling.
  void _stopSpeakingDetection() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    if (state.speakingUserIds.isNotEmpty) {
      state = state.copyWith(speakingUserIds: {});
    }
  }

  /// Poll getStats() on the peer connection to read inbound audio levels.
  Future<void> _pollAudioLevels() async {
    if (_serverConnection == null) return;

    try {
      final stats = await _serverConnection!.getStats();
      final newSpeaking = <String>{};

      // Check local mic for current user speaking
      if (_currentUserId != null && !state.muted && _localStream != null) {
        for (final report in stats) {
          final type = report.type;
          // Look for outbound audio stats (media-source type has audioLevel)
          if (type == 'media-source') {
            final kind = report.values['kind'];
            if (kind == 'audio') {
              final audioLevel = report.values['audioLevel'];
              if (audioLevel is num && audioLevel > _speakingThreshold) {
                newSpeaking.add(_currentUserId);
              }
            }
          }
        }
      }

      // Check remote streams for other users speaking
      for (final report in stats) {
        final type = report.type;
        // inbound-rtp stats contain audioLevel for received audio
        if (type == 'inbound-rtp') {
          final kind = report.values['kind'] ?? report.values['mediaType'];
          if (kind == 'audio') {
            final audioLevel = report.values['audioLevel'];
            if (audioLevel is num && audioLevel > _speakingThreshold) {
              // Try to match this to a user via trackIdentifier or stream
              final trackId = report.values['trackIdentifier'] as String?;
              if (trackId != null) {
                // Find which stream this track belongs to
                for (final entry in _remoteStreams.entries) {
                  for (final track in entry.value.getAudioTracks()) {
                    if (track.id == trackId) {
                      final userId = _streamToUserId[entry.key];
                      if (userId != null) {
                        newSpeaking.add(userId);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Only update state if speaking set changed
      if (!_setsEqual(newSpeaking, state.speakingUserIds)) {
        state = state.copyWith(speakingUserIds: newSpeaking);
      }
    } catch (e) {
      // Non-fatal — stats can occasionally fail
      debugPrint('[Voice] Audio level poll error: $e');
    }
  }

  /// Compare two sets for equality without creating a new object.
  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  /// Sync initial participants for a channel (called when fetching server channels)
  void syncInitialParticipants(
      String channelId, List<VoiceParticipant> initialParticipants) {
    final newParticipants =
        Map<String, List<VoiceParticipant>>.from(state.participants);

    if (state.currentChannelId == channelId &&
        newParticipants[channelId] != null) {
      final mergedList =
          List<VoiceParticipant>.from(newParticipants[channelId]!);
      for (final p in initialParticipants) {
        if (!mergedList.any((existing) => existing.userId == p.userId)) {
          mergedList.add(p);
        }
      }
      newParticipants[channelId] = mergedList;
    } else {
      newParticipants[channelId] = initialParticipants;
    }

    state = state.copyWith(participants: newParticipants);
  }

  Future<void> _startLocalAudio() async {
    final settings = _ref.read(settingsProvider);
    final useEC = settings.enableEchoCancellation;
    final useNS = settings.enableNoiseSuppression;
    // AGC disabled — it degrades audio quality by constantly adjusting levels,
    // making speech sound "pumpy" and processed. Better to let the user set
    // their mic level once and leave it alone.
    const useAGC = false;

    debugPrint('[Voice] Audio processing: EC=$useEC, NS=$useNS, AGC=$useAGC');

    final mediaConstraints = {
      'audio': {
        // Use the settings toggles for processing.
        'echoCancellation': useEC,
        'noiseSuppression': useNS,
        'autoGainControl': useAGC,
        'sampleRate': 48000,
        'channelCount': 2, // Stereo — full bandwidth audio
        'highpassFilter': false, // Preserve full frequency range
        'typingNoiseDetection': false, // Don't cut audio on keyboard typing
        // Chrome/libwebrtc-specific constraints
        'googEchoCancellation': useEC,
        'googAutoGainControl': useAGC,
        'googNoiseSuppression': useNS,
        'googHighpassFilter': false,
        'googTypingNoiseDetection': false,
        'googAudioMirroring': false,
        'googDucking': false,
        if (settings.selectedInputDeviceId != null)
          'deviceId': {'exact': settings.selectedInputDeviceId},
      },
      'video': false,
    };

    try {
      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      debugPrint('[Voice] Local audio stream started: ${_localStream!.id}');
    } catch (e) {
      debugPrint('[Voice] Failed to get microphone: $e');
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
      for (final track in stream.getTracks()) {
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
      // No client-side renegotiation needed — the SERVER will send us a
      // new offer with the new user's track when they join.
    }
  }

  Future<void> joinChannel(String channelId) async {
    if (state.currentChannelId == channelId) {
      await leaveChannel();
      return;
    }

    // Clean up any existing WebRTC connection before joining a new channel
    if (state.currentChannelId != null || _serverConnection != null) {
      if (state.currentChannelId != null) {
        try {
          await _api.leaveVoiceChannel(state.currentChannelId!);
        } catch (_) {}
      }
      await _cleanupWebRTC();
    }

    try {
      // 1. Start local audio
      await _startLocalAudio();

      // 2. Join via API
      final currentMuted = state.muted;
      final currentDeafened = state.deafened;
      final data = await _api.joinVoiceChannel(
        channelId,
        muted: currentMuted,
        deafened: currentDeafened,
      );
      final participants = data
          .map((e) => VoiceParticipant.fromJson(e as Map<String, dynamic>))
          .toList();

      final newParticipants =
          Map<String, List<VoiceParticipant>>.from(state.participants);

      final mergedList =
          List<VoiceParticipant>.from(newParticipants[channelId] ?? []);
      for (final p in participants) {
        mergedList.removeWhere((existing) => existing.userId == p.userId);
        mergedList.add(p);
      }
      newParticipants[channelId] = mergedList;

      state = state.copyWith(
        currentChannelId: channelId,
        isConnecting: true,
        muted: currentMuted,
        deafened: currentDeafened,
        participants: newParticipants,
      );

      // 3. Create peer connection and send offer to SFU
      //    The server will respond with an answer containing existing tracks.
      //    When new users join later, the server will send us new offers.
      await _initiateSfuCall(channelId);
    } catch (e) {
      debugPrint('[Voice] Failed to join voice channel: $e');
      await _cleanupWebRTC();
    }
  }

  Future<void> leaveChannel() async {
    final channelId = state.currentChannelId;
    if (channelId == null) return;

    try {
      await _api.leaveVoiceChannel(channelId);
    } catch (e) {
      debugPrint('[Voice] Failed to leave voice channel: $e');
    }

    await _cleanupWebRTC();

    state = state.copyWith(
      clearChannel: true,
      isConnecting: false,
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
      debugPrint('[Voice] Failed to update mute: $e');
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
      debugPrint('[Voice] Failed to update deafen: $e');
    }
  }
}

// ─── Provider ───────────────────────────────────────────────────────────

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final socket = ref.watch(socketServiceProvider);
  final connMgr = ref.read(connectionManagerProvider);
  final userId = ref.watch(authProvider).user?.id;
  return VoiceNotifier(api, socket, connMgr, userId, ref);
});
