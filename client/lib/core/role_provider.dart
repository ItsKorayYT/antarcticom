import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'models/role.dart';

class RolesState {
  final bool isLoading;
  final List<Role> roles;
  final String? error;

  const RolesState({
    this.isLoading = false,
    this.roles = const [],
    this.error,
  });
}

class RolesNotifier extends StateNotifier<RolesState> {
  final ApiService _api;
  final String serverId;

  RolesNotifier(this._api, this.serverId)
      : super(const RolesState(isLoading: true)) {
    fetchRoles();
  }

  Future<void> fetchRoles() async {
    state = const RolesState(isLoading: true);
    try {
      final data = await _api.listRoles(serverId);
      final roles =
          data.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList();
      state = RolesState(roles: roles);
    } catch (e) {
      state = const RolesState(error: 'Failed to load roles');
    }
  }

  Future<void> createRole(String name, int permissions, int color) async {
    try {
      final data = await _api.createRole(serverId, name, permissions, color, 0);
      final role = Role.fromJson(data);
      state = RolesState(roles: [role, ...state.roles]);
    } catch (_) {
      // Handle error
    }
  }

  Future<void> updateRole(
      String roleId, String name, int permissions, int color) async {
    try {
      final data = await _api.updateRole(
          serverId, roleId, name, permissions, color, 0); // Position 0 for now
      final updatedRole = Role.fromJson(data);
      state = RolesState(
        roles:
            state.roles.map((r) => r.id == roleId ? updatedRole : r).toList(),
      );
    } catch (_) {
      // Handle error
    }
  }

  Future<void> deleteRole(String roleId) async {
    try {
      await _api.deleteRole(serverId, roleId);
      state = RolesState(
        roles: state.roles.where((r) => r.id != roleId).toList(),
      );
    } catch (_) {
      // Handle error
    }
  }
}

final rolesProvider =
    StateNotifierProvider.family<RolesNotifier, RolesState, String>(
  (ref, serverId) {
    final api = ref.watch(apiServiceProvider);
    return RolesNotifier(api, serverId);
  },
);
