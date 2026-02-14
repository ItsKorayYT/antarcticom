import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/models/member.dart';
import '../../core/member_provider.dart';

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
    // We'll need a provider that returns List<Member> for the server
    // and listens to presence updates.
    // For now, let's assume membersProvider(serverId) gives us the list
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

class _MemberItem extends StatelessWidget {
  final Member member;

  const _MemberItem({required this.member});

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final name =
        member.nickname ?? user?.displayName ?? user?.username ?? 'Unknown';
    final avatarUrl = user?.avatarHash; // TODO: construct full URL

    // Status color
    Color statusColor = Colors.grey;
    switch (member.status) {
      case 'online':
        statusColor = Colors.green;
        break;
      case 'idle':
        statusColor = Colors.orange;
        break;
      case 'dnd':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

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
      // subtitle: member.status != 'offline' ? Text(member.status) : null,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () {
        // TODO: Open user profile
      },
    );
  }
}
