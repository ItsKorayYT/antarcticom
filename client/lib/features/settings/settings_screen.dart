import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:crop_image/crop_image.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/theme.dart';
import '../../core/settings_provider.dart';
import '../../core/auth_provider.dart';
import '../../core/api_service.dart';
import '../home/background_manager.dart';
import '../home/rainbow_builder.dart';

enum SettingsCategory {
  profile('My Profile', Icons.person),
  appearance('Appearance & UI', Icons.palette),
  voice('Voice & Audio', Icons.mic),
  advanced('Advanced', Icons.settings);

  final String label;
  final IconData icon;
  const SettingsCategory(this.label, this.icon);
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  SettingsCategory _selectedCategory = SettingsCategory.profile;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: BackgroundManager(
              theme: settings.backgroundTheme,
              opacity: 1.0,
            ),
          ),

          // Outer Glass Layer
          Positioned.fill(
            child: Row(
              children: [
                // ─── MASTER SIDEBAR ───
                _buildSidebar(settings.sidebarOpacity, theme),

                // ─── DETAIL CONTENT ───
                Expanded(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 24),
                          child: Row(
                            children: [
                              Text(
                                _selectedCategory.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white54, size: 28),
                                onPressed: () {
                                  if (context.canPop()) {
                                    context.pop();
                                  } else {
                                    context.go('/channels/@me');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        // Content Area
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.02, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _buildCategoryView(_selectedCategory),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(double opacity, AppThemeData theme) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.bgSecondary.withValues(alpha: opacity),
        border: const Border(
          right: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: SettingsCategory.values.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.accentPrimary.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? theme.accentPrimary.withValues(alpha: 0.3)
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          leading: Icon(
                            cat.icon,
                            color: isSelected
                                ? theme.accentPrimary
                                : Colors.white54,
                          ),
                          title: Text(
                            cat.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedCategory = cat;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryView(SettingsCategory category) {
    switch (category) {
      case SettingsCategory.profile:
        return const _ProfileView(key: ValueKey('profile'));
      case SettingsCategory.appearance:
        return const _AppearanceView(key: ValueKey('appearance'));
      case SettingsCategory.voice:
        return const _VoiceView(key: ValueKey('voice'));
      case SettingsCategory.advanced:
        return const _AdvancedView(key: ValueKey('advanced'));
    }
  }
}

// ─── SHARED UI COMPONENTS ───────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 0),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget trailing;

  const _SettingRow({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(width: 24),
          trailing,
        ],
      ),
    );

    return content;
  }
}

// ─── VIEWS ──────────────────────────────────────────────────────────────────

class _ProfileView extends ConsumerWidget {
  const _ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final api = ref.read(apiServiceProvider);
    final theme = ref.watch(themeProvider);

    if (user == null) return const Center(child: CircularProgressIndicator());

    final hasAvatar = user.avatarHash != null && user.avatarHash!.isNotEmpty;
    final initial =
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        _GlassCard(
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _pickAndUpload(context, ref),
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.bgTertiary,
                        image: hasAvatar
                            ? DecorationImage(
                                image: NetworkImage(
                                    api.avatarUrl(user.id, user.avatarHash!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: hasAvatar
                          ? null
                          : Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                    fontSize: 36,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.accentPrimary,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: theme.bgSecondary, width: 3),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                          color: theme.accentPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'User ID: ${user.id}',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiServiceProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    if (!context.mounted) return;

    final imageBytes = await image.readAsBytes();
    if (!context.mounted) return;

    final croppedBytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CropAvatarDialog(
          imageBytes: imageBytes, theme: ref.read(themeProvider)),
    );

    if (croppedBytes == null) return;

    try {
      final hash = await api.uploadAvatar(croppedBytes, 'avatar.png');
      authNotifier.updateAvatarHash(hash);
      if (context.mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Avatar updated!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

class _AppearanceView extends ConsumerWidget {
  const _AppearanceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = ref.watch(themeProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme & Ambience',
                  style: TextStyle(
                      color: theme.accentPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const SizedBox(height: 16),
              const Text('Application Theme',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<AppUiTheme>(
                  groupValue: settings.uiTheme,
                  thumbColor: theme.accentPrimary,
                  backgroundColor: Colors.black45,
                  children: const {
                    AppUiTheme.defaultDark: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Default Dark',
                            style: TextStyle(color: Colors.white))),
                    AppUiTheme.liquidGlass: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Liquid Glass',
                            style: TextStyle(color: Colors.white))),
                  },
                  onValueChanged: (val) {
                    if (val != null) notifier.setUiTheme(val);
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Text('Background Environment',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<AppBackgroundTheme>(
                  groupValue: settings.backgroundTheme,
                  thumbColor: theme.accentPrimary,
                  backgroundColor: Colors.black45,
                  children: const {
                    AppBackgroundTheme.stars: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Deep Space',
                            style: TextStyle(color: Colors.white))),
                    AppBackgroundTheme.sun: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Sunset',
                            style: TextStyle(color: Colors.white))),
                    AppBackgroundTheme.moon: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Night Moon',
                            style: TextStyle(color: Colors.white))),
                    AppBackgroundTheme.field: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Starfield',
                            style: TextStyle(color: Colors.white))),
                  },
                  onValueChanged: (val) {
                    if (val != null) notifier.setBackgroundTheme(val);
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              if (settings.backgroundTheme == AppBackgroundTheme.sun ||
                  settings.backgroundTheme == AppBackgroundTheme.moon ||
                  settings.backgroundTheme == AppBackgroundTheme.stars) ...[
                if (settings.backgroundTheme == AppBackgroundTheme.sun)
                  _SettingRow(
                    title: 'Show Birds',
                    subtitle: 'Flock of birds flying across the sunset',
                    trailing: CupertinoSwitch(
                      activeTrackColor: theme.accentPrimary,
                      value: settings.showBirds,
                      onChanged: (val) => notifier.toggleBirds(val),
                    ),
                  ),
                if (settings.backgroundTheme == AppBackgroundTheme.moon)
                  _SettingRow(
                    title: 'Show Night Birds',
                    subtitle: 'Silhouettes of owls or crows in the moonlight',
                    trailing: CupertinoSwitch(
                      activeTrackColor: theme.accentPrimary,
                      value: settings.showOwls,
                      onChanged: (val) => notifier.toggleOwls(val),
                    ),
                  ),
                if (settings.backgroundTheme == AppBackgroundTheme.moon ||
                    settings.backgroundTheme == AppBackgroundTheme.stars) ...[
                  _SettingRow(
                    title: 'Show Shooting Stars',
                    subtitle: 'Random streaks across the night sky',
                    trailing: CupertinoSwitch(
                      activeTrackColor: theme.accentPrimary,
                      value: settings.showShootingStars,
                      onChanged: (val) => notifier.toggleShootingStars(val),
                    ),
                  ),
                  if (settings.showShootingStars)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Row(
                        children: [
                          const Text('Rare',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: settings.shootingStarFrequency,
                              min: 0.0,
                              max: 1.0,
                              activeColor: theme.accentPrimary,
                              onChanged: (val) =>
                                  notifier.setShootingStarFrequency(val),
                            ),
                          ),
                          const Text('Frequent',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Colors',
                  style: TextStyle(
                      color: theme.accentPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const SizedBox(height: 16),
              _SettingRow(
                title: 'Rainbow Mode',
                subtitle: 'Automatically cycles through all accent colors',
                trailing: RainbowBuilder(
                    enabled: settings.rainbowMode,
                    builder: (context, color) {
                      return CupertinoSwitch(
                        activeTrackColor: color,
                        value: settings.rainbowMode,
                        onChanged: (val) => notifier.setRainbowMode(val),
                      );
                    }),
              ),
              if (!settings.rainbowMode) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _ColorSwatch(
                        color: const Color(0xFF6C5CE7),
                        isSelected:
                            settings.accentColor.toARGB32() == 0xFF6C5CE7,
                        onTap: () =>
                            notifier.setAccentColor(const Color(0xFF6C5CE7))),
                    _ColorSwatch(
                        color: const Color(0xFF00D2FF),
                        isSelected:
                            settings.accentColor.toARGB32() == 0xFF00D2FF,
                        onTap: () =>
                            notifier.setAccentColor(const Color(0xFF00D2FF))),
                    _ColorSwatch(
                        color: const Color(0xFF00E676),
                        isSelected:
                            settings.accentColor.toARGB32() == 0xFF00E676,
                        onTap: () =>
                            notifier.setAccentColor(const Color(0xFF00E676))),
                    _ColorSwatch(
                        color: const Color(0xFFFF1744),
                        isSelected:
                            settings.accentColor.toARGB32() == 0xFFFF1744,
                        onTap: () =>
                            notifier.setAccentColor(const Color(0xFFFF1744))),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                            context: context,
                            builder: (context) {
                              Color pickerColor = settings.accentColor;
                              return StatefulBuilder(
                                  builder: (context, setState) {
                                return AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E1E),
                                  title: const Text('Custom Color',
                                      style: TextStyle(color: Colors.white)),
                                  content: SingleChildScrollView(
                                    child: ColorPicker(
                                      pickerColor: pickerColor,
                                      onColorChanged: (c) =>
                                          setState(() => pickerColor = c),
                                      labelTypes: const [],
                                      pickerAreaHeightPercent: 0.8,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                        child: const Text('Cancel',
                                            style: TextStyle(
                                                color: Colors.white54)),
                                        onPressed: () =>
                                            Navigator.of(context).pop()),
                                    TextButton(
                                        child: Text('Select',
                                            style: TextStyle(
                                                color: theme.accentPrimary)),
                                        onPressed: () {
                                          notifier.setAccentColor(pickerColor);
                                          Navigator.of(context).pop();
                                        }),
                                  ],
                                );
                              });
                            });
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                        ),
                        child: const Icon(Icons.colorize,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceView extends ConsumerWidget {
  const _VoiceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = ref.watch(themeProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio Processing',
                  style: TextStyle(
                      color: theme.accentPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const SizedBox(height: 16),
              _SettingRow(
                title: 'Noise Suppression',
                subtitle:
                    'Filter out background noise like typing and fans using WebRTC',
                trailing: CupertinoSwitch(
                  activeTrackColor: theme.accentPrimary,
                  value: settings.enableNoiseSuppression,
                  onChanged: (val) => notifier.toggleNoiseSuppression(val),
                ),
              ),
              const Divider(color: Colors.white12),
              _SettingRow(
                title: 'Echo Cancellation',
                subtitle:
                    'Prevent your microphone from picking up speakers output',
                trailing: CupertinoSwitch(
                  activeTrackColor: theme.accentPrimary,
                  value: settings.enableEchoCancellation,
                  onChanged: (val) => notifier.toggleEchoCancellation(val),
                ),
              ),
            ],
          ),
        ),
        const _AudioDeviceSelectorsCard(),
      ],
    );
  }
}

class _AdvancedView extends ConsumerWidget {
  const _AdvancedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = ref.watch(themeProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Layout Overrides',
                  style: TextStyle(
                      color: theme.accentPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const SizedBox(height: 16),
              const Text('Taskbar Position',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<TaskbarPosition>(
                  groupValue: settings.taskbarPosition,
                  thumbColor: theme.accentPrimary,
                  backgroundColor: Colors.black45,
                  children: const {
                    TaskbarPosition.bottom: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Bottom',
                            style: TextStyle(color: Colors.white))),
                    TaskbarPosition.top: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child:
                            Text('Top', style: TextStyle(color: Colors.white))),
                    TaskbarPosition.left: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Left',
                            style: TextStyle(color: Colors.white))),
                    TaskbarPosition.right: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Right',
                            style: TextStyle(color: Colors.white))),
                  },
                  onValueChanged: (val) {
                    if (val != null) notifier.setTaskbarPosition(val);
                  },
                ),
              ),
              const SizedBox(height: 32),
              const Text('Translucency',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('Sidebar',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.sidebarOpacity,
                      min: 0.0,
                      max: 1.0,
                      activeColor: theme.accentPrimary,
                      onChanged: (val) => notifier.setSidebarOpacity(val),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 80,
                    child: Text('Content',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.backgroundOpacity,
                      min: 0.0,
                      max: 1.0,
                      activeColor: theme.accentPrimary,
                      onChanged: (val) => notifier.setBackgroundOpacity(val),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── AUDIO DEVICES CARD ─────────────────────────────────────────────────────

class _AudioDeviceSelectorsCard extends ConsumerStatefulWidget {
  const _AudioDeviceSelectorsCard();

  @override
  ConsumerState<_AudioDeviceSelectorsCard> createState() =>
      _AudioDeviceSelectorsCardState();
}

class _AudioDeviceSelectorsCardState
    extends ConsumerState<_AudioDeviceSelectorsCard> {
  List<MediaDeviceInfo> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)));
    }

    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final inputs = _devices.where((d) => d.kind == 'audioinput').toList();
    final outputs = _devices.where((d) => d.kind == 'audiooutput').toList();

    return _GlassCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hardware Devices',
            style: TextStyle(
                color: Color(0xFF6C5CE7),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1)),
        const SizedBox(height: 24),
        const Text('Input Source',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 8),
        _DeviceDropdown(
          value: settings.selectedInputDeviceId,
          items: inputs,
          defaultText: 'Default Microphone',
          onChanged: (val) => notifier.setInputDevice(val),
        ),
        const SizedBox(height: 24),
        const Text('Output Destination',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 8),
        _DeviceDropdown(
          value: settings.selectedOutputDeviceId,
          items: outputs,
          defaultText: 'System Default Output',
          onChanged: (val) => notifier.setOutputDevice(val),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadDevices,
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
            label: const Text('Refresh Devices',
                style: TextStyle(color: Colors.white54)),
          ),
        ),
      ],
    ));
  }
}

