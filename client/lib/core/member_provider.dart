import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'auth_provider.dart';
import 'role_provider.dart';
import 'server_provider.dart';
import 'models/member.dart';
import 'models/permissions.dart';

class CurrentMemberNotifier extends StateNotifier<AsyncValue<Member>> {
  final ApiService _api;
  final String serverId;
  final String? userId;

  CurrentMemberNotifier(this._api, this.serverId, this.userId)
      : super(const AsyncValue.loading()) {
    if (userId != null) {
      fetchMember();
    }
  }

  Future<void> fetchMember() async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.getMember(serverId, userId!);
      final member = Member.fromJson(data);
      state = AsyncValue.data(member);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final currentMemberProvider = StateNotifierProvider.family<
    CurrentMemberNotifier, AsyncValue<Member>, String>(
  (ref, serverId) {
    final api = ref.watch(apiServiceProvider);
    final user = ref.watch(authProvider).user;
    return CurrentMemberNotifier(api, serverId, user?.id);
  },
);

final permissionsProvider =
    Provider.family<Permissions, String>((ref, serverId) {
  final memberAsync = ref.watch(currentMemberProvider(serverId));
  final rolesState = ref.watch(rolesProvider(serverId));
  final serversState = ref.watch(serversProvider);
  final user = ref.watch(authProvider).user;

  // Defaults to 0 permissions if loading or error
  return memberAsync.maybeWhen(
    data: (member) {
      // 1. Check if owner
      final server = serversState.servers.firstWhere(
        (s) => s.id == serverId,
        orElse: () => const ServerInfo(
            id: '', name: '', ownerId: '', iconHash: null), // dummy
      );

      if (server.id.isNotEmpty && server.ownerId == user?.id) {
        return const Permissions(Permissions.administrator);
      }

      // 2. Aggregate role permissions
      int raw = 0;

      // Add @everyone role permissions (roleId == serverId typically, or we find by name)
      // Our backend creates @everyone with random ID or we need to find it.
      // Current backend `db::roles::create` makes random ID.
      // We need to identify @everyone. By name "@everyone".
      final everyoneRole =
          rolesState.roles.where((r) => r.name == '@everyone').firstOrNull;
      if (everyoneRole != null) {
        raw |= everyoneRole.permissions;
      }

      for (final roleId in member.roles) {
        final role = rolesState.roles.where((r) => r.id == roleId).firstOrNull;
        if (role != null) {
          raw |= role.permissions;
        }
      }

      return Permissions(raw);
    },
    orElse: () => const Permissions(0),
  );
});

// ─── Server Members Notifier ─────────────────────────────────────────────

class ServerMembersNotifier extends StateNotifier<AsyncValue<List<Member>>> {
  final ApiService _api;
  final SocketService _socket;
  final String serverId;

  ServerMembersNotifier(this._api, this._socket, this.serverId)
      : super(const AsyncValue.loading()) {
    fetchMembers();
    _socket.events.listen(_handleEvent);
  }

  Future<void> fetchMembers() async {
    state = const AsyncValue.loading();
    try {
      final data = await _api.getMembers(serverId);
      final members =
          data.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
      state = AsyncValue.data(members);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _handleEvent(WsEvent event) {
    if (event.type == 'PresenceUpdate') {
      final userId = event.data?['user_id'] as String?;
      final status = event.data?['status'] as String?;

      if (userId != null && status != null) {
        state.whenData((members) {
          final index = members.indexWhere((m) => m.userId == userId);
          if (index != -1) {
            final updated =
                members[index].copyWith(status: status.toLowerCase());
            final newMembers = List<Member>.from(members);
            newMembers[index] = updated;
            state = AsyncValue.data(newMembers);
          }
        });
      }
    }
    // Also handle MemberJoin/Leave if desired
  }
}

final serverMembersProvider = StateNotifierProvider.family<
    ServerMembersNotifier, AsyncValue<List<Member>>, String>((ref, serverId) {
  final api = ref.watch(apiServiceProvider);
  final socket = ref.watch(socketServiceProvider);
  return ServerMembersNotifier(api, socket, serverId);
});
