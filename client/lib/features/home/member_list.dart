import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/member.dart';
import '../../core/models/permissions.dart';
import '../../core/member_provider.dart';
import '../../core/api_service.dart';
import '../../core/auth_provider.dart';

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

  void _showUserProfile(
      BuildContext context, WidgetRef ref, String? avatarUrl) {
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

    // Check permissions for the current user
    final perms = ref.watch(permissionsProvider(member.serverId));
    final canKick = perms.has(Permissions.kickMembers);
    final canBan = perms.has(Permissions.banMembers);
    final canManageRoles = perms.has(Permissions.administrator);

    // Ensure we don't show these actions on ourselves
    final auth = ref.watch(authProvider);
    final isSelf = auth.user?.id == member.userId;

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
                        Text(
                          name,
                          style: const TextStyle(
                            color: AntarcticomTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
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
                            (canKick || canBan || canManageRoles)) ...[
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              if (canManageRoles)
                                TextButton.icon(
                                  onPressed: () async {
                                    final api = ref.read(apiServiceProvider);
                                    try {
                                      final roles =
                                          await api.listRoles(member.serverId);
                                      var adminRole = roles
                                          .where(
                                            (r) =>
                                                ((r['permissions'] as int) &
                                                    32) !=
                                                0,
                                          )
                                          .firstOrNull;

                                      if (adminRole == null) {
                                        adminRole = await api.createRole(
                                          member.serverId,
                                          "Admin",
                                          32, // Administrator permission
                                          0, // default color
                                          100, // high position
                                        );
                                      }
                                      await api.assignRole(
                                          member.serverId,
                                          member.userId,
                                          adminRole['id'] as String);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'User promoted to Admin!')),
                                        );
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Failed to make user an Admin.')),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.admin_panel_settings,
                                      size: 18, color: Colors.blueAccent),
                                  label: const Text('Make Admin',
                                      style:
                                          TextStyle(color: Colors.blueAccent)),
                                ),
                              if (canKick)
                                TextButton.icon(
                                  onPressed: () async {
                                    final api = ref.read(apiServiceProvider);
                                    try {
                                      await api.kickMember(
                                          member.serverId, member.userId);
                                      if (context.mounted)
                                        Navigator.pop(context);
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
                                      if (context.mounted)
                                        Navigator.pop(context);
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
      onTap: () => _showUserProfile(context, ref, avatarUrl),
    );
  }
}
