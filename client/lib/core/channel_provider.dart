import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';

// ─── Channel Model ──────────────────────────────────────────────────────

class ChannelInfo {
  final String id;
  final String serverId;
  final String name;
  final String channelType; // "Text", "Voice", "Announcement"
  final int position;

  const ChannelInfo({
    required this.id,
    required this.serverId,
    required this.name,
    required this.channelType,
    required this.position,
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    return ChannelInfo(
      id: json['id'] as String,
      serverId: json['server_id'] as String,
      name: json['name'] as String,
      channelType: json['channel_type'] as String,
      position: json['position'] as int,
    );
  }

  bool get isText => channelType == 'Text';
  bool get isVoice => channelType == 'Voice';
}

// ─── State ──────────────────────────────────────────────────────────────

class ChannelsState {
  final bool isLoading;
  final List<ChannelInfo> channels;
  final String? error;

  const ChannelsState({
    this.isLoading = false,
    this.channels = const [],
    this.error,
  });

  List<ChannelInfo> get textChannels => channels.where((c) => c.isText).toList()
    ..sort((a, b) => a.position.compareTo(b.position));

  List<ChannelInfo> get voiceChannels =>
      channels.where((c) => c.isVoice).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
}

// ─── Notifier ───────────────────────────────────────────────────────────

class ChannelsNotifier extends StateNotifier<ChannelsState> {
  final ApiService _api;

  ChannelsNotifier(this._api) : super(const ChannelsState());

  Future<void> fetchChannels(String serverId) async {
    state = const ChannelsState(isLoading: true);
    try {
      final data = await _api.listChannels(serverId);
      final channels = data
          .map((e) => ChannelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      state = ChannelsState(channels: channels);
    } catch (e) {
      state = const ChannelsState(error: 'Failed to load channels');
    }
  }

  void clear() {
    state = const ChannelsState();
  }
}

// ─── Providers ──────────────────────────────────────────────────────────

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, ChannelsState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ChannelsNotifier(api);
});

/// Currently selected channel ID.
final selectedChannelIdProvider = StateProvider<String?>((ref) => null);
