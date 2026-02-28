import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/server_provider.dart';
import '../../core/connection_manager.dart';
import '../../core/channel_provider.dart';
import '../../core/voice_provider.dart';
import '../../core/settings_provider.dart';
import '../../core/api_service.dart';
import 'background_manager.dart';
import 'rainbow_builder.dart';
import '../../core/member_provider.dart';
import '../../core/models/permissions.dart';
import '../settings/roles_screen.dart';
import '../../core/models/user.dart';
import 'member_list.dart';

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
    final theme = ref.watch(themeProvider);

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

    // Handle kicking / leaving the currently selected server
    ref.listen<ServersState>(serversProvider, (previous, next) {
      if (!next.isLoading && selectedServerId != null) {
        final serverExists = next.servers.any((s) => s.id == selectedServerId);
        if (!serverExists) {
          Future.microtask(() {
            if (!mounted) return;
            ref.read(selectedServerIdProvider.notifier).state = null;
            ref.read(channelsProvider.notifier).clear();
            ref.read(selectedChannelIdProvider.notifier).state = null;
            if (context.mounted) {
              context.go('/channels/@me');
            }
          });
        }
      }
    });

    // ─── Component Builders ─────────────────────────────────────────────

    // 1. Taskbar (Server List)
    Widget buildTaskbar({bool vertical = true}) {
      return Container(
        width: vertical ? 80 : null,
        height: vertical ? null : 64,
        color: theme.bgSecondary.withValues(alpha: settings.sidebarOpacity),
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
        color: theme.bgSecondary.withValues(alpha: settings.sidebarOpacity),
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
              //       color: theme.bgDeepest.withOpacity(0.5),
              //     ),
              //   ),
              // ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
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
                  if (selectedServerId != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final perms =
                            ref.watch(permissionsProvider(selectedServerId));
                        final canManageServer =
                            perms.has(Permissions.manageServer);
                        final auth = ref.watch(authProvider);
                        final server = ref
                            .watch(serversProvider)
                            .servers
                            .where((s) => s.id == selectedServerId)
                            .firstOrNull;
                        final isOwner =
                            server != null && server.ownerId == auth.user?.id;

                        return PopupMenuButton<String>(
                          icon:
                              Icon(Icons.expand_more, color: theme.textPrimary),
                          onSelected: (value) async {
                            if (value == 'roles') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RolesScreen(serverId: selectedServerId),
                                ),
                              );
                            } else if (value == 'leave') {
                              try {
                                // Close the popup
                                final api = ref.read(apiServiceProvider);
                                // The api service might not be the right one if it's a community server
                                // Let's use the current connection manager
                                final host = ref
                                    .read(serversProvider)
                                    .servers
                                    .where((s) => s.id == selectedServerId)
                                    .firstOrNull
                                    ?.hostUrl;
                                final effectiveApi = host != null
                                    ? ref
                                            .read(connectionManagerProvider)
                                            .getApiForHost(host) ??
                                        api
                                    : api;

                                // Actually, leave server endpoint is not exposed in ApiService yet!
                                // Wait, let's just make a raw DIO call or add it to ApiService.
                                // I will add it to ApiService next.
                                await effectiveApi
                                    .leaveServer(selectedServerId);

                                // Deselect the server
                                ref
                                    .read(selectedServerIdProvider.notifier)
                                    .state = null;
                                ref.read(channelsProvider.notifier).clear();
                                ref
                                    .read(selectedChannelIdProvider.notifier)
                                    .state = null;

                                // Refresh servers list
                                ref
                                    .read(serversProvider.notifier)
                                    .fetchServers();

                                if (context.mounted) {
                                  context.go('/channels/@me');
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Failed to leave server: $e')),
                                  );
                                }
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            if (canManageServer)
                              const PopupMenuItem(
                                value: 'roles',
                                child: Text('Server Roles'),
                              ),
                            if (!isOwner)
                              const PopupMenuItem(
                                value: 'leave',
                                child: Text('Leave Server',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            // List
            Expanded(
              child: _buildChannelListContent(
                  servers, selectedServerId, channels, selectedChannelId),
            ),
            // Voice status panel
            _buildVoiceStatusPanel(),
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
          color: theme.bgPrimary.withValues(alpha: settings.backgroundOpacity),
          child: widget.child,
        ),
      );
    }

    // 4. Member List (Right Sidebar)
    Widget buildMemberList() {
      if (selectedServerId == null) return const SizedBox();

      // Toggle logic could go here (e.g. only show if button pressed)
      // For now, always show on desktop if server selected
      return MemberList(serverId: selectedServerId);
    }

    // ─── Layout Logic ───────────────────────────────────────────────────

    Widget layout;
    final taskbar = buildTaskbar(
        vertical: settings.taskbarPosition == TaskbarPosition.left ||
            settings.taskbarPosition == TaskbarPosition.right);
    final sidebar = buildSidebar();
    final content = buildContent();
    final memberList = buildMemberList();

    switch (settings.taskbarPosition) {
      case TaskbarPosition.bottom:
        layout = Column(
          children: [
            Expanded(
              child: Row(
                children: [sidebar, content, memberList],
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
                children: [sidebar, content, memberList],
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
            memberList,
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
            memberList,
          ],
        );
        break;
    }

    return Scaffold(
      backgroundColor: theme.bgDeepest,
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
    final theme = ref.watch(themeProvider);
    return Container(
      width: vertical ? 32 : 2,
      height: vertical ? 2 : 32,
      decoration: BoxDecoration(
        color: theme.bgTertiary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildServerList(ServersState servers, String? selectedServerId,
      {bool vertical = true}) {
    final theme = ref.watch(themeProvider);
    if (servers.isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.accentPrimary,
          ),
        ),
      );
    }
    return ListView(
      scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
      padding: const EdgeInsets.all(AntarcticomTheme.spacingXs),
      children: [
        ...servers.servers.map((server) {
          return _ServerIcon(
            label: server.initials,
            color: Theme.of(context).primaryColor,
            isSelected: selectedServerId == server.id,
            onTap: () => _selectServer(server),
          );
        }),
        // "Add Server" button
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: vertical ? 4 : 0,
            horizontal: vertical ? 0 : 4,
          ),
          child: Tooltip(
            message: 'Add a community server',
            child: GestureDetector(
              onTap: () => _showAddServerDialog(context),
              child: Container(
                width: vertical ? 56 : 48,
                height: vertical ? 56 : 48,
                decoration: BoxDecoration(
                  color: theme.bgTertiary,
                  borderRadius: BorderRadius.circular(vertical ? 16 : 12),
                  border: Border.all(
                    color: theme.accentPrimary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.add,
                    color: theme.accentPrimary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelListContent(
      ServersState servers,
      String? selectedServerId,
      ChannelsState channels,
      String? selectedChannelId) {
    final theme = ref.watch(themeProvider);
    if (selectedServerId == null) {
      return _buildWelcomeState(servers);
    }
    if (channels.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: theme.accentPrimary),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(
        vertical: AntarcticomTheme.spacingMd,
        horizontal: AntarcticomTheme.spacingSm,
      ),
      children: [
        _ChannelCategory(
          name: 'TEXT CHANNELS',
          onAdd: () => _showCreateChannelDialog(context, selectedServerId),
          serverId: selectedServerId,
        ),
        ...channels.textChannels.map((ch) => _ChannelItem(
              name: ch.name,
              icon: Icons.tag,
              isActive: selectedChannelId == ch.id,
              onTap: () => _selectChannel(ch.id),
              onDelete: () => _showDeleteChannelDialog(
                  context, selectedServerId, ch.id, ch.name),
            )),
        const SizedBox(height: AntarcticomTheme.spacingMd),
        _ChannelCategory(
          name: 'VOICE CHANNELS',
          onAdd: () => _showCreateChannelDialog(context, selectedServerId,
              isVoice: true),
          serverId: selectedServerId,
        ),
        ...channels.voiceChannels.expand((ch) {
          final voiceState = ref.watch(voiceProvider);
          final isInChannel = voiceState.currentChannelId == ch.id;
          final participants = voiceState.participantsFor(ch.id);
          return [
            _ChannelItem(
              name: ch.name,
              icon: Icons.volume_up,
              isVoice: true,
              isActive: isInChannel,
              onTap: () => ref.read(voiceProvider.notifier).joinChannel(ch.id),
              onDelete: () => _showDeleteChannelDialog(
                  context, selectedServerId, ch.id, ch.name),
            ),
            // Show participants when channel has users
            ...participants.map((p) => Padding(
                  padding: const EdgeInsets.only(left: 28.0, top: 1, bottom: 1),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 14,
                        color: theme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.displayName ?? p.userId.substring(0, 8),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (p.muted)
                        const Icon(Icons.mic_off,
                            size: 12, color: Colors.redAccent),
                      if (p.deafened)
                        const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(Icons.headset_off,
                              size: 12, color: Colors.redAccent),
                        ),
                    ],
                  ),
                )),
          ];
        }),
      ],
    );
  }

  Widget _buildWelcomeState(ServersState servers) {
    // Show "Select a server" + Online People
    final theme = ref.watch(themeProvider);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore,
            size: 64,
            color: theme.bgTertiary,
          ),
          const SizedBox(height: AntarcticomTheme.spacingMd),
          Text(
            servers.servers.isEmpty
                ? 'Create or join a server to get started!'
                : 'Select a server or direct message from the taskbar',
            style: TextStyle(color: theme.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceStatusPanel() {
    final theme = ref.watch(themeProvider);
    final voiceState = ref.watch(voiceProvider);
    if (voiceState.currentChannelId == null) {
      return const SizedBox.shrink();
    }

    // Try to find the channel name from channels state
    final channels = ref.watch(channelsProvider);
    final channelName = channels.voiceChannels
            .where((ch) => ch.id == voiceState.currentChannelId)
            .map((ch) => ch.name)
            .firstOrNull ??
        'Voice Channel';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AntarcticomTheme.spacingSm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        border: Border(
          top: BorderSide(
            color: theme.accentPrimary.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Voice Connected" or "Connecting..."
          Row(
            children: [
              Icon(
                  voiceState.isConnecting
                      ? Icons.signal_cellular_alt_1_bar
                      : Icons.signal_cellular_alt,
                  size: 14,
                  color: voiceState.isConnecting
                      ? Colors.orangeAccent
                      : theme.online),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  voiceState.isConnecting
                      ? 'Voice Connecting...'
                      : 'Voice Connected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: voiceState.isConnecting
                        ? Colors.orangeAccent
                        : theme.online,
                  ),
                ),
              ),
            ],
          ),
          // Channel name
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              channelName,
              style: TextStyle(
                fontSize: 11,
                color: theme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          // Controls: mute, deafen, disconnect
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _VoiceControlButton(
                icon: voiceState.muted ? Icons.mic_off : Icons.mic,
                isActive: voiceState.muted,
                onTap: () => ref.read(voiceProvider.notifier).toggleMute(),
                tooltip: voiceState.muted ? 'Unmute' : 'Mute',
              ),
              const SizedBox(width: 8),
              _VoiceControlButton(
                icon: voiceState.deafened ? Icons.headset_off : Icons.headset,
                isActive: voiceState.deafened,
                onTap: () => ref.read(voiceProvider.notifier).toggleDeafen(),
                tooltip: voiceState.deafened ? 'Undeafen' : 'Deafen',
              ),
              const SizedBox(width: 8),
              _VoiceControlButton(
                icon: Icons.call_end,
                isActive: true,
                activeColor: Colors.redAccent,
                onTap: () => ref.read(voiceProvider.notifier).leaveChannel(),
                tooltip: 'Disconnect',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserPanel(
      User? user, BuildContext context, AppSettings settings) {
    final theme = ref.watch(themeProvider);
    return Container(
      height: 52,
      padding:
          const EdgeInsets.symmetric(horizontal: AntarcticomTheme.spacingSm),
      color: theme.bgSecondary.withValues(alpha: settings.sidebarOpacity),
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
                        : theme.accentGradient,
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
                    color: theme.textPrimary,
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
            decoration: BoxDecoration(
              color: theme.bgTertiary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings, size: 16),
              color: theme.textSecondary,
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
            decoration: BoxDecoration(
              color: theme.bgTertiary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.logout, size: 16),
              color: theme.textSecondary,
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

  void _showCreateChannelDialog(BuildContext context, String serverId,
      {bool isVoice = false}) {
    final perms = ref.read(permissionsProvider(serverId));
    if (!perms.has(Permissions.manageChannels)) return;

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isVoice ? 'Create Voice Channel' : 'Create Text Channel'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Channel Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await ref.read(channelsProvider.notifier).createChannel(
                    serverId, controller.text, isVoice ? 'voice' : 'text');
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteChannelDialog(BuildContext context, String serverId,
      String channelId, String channelName) {
    final perms = ref.read(permissionsProvider(serverId));
    if (!perms.has(Permissions.manageChannels)) return;
    final theme = ref.read(themeProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.bgSecondary,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text('Delete Channel #$channelName',
                    style: const TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final api = ref.read(apiServiceProvider);
                    await api.deleteChannel(serverId, channelId);

                    if (ref.read(selectedChannelIdProvider) == channelId) {
                      ref.read(selectedChannelIdProvider.notifier).state = null;
                      if (context.mounted) {
                        context.go('/channels/$serverId');
                      }
                    }

                    // Refresh channels
                    ref.read(channelsProvider.notifier).fetchChannels(serverId);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Failed to delete channel')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Add Server Dialog ──────────────────────────────────────────────

  void _showAddServerDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;
    bool isLoading = false;
    final theme = ref.read(themeProvider);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: theme.bgSecondary,
          title: Text('Add Community Server',
              style: TextStyle(color: theme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the IP address or domain of a community server.',
                style: TextStyle(color: theme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: theme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. myserver.com',
                  hintStyle: TextStyle(color: theme.textSecondary),
                  errorText: errorText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: theme.bgPrimary,
                ),
                onSubmitted: (_) {},
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('Cancel', style: TextStyle(color: theme.textSecondary)),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final url = controller.text.trim();
                      if (url.isEmpty) {
                        setDialogState(
                            () => errorText = 'Please enter a server address');
                        return;
                      }
                      setDialogState(() {
                        isLoading = true;
                        errorText = null;
                      });
                      try {
                        final connMgr = ref.read(connectionManagerProvider);
                        await connMgr.addServer(url);
                        // Refresh the server list
                        ref.read(serversProvider.notifier).fetchServers();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                          errorText =
                              e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: theme.accentPrimary,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
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
      final theme = ref.watch(themeProvider);
      return RainbowBuilder(
        enabled: settings.rainbowMode,
        builder: (context, rainbowColor) {
          final effectiveColor =
              settings.rainbowMode && (widget.isHome || widget.color != null)
                  ? rainbowColor
                  : (widget.color ?? theme.bgTertiary);

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
                        ? (isActive ? effectiveColor : theme.bgTertiary)
                        : (isActive ? effectiveColor : theme.bgTertiary),
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
                            color:
                                isActive ? Colors.white : theme.textSecondary,
                            size: 24,
                          )
                        : Text(
                            widget.label ?? '',
                            style: TextStyle(
                              color:
                                  isActive ? Colors.white : theme.textPrimary,
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
// (Reused Channel Helpers)
class _ChannelCategory extends ConsumerWidget {
  final String name;
  final VoidCallback? onAdd;
  final String? serverId;

  const _ChannelCategory({required this.name, this.onAdd, this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    bool canAdd = false;
    if (serverId != null) {
      final perms = ref.watch(permissionsProvider(serverId!));
      canAdd = perms.has(Permissions.manageChannels);
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: AntarcticomTheme.spacingSm,
        top: AntarcticomTheme.spacingXs,
        bottom: AntarcticomTheme.spacingXs,
      ),
      child: Row(
        children: [
          Icon(Icons.expand_more, size: 10, color: theme.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (canAdd && onAdd != null)
            InkWell(
              onTap: onAdd,
              child: Icon(Icons.add, size: 14, color: theme.textPrimary),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ChannelItem extends ConsumerStatefulWidget {
  final String name;
  final IconData icon;
  final bool isActive;
  final bool isVoice;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ChannelItem({
    required this.name,
    required this.icon,
    this.isActive = false,
    this.isVoice = false,
    required this.onTap,
    this.onDelete,
  });
  @override
  ConsumerState<_ChannelItem> createState() => _ChannelItemState();
}

class _ChannelItemState extends ConsumerState<_ChannelItem> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _hovering;
    final theme = ref.watch(themeProvider);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onDelete,
        onSecondaryTap: widget.onDelete,
        child: AnimatedContainer(
          duration: AntarcticomTheme.animFast,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AntarcticomTheme.spacingSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isHighlighted
                ? theme.bgHover.withValues(alpha: widget.isActive ? 1.0 : 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AntarcticomTheme.radiusSm),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: isHighlighted ? theme.textPrimary : theme.textMuted,
              ),
              const SizedBox(width: AntarcticomTheme.spacingSm),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isHighlighted ? theme.textPrimary : theme.textSecondary,
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

// ─── Voice Control Button ───────────────────────────────────────────────

class _VoiceControlButton extends ConsumerWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;
  final Color activeColor;

  const _VoiceControlButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.tooltip,
    this.activeColor = Colors.redAccent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AntarcticomTheme.radiusFull),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color:
                isActive ? activeColor.withValues(alpha: 0.2) : theme.bgPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? activeColor : theme.textSecondary,
          ),
        ),
      ),
    );
  }
}