class _DeviceDropdown extends StatelessWidget {
  final String? value;
  final List<MediaDeviceInfo> items;
  final String defaultText;
  final ValueChanged<String?> onChanged;

  const _DeviceDropdown({
    required this.value,
    required this.items,
    required this.defaultText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E1E),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(defaultText,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            ...items.map((d) => DropdownMenuItem(
                  value: d.deviceId,
                  child: Text(
                      d.label.isNotEmpty ? d.label : 'Device (${d.deviceId})'),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── UTILS ──────────────────────────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch(
      {required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: [
            if (isSelected)
              BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 4),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 28)
            : null,
      ),
    );
  }
}

class _CropAvatarDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final AppThemeData theme;
  const _CropAvatarDialog({required this.imageBytes, required this.theme});
  @override
  State<_CropAvatarDialog> createState() => _CropAvatarDialogState();
}

class _CropAvatarDialogState extends State<_CropAvatarDialog> {
  final _controller = CropController(aspectRatio: 1.0);
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Crop Avatar', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        height: 400,
        child: CropImage(
          controller: _controller,
          image: Image.memory(widget.imageBytes),
          paddingSize: 20,
          alwaysMove: true,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54))),
        TextButton(
          onPressed: () async {
            final ui.Image bitmap = await _controller.croppedBitmap();
            final ByteData? data =
                await bitmap.toByteData(format: ui.ImageByteFormat.png);
            if (data != null && context.mounted) {
              Navigator.of(context).pop(data.buffer.asUint8List());
            } else if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child:
              Text('Crop', style: TextStyle(color: widget.theme.accentPrimary)),
        ),
      ],
    );
  }
}
