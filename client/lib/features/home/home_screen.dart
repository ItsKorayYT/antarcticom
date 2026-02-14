import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/server_provider.dart';
import '../../core/channel_provider.dart';
import '../../core/settings_provider.dart';
import 'background_manager.dart';
import 'rainbow_builder.dart';

/// Main app shell — server list (taskbar) + channel list + content area.
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
    final settings = ref.watch(settingsProvider);

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

    // ─── Component Builders ─────────────────────────────────────────────

    // 1. Taskbar (Server List)
    Widget buildTaskbar({bool vertical = true}) {
      return Container(
        width: vertical ? 80 : null,
        height: vertical ? null : 64,
        color: AntarcticomTheme.bgSecondary
            .withValues(alpha: settings.sidebarOpacity),
        child: vertical
            ? Column(
                children: [
                  const SizedBox(height: AntarcticomTheme.spacingMd),
                  _buildHomeButton(selectedServerId),
                  const SizedBox(height: AntarcticomTheme.spacingSm),
                  _buildDivider(vertical: true),
                  const SizedBox(height: AntarcticomTheme.spacingSm),
                  Expanded(child: _buildServerList(servers, selectedServerId)),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: AntarcticomTheme.spacingMd),
                  _buildHomeButton(selectedServerId),
                  const SizedBox(width: AntarcticomTheme.spacingSm),
                  _buildDivider(vertical: false),
                  const SizedBox(width: AntarcticomTheme.spacingSm),
                  Expanded(
                    child: _buildServerList(servers, selectedServerId,
                        vertical: false),
                  ),
                ],
              ),
      );
    }

    // 2. Sidebar (Channel List)
    Widget buildSidebar() {
      return Container(
        width: 240,
        color: AntarcticomTheme.bgSecondary
            .withValues(alpha: settings.sidebarOpacity),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(
                  horizontal: AntarcticomTheme.spacingMd),
              // decoration: BoxDecoration(
              //   border: Border(
              //     bottom: BorderSide(
              //       color: AntarcticomTheme.bgDeepest.withOpacity(0.5),
              //     ),
              //   ),
              // ),
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
            // List
            Expanded(
              child: _buildChannelListContent(
                  servers, selectedServerId, channels, selectedChannelId),
            ),
            // User Panel
            _buildUserPanel(user, context, settings),
          ],
        ),
      );
    }

    // 3. Main Content
    Widget buildContent() {
      return Expanded(
        child: Container(
          color: AntarcticomTheme.bgPrimary
              .withValues(alpha: settings.backgroundOpacity),
          child: widget.child,
        ),
      );
    }

    // ─── Layout Logic ───────────────────────────────────────────────────

    Widget layout;
    final taskbar = buildTaskbar(
        vertical: settings.taskbarPosition == TaskbarPosition.left ||
            settings.taskbarPosition == TaskbarPosition.right);
    final sidebar = buildSidebar();
    final content = buildContent();

    switch (settings.taskbarPosition) {
      case TaskbarPosition.bottom:
        layout = Column(
          children: [
            Expanded(
              child: Row(
                children: [sidebar, content],
              ),
            ),
            taskbar,
          ],
        );
        break;
      case TaskbarPosition.top:
        layout = Column(
          children: [
            taskbar,
            Expanded(
              child: Row(
                children: [sidebar, content],
              ),
            ),
          ],
        );
        break;
      case TaskbarPosition.right:
        layout = Row(
          children: [
            sidebar,
            content,
            taskbar,
          ],
        );
        break;
      case TaskbarPosition.left:
        layout = Row(
          children: [
            taskbar,
            sidebar,
            content,
          ],
        );
        break;
    }

    return Scaffold(
      backgroundColor: AntarcticomTheme.bgDeepest,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: BackgroundManager(
              theme: settings.backgroundTheme,
              opacity: 1.0,
            ),
          ),

          // Layout
          Positioned.fill(child: layout),
        ],
      ),
    );
  }

  // ─── Sub-builders ─────────────────────────────────────────────────────

  Widget _buildHomeButton(String? selectedServerId) {
    return _ServerIcon(
      isHome: true,
      isSelected: selectedServerId == null,
      onTap: () {
        ref.read(selectedServerIdProvider.notifier).state = null;
        ref.read(channelsProvider.notifier).clear();
        ref.read(selectedChannelIdProvider.notifier).state = null;
        context.go('/channels/@me');
      },
    );
  }

  Widget _buildDivider({required bool vertical}) {
    return Container(
      width: vertical ? 32 : 2,
      height: vertical ? 2 : 32,
      decoration: BoxDecoration(
        color: AntarcticomTheme.bgTertiary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildServerList(ServersState servers, String? selectedServerId,
      {bool vertical = true}) {
    if (servers.isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AntarcticomTheme.accentPrimary,
          ),
        ),
      );
    }
    return ListView(
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      padding: const EdgeInsets.all(AntarcticomTheme.spacingXs),
      children: servers.servers.map((server) {
        return _ServerIcon(
          label: server.initials,
          color: Theme.of(context).primaryColor,
          isSelected: selectedServerId == server.id,
          onTap: () => _selectServer(server),
        );
      }).toList(),
    );
  }

  Widget _buildChannelListContent(
      ServersState servers,
      String? selectedServerId,
      ChannelsState channels,
      String? selectedChannelId) {
    if (selectedServerId == null) {
      return _buildWelcomeState(servers);
    }
    if (channels.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AntarcticomTheme.accentPrimary),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(
        vertical: AntarcticomTheme.spacingMd,
        horizontal: AntarcticomTheme.spacingSm,
      ),
      children: [
        if (channels.textChannels.isNotEmpty) ...[
          const _ChannelCategory(name: 'TEXT CHANNELS'),
          ...channels.textChannels.map((ch) => _ChannelItem(
                name: ch.name,
                icon: Icons.tag,
                isActive: selectedChannelId == ch.id,
                onTap: () => _selectChannel(ch.id),
              )),
        ],
        if (channels.voiceChannels.isNotEmpty) ...[
          const SizedBox(height: AntarcticomTheme.spacingMd),
          const _ChannelCategory(name: 'VOICE CHANNELS'),
          ...channels.voiceChannels.map((ch) => _ChannelItem(
                name: ch.name,
                icon: Icons.volume_up,
                isVoice: true,
                isActive: selectedChannelId == ch.id,
                onTap: () {},
              )),
        ],
      ],
    );
  }

  Widget _buildWelcomeState(ServersState servers) {
    // Show "Select a server" + Online People

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.explore,
            size: 64,
            color: AntarcticomTheme.bgTertiary,
          ),
          const SizedBox(height: AntarcticomTheme.spacingMd),
          Text(
            servers.servers.isEmpty
                ? 'Create or join a server to get started!'
                : 'Select a server or direct message from the taskbar',
            style: const TextStyle(
                color: AntarcticomTheme.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUserPanel(
      UserInfo? user, BuildContext context, AppSettings settings) {
    return Container(
      height: 52,
      padding:
          const EdgeInsets.symmetric(horizontal: AntarcticomTheme.spacingSm),
      color: AntarcticomTheme.bgSecondary
          .withValues(alpha: settings.sidebarOpacity),
      child: Row(
        children: [
          RainbowBuilder(
              enabled: settings.rainbowMode,
              builder: (context, color) {
                return Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: settings.rainbowMode
                        ? LinearGradient(
                            colors: [color, color.withValues(alpha: 0.7)])
                        : AntarcticomTheme.accentGradient,
                    borderRadius:
                        BorderRadius.circular(AntarcticomTheme.radiusFull),
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
                );
              }),
          const SizedBox(width: AntarcticomTheme.spacingSm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'User',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AntarcticomTheme.textPrimary,
                    shadows: const [
                      Shadow(
                        color: Color(0xCC000000),
                        offset: Offset(0, 1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AntarcticomTheme.bgTertiary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings, size: 16),
              color: AntarcticomTheme.textSecondary,
              padding: EdgeInsets.zero,
              onPressed: () {
                context.push('/settings');
              },
              splashRadius: 16,
              tooltip: 'Settings',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AntarcticomTheme.bgTertiary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.logout, size: 16),
              color: AntarcticomTheme.textSecondary,
              padding: EdgeInsets.zero,
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              splashRadius: 16,
            ),
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

// ─── Helpers ────────────────────────────────────────────────────────────

class _ServerIcon extends StatefulWidget {
  final String? label;
  final Color? color;
  final bool isHome;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServerIcon({
    this.label,
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

    // If it's a home icon or it has a custom color (which usually comes from Theme.primary)
    // we might want rainbow.
    // The server icon generally uses `Theme.of(context).primaryColor` passed in from parent.
    // Let's ignore the passed color if rainbow is on, logic handled in builder.

    // We need access to settings to know if enabled.
    // Ideally pass `isRainbowEnabled` to `_ServerIcon`.
    // For now, let's use Consumer in `_ServerIcon` or just wrap the usage in `HomeScreen`.
    // Wrapping usage in `HomeScreen` is cleaner but `_ServerIcon` is where the color is used.
    // Let's Refactor `_ServerIcon` to be a ConsumerWidget or read settings.
    return Consumer(builder: (context, ref, _) {
      final settings = ref.watch(settingsProvider);
      return RainbowBuilder(
        enabled: settings.rainbowMode,
        builder: (context, rainbowColor) {
          final effectiveColor =
              settings.rainbowMode && (widget.isHome || widget.color != null)
                  ? rainbowColor
                  : (widget.color ?? AntarcticomTheme.bgTertiary);

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
                            ? effectiveColor
                            : AntarcticomTheme.bgTertiary)
                        : (isActive
                            ? effectiveColor
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
        },
      );
    });
  }
}

// (Reused Channel Helpers)
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
          const Icon(Icons.expand_more,
              size: 10, color: AntarcticomTheme.textMuted),
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
