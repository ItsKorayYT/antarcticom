import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/member.dart';
import '../../core/models/permissions.dart';
import '../../core/member_provider.dart';
import '../../core/api_service.dart';
import '../../core/server_provider.dart';
import '../../core/auth_provider.dart';
import '../../core/role_provider.dart';

class MemberList extends ConsumerWidget {
  final String serverId;
  final bool isMobile;

  const MemberList({
    super.key,
    required this.serverId,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(serverMembersProvider(serverId));

    return Container(
      width: isMobile ? null : 240,
      color: AntarcticomTheme.bgSecondary,
      child: membersAsync.when(
        data: (members) {
          // Group by status
          final online = members
              .where((m) =>
                  m.status == 'online' ||
                  m.status == 'idle' ||
                  m.status == 'dnd')
              .toList();
          final offline = members
              .where((m) =>
                  m.status == 'offline' ||
                  m.status == '') // Handle empty/unknown as offline
              .toList();

          // Sort by name
          online.sort((a, b) =>
              (a.user?.username ?? '').compareTo(b.user?.username ?? ''));
          offline.sort((a, b) =>
              (a.user?.username ?? '').compareTo(b.user?.username ?? ''));

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (online.isNotEmpty) ...[
                _buildCategoryHeader('ONLINE — ${online.length}'),
                ...online.map((m) => _MemberItem(member: m)),
              ],
              if (online.isNotEmpty && offline.isNotEmpty)
                const SizedBox(height: 16),
              if (offline.isNotEmpty) ...[
                _buildCategoryHeader('OFFLINE — ${offline.length}'),
                ...offline.map((m) => _MemberItem(member: m)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AntarcticomTheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MemberItem extends ConsumerWidget {
  final Member member;

  const _MemberItem({required this.member});

  /// Build the full avatar URL from the API base URL, user ID, and hash.
  String? _buildAvatarUrl(String baseUrl, String? userId, String? avatarHash) {
    if (userId == null || avatarHash == null) return null;
    return '$baseUrl/api/avatars/$userId/$avatarHash';
  }

  /// Status indicator color.
  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'idle':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Status display label.
  String _statusLabel(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'idle':
        return 'Idle';
      case 'dnd':
        return 'Do Not Disturb';
      default:
        return 'Offline';
    }
  }

  void _showRoleManagerDialog(
      BuildContext context, WidgetRef ref, Member targetMember) {
    showDialog(
      context: context,
      builder: (ctx) => _RoleManagerDialog(member: targetMember),
    );
  }

  void _showUserProfile(
      BuildContext context,
      WidgetRef ref,
      String? avatarUrl,
      bool canKick,
      bool canBan,
      bool canManageRoles,
      bool targetIsAdmin,
      bool isSelf,
      bool targetIsOwner) {
    final user = member.user;
    final name =
        member.nickname ?? user?.displayName ?? user?.username ?? 'Unknown';
    final username = user?.username ?? '';
    final statusColor = _statusColor(member.status);
    final statusLabel = _statusLabel(member.status);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final d = member.joinedAt;
    final joinedDate = '${months[d.month - 1]} ${d.day}, ${d.year}';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AntarcticomTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AntarcticomTheme.radiusMd),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Banner area
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: AntarcticomTheme.accentGradient,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(AntarcticomTheme.radiusMd),
                      topRight: Radius.circular(AntarcticomTheme.radiusMd),
                    ),
                  ),
                ),

                // Avatar (overlapping the banner)
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AntarcticomTheme.bgSecondary,
                            width: 5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: AntarcticomTheme.bgTertiary,
                          backgroundImage: avatarUrl != null
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl == null
                              ? Text(
                                  name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AntarcticomTheme.bgSecondary,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // User info
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Transform.translate(
                    offset: const Offset(0, -20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display name
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: AntarcticomTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (targetIsOwner) ...[
                              const SizedBox(width: 8),
                              const Tooltip(
                                message: 'Server Owner',
                                child: Icon(
                                  Icons
                                      .workspace_premium, // Crown icon approximation
                                  color: Colors.amber,
                                  size: 20,
                                ),
                              ),
                            ] else if (targetIsAdmin) ...[
                              const SizedBox(width: 8),
                              const Tooltip(
                                message: 'Server Admin',
                                child: Icon(
                                  Icons.shield,
                                  color: AntarcticomTheme.accentSecondary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            style: const TextStyle(
                              color: AntarcticomTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),

                        const SizedBox(height: 12),
                        const Divider(
                          color: AntarcticomTheme.bgTertiary,
                          height: 1,
                        ),
                        const SizedBox(height: 12),

                        // Status
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              statusLabel,
                              style: const TextStyle(
                                color: AntarcticomTheme.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Member since
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: AntarcticomTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Member since $joinedDate',
                              style: const TextStyle(
                                color: AntarcticomTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        // Admin Actions
                        if (!isSelf &&
                            !targetIsOwner &&
                            (canKick || canBan || canManageRoles)) ...[
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              if (canManageRoles)
                                TextButton.icon(
                                  onPressed: () => _showRoleManagerDialog(
                                      context, ref, member),
                                  icon: const Icon(Icons.stars,
                                      size: 18, color: Colors.purpleAccent),
                                  label: const Text('Manage Roles',
                                      style: TextStyle(
                                          color: Colors.purpleAccent)),
                                ),
                              if (canKick)
                                TextButton.icon(
                                  onPressed: () async {
                                    final api = ref.read(apiServiceProvider);
                                    try {
                                      await api.kickMember(
                                          member.serverId, member.userId);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Failed to kick member. Missing permissions?')),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.person_remove,
                                      size: 18, color: Colors.orange),
                                  label: const Text('Kick',
                                      style: TextStyle(color: Colors.orange)),
                                ),
                              if (canBan)
                                TextButton.icon(
                                  onPressed: () async {
                                    final api = ref.read(apiServiceProvider);
                                    try {
                                      await api.banMember(
                                          member.serverId, member.userId);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Failed to ban member. Missing permissions?')),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.block,
                                      size: 18, color: Colors.redAccent),
                                  label: const Text('Ban',
                                      style:
                                          TextStyle(color: Colors.redAccent)),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = member.user;
    final name =
        member.nickname ?? user?.displayName ?? user?.username ?? 'Unknown';
    final baseUrl = ref.watch(apiServiceProvider).baseUrl;
    final avatarUrl = _buildAvatarUrl(baseUrl, user?.id, user?.avatarHash);
    final statusColor = _statusColor(member.status);

    // Check permissions for the current user
    final currentUserPerms = ref.watch(permissionsProvider(member.serverId));
    final canKick = currentUserPerms.has(Permissions.kickMembers);
    final canBan = currentUserPerms.has(Permissions.banMembers);
    final canManageRoles = currentUserPerms.has(Permissions.administrator);

    // Check permissions for the target user (to see if they are already an admin)
    final targetUserPerms = ref.watch(memberPermissionsProvider(member));
    final targetIsAdmin = targetUserPerms.has(Permissions.administrator);

    // Check if target is owner
    final targetIsOwner = ref
        .watch(serversProvider)
        .servers
        .any((s) => s.id == member.serverId && s.ownerId == member.userId);

    // Ensure we don't show these actions on ourselves
    final auth = ref.watch(authProvider);
    final isSelf = auth.user?.id == member.userId;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: AntarcticomTheme.bgTertiary,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white))
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border:
                    Border.all(color: AntarcticomTheme.bgSecondary, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        name,
        style: TextStyle(
          color: member.status == 'offline'
              ? AntarcticomTheme.textMuted
              : AntarcticomTheme.textPrimary,
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () => _showUserProfile(context, ref, avatarUrl, canKick, canBan,
          canManageRoles, targetIsAdmin, isSelf, targetIsOwner),
    );
  }
}

class _RoleManagerDialog extends ConsumerStatefulWidget {
  final Member member;

  const _RoleManagerDialog({required this.member});

  @override
  ConsumerState<_RoleManagerDialog> createState() => _RoleManagerDialogState();
}

class _RoleManagerDialogState extends ConsumerState<_RoleManagerDialog> {
  final Set<String> _processingRoleIds = {};

  @override
  Widget build(BuildContext context) {
    final rolesState = ref.watch(rolesProvider(widget.member.serverId));

    return Dialog(
      backgroundColor: AntarcticomTheme.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AntarcticomTheme.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage Roles',
                style: TextStyle(
                  color: AntarcticomTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (rolesState.isLoading && rolesState.roles.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (rolesState.error != null)
                Center(
                  child: Text(
                    rolesState.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              else if (rolesState.roles
                  .where((r) => r.name != '@everyone')
                  .isEmpty)
                const Center(
                  child: Text(
                    'No custom roles found.',
                    style: TextStyle(color: AntarcticomTheme.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rolesState.roles.length,
                    itemBuilder: (context, index) {
                      final role = rolesState.roles[index];
                      // Don't allow modifying @everyone here
                      if (role.name == '@everyone') {
                        return const SizedBox.shrink();
                      }

                      final hasRole = widget.member.roles.contains(role.id);
                      final isProcessing = _processingRoleIds.contains(role.id);

                      return CheckboxListTile(
                        title: Text(
                          role.name,
                          style: TextStyle(
                            color: Color(role.color == 0
                                ? 0xFFFFFFFF
                                : (role.color | 0xFF000000)),
                            fontWeight:
                                hasRole ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        value: hasRole,
                        activeColor: AntarcticomTheme.accentPrimary,
                        checkColor: Colors.white,
                        onChanged: isProcessing
                            ? null
                            : (bool? value) =>
                                _toggleRole(role.id, value ?? false),
                        secondary: isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : null,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRole(String roleId, bool assign) async {
    setState(() {
      _processingRoleIds.add(roleId);
    });

    try {
      final api = ref.read(apiServiceProvider);
      if (assign) {
        await api.assignRole(
            widget.member.serverId, widget.member.userId, roleId);
      } else {
        await api.removeRole(
            widget.member.serverId, widget.member.userId, roleId);
      }

      // Close both the role manager dialog and the user profile dialog to force a refresh
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                assign ? 'Failed to assign role.' : 'Failed to remove role.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingRoleIds.remove(roleId);
        });
      }
    }
  }
}
