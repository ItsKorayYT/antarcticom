import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/role_provider.dart';
import '../../core/models/permissions.dart';
import '../../core/models/role.dart';

class EditRoleScreen extends ConsumerStatefulWidget {
  final String serverId;
  final Role? role;

  const EditRoleScreen({super.key, required this.serverId, this.role});

  @override
  ConsumerState<EditRoleScreen> createState() => _EditRoleScreenState();
}

class _EditRoleScreenState extends ConsumerState<EditRoleScreen> {
  late TextEditingController _nameController;
  late int _permissions;
  late int _color;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role?.name ?? '');
    _permissions = widget.role?.permissions ?? 0;
    _color = widget.role?.color ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _togglePermission(int permission) {
    setState(() {
      if ((_permissions & permission) != 0) {
        _permissions &= ~permission;
      } else {
        _permissions |= permission;
      }
    });
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      if (widget.role == null) {
        await ref.read(rolesProvider(widget.serverId).notifier).createRole(
              _nameController.text,
              _permissions,
              _color,
            );
      } else {
        await ref.read(rolesProvider(widget.serverId).notifier).updateRole(
              widget.role!.id,
              _nameController.text,
              _permissions,
              _color,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == null ? 'Create Role' : 'Edit Role'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Role Name'),
          ),
          const SizedBox(height: 20),
          const Text('Permissions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          CheckboxListTile(
            title: const Text('Administrator'),
            subtitle: const Text('Grants all permissions. Dangerous!'),
            value: (_permissions & Permissions.administrator) != 0,
            onChanged: (v) => _togglePermission(Permissions.administrator),
          ),
          CheckboxListTile(
            title: const Text('Manage Server'),
            value: (_permissions & Permissions.manageServer) != 0,
            onChanged: (v) => _togglePermission(Permissions.manageServer),
          ),
          CheckboxListTile(
            title: const Text('Manage Channels'),
            value: (_permissions & Permissions.manageChannels) != 0,
            onChanged: (v) => _togglePermission(Permissions.manageChannels),
          ),
          CheckboxListTile(
            title: const Text('Kick Members'),
            value: (_permissions & Permissions.kickMembers) != 0,
            onChanged: (v) => _togglePermission(Permissions.kickMembers),
          ),
          CheckboxListTile(
            title: const Text('Ban Members'),
            value: (_permissions & Permissions.banMembers) != 0,
            onChanged: (v) => _togglePermission(Permissions.banMembers),
          ),
          CheckboxListTile(
            title: const Text('Send Messages'),
            value: (_permissions & Permissions.sendMessages) != 0,
            onChanged: (v) => _togglePermission(Permissions.sendMessages),
          ),
          if (widget.role != null) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Role'),
                    content: const Text(
                        'Are you sure you want to delete this role?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(rolesProvider(widget.serverId).notifier)
                      .deleteRole(widget.role!.id);
                  if (mounted) navigator.pop();
                }
              },
              child: const Text('Delete Role'),
            ),
          ],
        ],
      ),
    );
  }
}
