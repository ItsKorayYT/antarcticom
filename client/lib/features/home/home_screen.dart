import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/server_provider.dart';
import '../../core/channel_provider.dart';

/// Main app shell — server list sidebar + channel list + content area.
class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _didAutoSelect = false;

  @override
  void initState() {
    super.initState();
    // Fetch servers on first load
    Future.microtask(() {
      ref.read(serversProvider.notifier).fetchServers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final servers = ref.watch(serversProvider);
    final selectedServerId = ref.watch(selectedServerIdProvider);
    final channels = ref.watch(channelsProvider);
    final selectedChannelId = ref.watch(selectedChannelIdProvider);

    // Auto-select the first server once loaded
    if (!_didAutoSelect &&
        !servers.isLoading &&
        servers.servers.isNotEmpty &&
        selectedServerId == null) {
      _didAutoSelect = true;
      Future.microtask(() => _selectServer(servers.servers.first));
    }

    // Auto-select first text channel once channels load
    if (selectedServerId != null &&
        !channels.isLoading &&
        channels.textChannels.isNotEmpty &&
        selectedChannelId == null) {
      Future.microtask(() => _selectChannel(channels.textChannels.first.id));
    }

    return Scaffold(
      backgroundColor: AntarcticomTheme.bgPrimary,
      body: Row(
        children: [
          // ─── Server List (narrow sidebar) ───────────────────────────
          Container(
            width: 72,
            color: AntarcticomTheme.bgDeepest,
            child: Column(
              children: [
                const SizedBox(height: AntarcticomTheme.spacingMd),

                // Home / DMs button
                _ServerIcon(
                  isHome: true,
                  isSelected: selectedServerId == null,
                  onTap: () {
                    ref.read(selectedServerIdProvider.notifier).state = null;
                    ref.read(channelsProvider.notifier).clear();
                    ref.read(selectedChannelIdProvider.notifier).state = null;
                    context.go('/channels/@me');
                  },
                ),
                const SizedBox(height: AntarcticomTheme.spacingSm),

                // Divider
                Container(
                  width: 32,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AntarcticomTheme.bgTertiary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: AntarcticomTheme.spacingSm),

                // Dynamic server list
                Expanded(
                  child: servers.isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AntarcticomTheme.accentPrimary,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              vertical: AntarcticomTheme.spacingXs),
                          children: servers.servers.map((server) {
                            return _ServerIcon(
                              label: server.initials,
                              color: AntarcticomTheme.accentPrimary,
                              isSelected: selectedServerId == server.id,
                              onTap: () => _selectServer(server),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),

          // ─── Channel List (sidebar) ─────────────────────────────────
          Container(
            width: 240,
            color: AntarcticomTheme.bgSecondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Server header
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AntarcticomTheme.spacingMd),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            AntarcticomTheme.bgDeepest.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selectedServerId != null
                        ? (servers.servers
                                .where((s) => s.id == selectedServerId)
                                .map((s) => s.name)
                                .firstOrNull ??
                            'Server')
                        : 'Direct Messages',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Channel list
                Expanded(
                  child: selectedServerId == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(
                                AntarcticomTheme.spacingMd),
                            child: Text(
                              servers.servers.isEmpty
                                  ? 'Create or join a server to get started!'
                                  : 'Select a server',
                              style: TextStyle(
                                  color: AntarcticomTheme.textMuted,
                                  fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : channels.isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AntarcticomTheme.accentPrimary,
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                vertical: AntarcticomTheme.spacingMd,
                                horizontal: AntarcticomTheme.spacingSm,
                              ),
                              children: [
                                if (channels.textChannels.isNotEmpty) ...[
                                  _ChannelCategory(name: 'TEXT CHANNELS'),
                                  ...channels.textChannels
                                      .map((ch) => _ChannelItem(
                                            name: ch.name,
                                            icon: Icons.tag,
                                            isActive:
                                                selectedChannelId == ch.id,
                                            onTap: () => _selectChannel(ch.id),
                                          )),
                                ],
                                if (channels.voiceChannels.isNotEmpty) ...[
                                  const SizedBox(
                                      height: AntarcticomTheme.spacingMd),
                                  _ChannelCategory(name: 'VOICE CHANNELS'),
                                  ...channels.voiceChannels
                                      .map((ch) => _ChannelItem(
                                            name: ch.name,
                                            icon: Icons.volume_up,
                                            isVoice: true,
                                            isActive:
                                                selectedChannelId == ch.id,
                                            onTap: () {},
                                          )),
                                ],
                              ],
                            ),
                ),

                // User panel (bottom)
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AntarcticomTheme.spacingSm),
                  color: AntarcticomTheme.bgDeepest.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: AntarcticomTheme.accentGradient,
                          borderRadius: BorderRadius.circular(
                              AntarcticomTheme.radiusFull),
                        ),
                        child: Center(
                          child: Text(
                            user != null && user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AntarcticomTheme.spacingSm),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'User',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color: AntarcticomTheme.textPrimary,
                                      fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Online',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      fontSize: 11,
                                      color: AntarcticomTheme.online),
                            ),
                          ],
                        ),
                      ),
                      // Mic
                      IconButton(
                        icon: const Icon(Icons.mic, size: 18),
                        color: AntarcticomTheme.textSecondary,
                        onPressed: () {},
                        splashRadius: 16,
                      ),
                      // Logout
                      IconButton(
                        icon: const Icon(Icons.logout, size: 18),
                        color: AntarcticomTheme.textSecondary,
                        onPressed: () async {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) context.go('/login');
                        },
                        splashRadius: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── Main Content Area ──────────────────────────────────────
          Expanded(
            child: widget.child,
          ),
        ],
      ),
    );
  }

  void _selectServer(ServerInfo server) {
    ref.read(selectedServerIdProvider.notifier).state = server.id;
    ref.read(selectedChannelIdProvider.notifier).state = null;
    ref.read(channelsProvider.notifier).fetchChannels(server.id);
  }

  void _selectChannel(String channelId) {
    final serverId = ref.read(selectedServerIdProvider);
    if (serverId == null) return;
    ref.read(selectedChannelIdProvider.notifier).state = channelId;
    context.go('/channels/$serverId/$channelId');
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────

class _ServerIcon extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final Color? color;
  final bool isHome;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServerIcon({
    this.label,
    this.icon,
    this.color,
    this.isHome = false,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  State<_ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<_ServerIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _hovering;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AntarcticomTheme.spacingXs,
        horizontal: 12,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AntarcticomTheme.animFast,
            curve: AntarcticomTheme.animCurve,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.isHome
                  ? (isActive
                      ? AntarcticomTheme.accentPrimary
                      : AntarcticomTheme.bgTertiary)
                  : (isActive
                      ? widget.color ?? AntarcticomTheme.bgTertiary
                      : AntarcticomTheme.bgTertiary),
              borderRadius: BorderRadius.circular(
                isActive
                    ? AntarcticomTheme.radiusMd
                    : AntarcticomTheme.radiusXl,
              ),
            ),
            child: Center(
              child: widget.isHome
                  ? Icon(
                      Icons.home_rounded,
                      color: isActive
                          ? Colors.white
                          : AntarcticomTheme.textSecondary,
                      size: 24,
                    )
                  : widget.icon != null
                      ? Icon(
                          widget.icon,
                          color: AntarcticomTheme.textSecondary,
                          size: 22,
                        )
                      : Text(
                          widget.label ?? '',
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : AntarcticomTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelCategory extends StatelessWidget {
  final String name;

  const _ChannelCategory({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AntarcticomTheme.spacingSm,
        top: AntarcticomTheme.spacingXs,
        bottom: AntarcticomTheme.spacingXs,
      ),
      child: Row(
        children: [
          Icon(Icons.expand_more, size: 10, color: AntarcticomTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AntarcticomTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelItem extends StatefulWidget {
  final String name;
  final IconData icon;
  final bool isActive;
  final bool isVoice;
  final VoidCallback onTap;

  const _ChannelItem({
    required this.name,
    required this.icon,
    this.isActive = false,
    this.isVoice = false,
    required this.onTap,
  });

  @override
  State<_ChannelItem> createState() => _ChannelItemState();
}

class _ChannelItemState extends State<_ChannelItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _hovering;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AntarcticomTheme.animFast,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AntarcticomTheme.spacingSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isHighlighted
                ? AntarcticomTheme.bgHover
                    .withValues(alpha: widget.isActive ? 1.0 : 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AntarcticomTheme.radiusSm),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: isHighlighted
                    ? AntarcticomTheme.textPrimary
                    : AntarcticomTheme.textMuted,
              ),
              const SizedBox(width: AntarcticomTheme.spacingSm),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isHighlighted
                        ? AntarcticomTheme.textPrimary
                        : AntarcticomTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
