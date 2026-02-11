import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Main app shell — server list sidebar + channel list + content area.
/// This is the root layout that wraps all authenticated views.
class HomeScreen extends StatelessWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
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
                  onTap: () {},
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

                // Server list (placeholder)
                Expanded(
                  child: ListView(
                    padding:
                        const EdgeInsets.symmetric(vertical: AntarcticomTheme.spacingXs),
                    children: [
                      _ServerIcon(label: 'NC', color: AntarcticomTheme.accentPrimary, onTap: () {}),
                      _ServerIcon(label: 'GG', color: const Color(0xFF00E676), onTap: () {}),
                      _ServerIcon(label: 'DEV', color: const Color(0xFFFF6D00), onTap: () {}),
                    ],
                  ),
                ),

                // Add server button
                Padding(
                  padding: const EdgeInsets.only(bottom: AntarcticomTheme.spacingMd),
                  child: _ServerIcon(
                    icon: Icons.add,
                    onTap: () {},
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
                        color: AntarcticomTheme.bgDeepest.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Antarcticom Server',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.expand_more,
                          color: AntarcticomTheme.textSecondary, size: 18),
                    ],
                  ),
                ),

                // Channel list
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: AntarcticomTheme.spacingMd,
                      horizontal: AntarcticomTheme.spacingSm,
                    ),
                    children: [
                      _ChannelCategory(name: 'TEXT CHANNELS'),
                      _ChannelItem(
                        name: 'general',
                        icon: Icons.tag,
                        isActive: true,
                      ),
                      _ChannelItem(name: 'development', icon: Icons.tag),
                      _ChannelItem(name: 'off-topic', icon: Icons.tag),
                      const SizedBox(height: AntarcticomTheme.spacingMd),
                      _ChannelCategory(name: 'VOICE CHANNELS'),
                      _ChannelItem(
                        name: 'Lounge',
                        icon: Icons.volume_up,
                        isVoice: true,
                      ),
                      _ChannelItem(
                        name: 'Gaming',
                        icon: Icons.volume_up,
                        isVoice: true,
                      ),
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
                          borderRadius:
                              BorderRadius.circular(AntarcticomTheme.radiusFull),
                        ),
                        child: const Center(
                          child: Text(
                            'K',
                            style: TextStyle(
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
                              'koray',
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
                      // Mic / Settings
                      IconButton(
                        icon: const Icon(Icons.mic, size: 18),
                        color: AntarcticomTheme.textSecondary,
                        onPressed: () {},
                        splashRadius: 16,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: 18),
                        color: AntarcticomTheme.textSecondary,
                        onPressed: () {},
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
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────

class _ServerIcon extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final Color? color;
  final bool isHome;
  final VoidCallback onTap;

  const _ServerIcon({
    this.label,
    this.icon,
    this.color,
    this.isHome = false,
    required this.onTap,
  });

  @override
  State<_ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<_ServerIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
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
                  ? (_hovering
                      ? AntarcticomTheme.accentPrimary
                      : AntarcticomTheme.bgTertiary)
                  : (_hovering ? widget.color ?? AntarcticomTheme.bgTertiary : AntarcticomTheme.bgTertiary),
              borderRadius: BorderRadius.circular(
                _hovering ? AntarcticomTheme.radiusMd : AntarcticomTheme.radiusXl,
              ),
            ),
            child: Center(
              child: widget.isHome
                  ? Icon(
                      Icons.home_rounded,
                      color: _hovering
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
                            color: _hovering
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
          Icon(Icons.expand_more,
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

  const _ChannelItem({
    required this.name,
    required this.icon,
    this.isActive = false,
    this.isVoice = false,
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
      child: AnimatedContainer(
        duration: AntarcticomTheme.animFast,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(
          horizontal: AntarcticomTheme.spacingSm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AntarcticomTheme.bgHover.withValues(alpha: widget.isActive ? 1.0 : 0.6)
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
    );
  }
}
