import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/role_provider.dart';
import 'edit_role_screen.dart';

class RolesScreen extends ConsumerStatefulWidget {
  final String serverId;

  const RolesScreen({super.key, required this.serverId});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch roles on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rolesProvider(widget.serverId).notifier).fetchRoles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rolesState = ref.watch(rolesProvider(widget.serverId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      EditRoleScreen(serverId: widget.serverId),
                ),
              );
            },
          ),
        ],
      ),
      body: rolesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : rolesState.error != null
              ? Center(child: Text(rolesState.error!))
              : ListView.builder(
                  itemCount: rolesState.roles.length,
                  itemBuilder: (context, index) {
                    final role = rolesState.roles[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Color(role.color).withValues(alpha: 1.0),
                        radius: 12,
                      ),
                      title: Text(role.name,
                          style: TextStyle(
                            color: role.color != 0 ? Color(role.color) : null,
                          )),
                      subtitle: Text('Permissions: ${role.permissions}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EditRoleScreen(
                                serverId: widget.serverId,
                                role: role,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
