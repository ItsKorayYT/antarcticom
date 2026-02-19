import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../core/settings_provider.dart';
import '../../core/auth_provider.dart';
import '../../core/api_service.dart';
import '../home/background_manager.dart';
import '../home/rainbow_builder.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor:
          Colors.transparent, // We manage background manually below
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: BackgroundManager(
              theme: settings.backgroundTheme,
              opacity: 1.0,
            ),
          ),

          // Content
          Column(
            children: [
              AppBar(
                title: const Text('Appearance Settings'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/channels/@me');
                    }
                  },
                ),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    margin: const EdgeInsets.all(AntarcticomTheme.spacingMd),
                    padding: const EdgeInsets.all(AntarcticomTheme.spacingLg),
                    decoration: BoxDecoration(
                      color: AntarcticomTheme.bgSecondary
                          .withValues(alpha: settings.sidebarOpacity),
                      borderRadius:
                          BorderRadius.circular(AntarcticomTheme.radiusLg),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // ─── Profile & Avatar ────────────────────────────
                        _AvatarSection(ref: ref),
                        const SizedBox(height: AntarcticomTheme.spacingLg),
                        const Divider(color: AntarcticomTheme.bgTertiary),
                        const SizedBox(height: AntarcticomTheme.spacingLg),

                        Text(
                          'Visual Customization',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AntarcticomTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: AntarcticomTheme.spacingLg),

                        // ─── Theme & Background ─────────────────────────────
                        const _SectionHeader('Theme & Background'),
                        DropdownButtonFormField<AppBackgroundTheme>(
                          key: ValueKey(settings.backgroundTheme),
                          initialValue: settings.backgroundTheme,
                          decoration: const InputDecoration(
                            labelText: 'Background Theme',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.black26,
                          ),
                          dropdownColor: AntarcticomTheme.bgTertiary,
                          items: AppBackgroundTheme.values.map((theme) {
                            return DropdownMenuItem(
                              value: theme,
                              child: Text(
                                theme.name.toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              notifier.setBackgroundTheme(val);
                            }
                          },
                        ),
                        if (settings.backgroundTheme ==
                            AppBackgroundTheme.moon) ...[
                          const SizedBox(height: AntarcticomTheme.spacingMd),
                          const _SectionHeader('Moon Position'),
                          _SliderSetting(
                            label: 'Horizontal Position',
                            value: settings.moonX,
                            onChanged: (val) =>
                                notifier.setMoonPosition(val, settings.moonY),
                          ),
                          _SliderSetting(
                            label: 'Vertical Position',
                            value: settings.moonY,
                            onChanged: (val) =>
                                notifier.setMoonPosition(settings.moonX, val),
                          ),
                        ],
                        const SizedBox(height: AntarcticomTheme.spacingMd),

                        if (settings.backgroundTheme ==
                            AppBackgroundTheme.sun) ...[
                          const _SectionHeader('Sun Position'),
                          _SliderSetting(
                            label: 'Horizontal Position',
                            value: settings.sunX,
                            onChanged: (val) =>
                                notifier.setSunPosition(val, settings.sunY),
                          ),
                          _SliderSetting(
                            label: 'Vertical Position',
                            value: settings.sunY,
                            onChanged: (val) =>
                                notifier.setSunPosition(settings.sunX, val),
                          ),
                          const SizedBox(height: AntarcticomTheme.spacingMd),
                        ],

                        // ─── Animations ─────────────────────────────────────
                        if (settings.backgroundTheme ==
                                AppBackgroundTheme.sun ||
                            settings.backgroundTheme ==
                                AppBackgroundTheme.moon ||
                            settings.backgroundTheme ==
                                AppBackgroundTheme.stars)
                          const _SectionHeader('Ambient Animations'),

                        if (settings.backgroundTheme == AppBackgroundTheme.sun)
                          SwitchListTile(
                            title: const Text('Show Birds',
                                style: TextStyle(
                                    color: AntarcticomTheme.textPrimary)),
                            value: settings.showBirds,
                            onChanged: (val) => notifier.toggleBirds(val),
                          ),

                        if (settings.backgroundTheme == AppBackgroundTheme.moon)
                          SwitchListTile(
                            title: const Text('Show Owls/Crows',
                                style: TextStyle(
                                    color: AntarcticomTheme.textPrimary)),
                            value: settings.showOwls,
                            onChanged: (val) => notifier.toggleOwls(val),
                          ),

                        if (settings.backgroundTheme ==
                                AppBackgroundTheme.moon ||
                            settings.backgroundTheme ==
                                AppBackgroundTheme.stars)
                          SwitchListTile(
                            title: const Text('Show Shooting Stars',
                                style: TextStyle(
                                    color: AntarcticomTheme.textPrimary)),
                            value: settings.showShootingStars,
                            onChanged: (val) =>
                                notifier.toggleShootingStars(val),
                            activeTrackColor:
                                Theme.of(context).colorScheme.primary,
                          ),
                        if (settings.showShootingStars &&
                            (settings.backgroundTheme ==
                                    AppBackgroundTheme.moon ||
                                settings.backgroundTheme ==
                                    AppBackgroundTheme.stars))
                          _SliderSetting(
                            label: 'Frequency (Rare → Frequent)',
                            value: settings.shootingStarFrequency,
                            onChanged: (val) =>
                                notifier.setShootingStarFrequency(val),
                          ),
                        const SizedBox(height: AntarcticomTheme.spacingMd),

                        // ─── Layout ─────────────────────────────────────────
                        const _SectionHeader('Layout'),
                        DropdownButtonFormField<TaskbarPosition>(
                          key: ValueKey(settings.taskbarPosition),
                          initialValue: settings.taskbarPosition,
                          decoration: const InputDecoration(
                            labelText: 'Taskbar Position',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.black26,
                          ),
                          dropdownColor: AntarcticomTheme.bgTertiary,
                          items: TaskbarPosition.values.map((pos) {
                            return DropdownMenuItem(
                              value: pos,
                              child: Text(
                                pos.name.toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) notifier.setTaskbarPosition(val);
                          },
                        ),

                        const SizedBox(height: AntarcticomTheme.spacingMd),

                        // ─── Opacity ────────────────────────────────────────
                        const _SectionHeader('Transparency'),
                        _SliderSetting(
                          label: 'Sidebar / Taskbar Opacity',
                          value: settings.sidebarOpacity,
                          onChanged: (val) => notifier.setSidebarOpacity(val),
                        ),
                        _SliderSetting(
                          label: 'Content Background Opacity',
                          value: settings.backgroundOpacity,
                          onChanged: (val) =>
                              notifier.setBackgroundOpacity(val),
                        ),

                        const SizedBox(height: AntarcticomTheme.spacingMd),

                        // ─── Accent Color ───────────────────────────────────
                        const _SectionHeader('Accent Color'),
                        const SizedBox(height: AntarcticomTheme.spacingSm),
                        Row(
                          children: [
                            const Text('Rainbow Mode',
                                style: TextStyle(
                                    color: AntarcticomTheme.textPrimary)),
                            const Spacer(),
                            RainbowBuilder(
                                enabled: settings.rainbowMode,
                                builder: (context, color) {
                                  return Switch(
                                    value: settings.rainbowMode,
                                    onChanged: (val) =>
                                        notifier.setRainbowMode(val),
                                    activeTrackColor: color,
                                  );
                                }),
                          ],
                        ),
                        const SizedBox(height: AntarcticomTheme.spacingSm),
                        if (!settings.rainbowMode) ...[
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      Color pickerColor = settings.accentColor;
                                      return StatefulBuilder(
                                          builder: (context, setState) {
                                        return AlertDialog(
                                          title: const Text('Pick a color'),
                                          content: SingleChildScrollView(
                                            child: Column(
                                              children: [
                                                ColorPicker(
                                                  pickerColor: pickerColor,
                                                  onColorChanged: (color) {
                                                    setState(() {
                                                      pickerColor = color;
                                                    });
                                                    // Optional: Live update if performant enough,
                                                    // but user complained about lag.
                                                    // Let's commit on "Got it" for safety,
                                                    // OR debounce.
                                                    // The user said "gives no feedback when you select".
                                                    // Updating local state handles the picker UI feedback.
                                                  },
                                                  labelTypes: const [],
                                                  pickerAreaHeightPercent: 0.8,
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('Cancel'),
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                            ),
                                            TextButton(
                                              child: const Text('Select'),
                                              onPressed: () {
                                                notifier.setAccentColor(
                                                    pickerColor);
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                          ],
                                        );
                                      });
                                    },
                                  );
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: settings.accentColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.colorize,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _ColorSwatch(
                                      color: const Color(0xFF6C5CE7),
                                      isSelected:
                                          settings.accentColor.toARGB32() ==
                                              0xFF6C5CE7,
                                      onTap: () => notifier.setAccentColor(
                                          const Color(0xFF6C5CE7)),
                                    ),
                                    _ColorSwatch(
                                      color: const Color(0xFF00D2FF),
                                      isSelected:
                                          settings.accentColor.toARGB32() ==
                                              0xFF00D2FF,
                                      onTap: () => notifier.setAccentColor(
                                          const Color(0xFF00D2FF)),
                                    ),
                                    _ColorSwatch(
                                      color: const Color(0xFF00E676),
                                      isSelected:
                                          settings.accentColor.toARGB32() ==
                                              0xFF00E676,
                                      onTap: () => notifier.setAccentColor(
                                          const Color(0xFF00E676)),
                                    ),
                                    _ColorSwatch(
                                      color: const Color(0xFFFF1744),
                                      isSelected:
                                          settings.accentColor.toARGB32() ==
                                              0xFFFF1744,
                                      onTap: () => notifier.setAccentColor(
                                          const Color(0xFFFF1744)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  final WidgetRef ref;
  const _AvatarSection({required this.ref});

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final api = ref.read(apiServiceProvider);

    if (user == null) return const SizedBox.shrink();

    final hasAvatar = user.avatarHash != null && user.avatarHash!.isNotEmpty;
    final initial =
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AntarcticomTheme.textPrimary,
              ),
        ),
        const SizedBox(height: AntarcticomTheme.spacingMd),
        Row(
          children: [
            // Avatar
            GestureDetector(
              onTap: () => _pickAndUpload(context),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AntarcticomTheme.bgTertiary,
                    backgroundImage: hasAvatar
                        ? NetworkImage(api.avatarUrl(user.id, user.avatarHash!))
                        : null,
                    child: hasAvatar
                        ? null
                        : Text(initial,
                            style: const TextStyle(
                                fontSize: 28,
                                color: AntarcticomTheme.textPrimary)),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AntarcticomTheme.accentPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AntarcticomTheme.spacingMd),
            // Name / Username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: const TextStyle(
                      color: AntarcticomTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      color: AntarcticomTheme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final api = ref.read(apiServiceProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    try {
      final hash = await api.uploadAvatar(image.path);
      authNotifier.updateAvatarHash(hash);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Avatar updated!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to upload avatar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AntarcticomTheme.spacingSm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AntarcticomTheme.textSecondary,
            ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AntarcticomTheme.textPrimary)),
            Text('${(value * 100).toInt()}%',
                style: const TextStyle(color: AntarcticomTheme.textMuted)),
          ],
        ),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          onChanged: onChanged,
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}
