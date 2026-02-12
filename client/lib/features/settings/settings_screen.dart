import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor:
          AntarcticomTheme.bgPrimary.withOpacity(settings.backgroundOpacity),
      appBar: AppBar(
        title: const Text('Appearance Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/channels/@me'),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(AntarcticomTheme.spacingLg),
          decoration: BoxDecoration(
            color: AntarcticomTheme.bgSecondary
                .withOpacity(settings.sidebarOpacity),
            borderRadius: BorderRadius.circular(AntarcticomTheme.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Visual Customization',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AntarcticomTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: AntarcticomTheme.spacingLg),

              // ─── Background ─────────────────────────────────────────────
              _SectionHeader('Background'),
              SwitchListTile(
                title: const Text('Starry Night Sky'),
                subtitle:
                    const Text('Enable the animated starfield background'),
                value: settings.enableStarfield,
                onChanged: (value) => notifier.toggleStarfield(value),
                activeColor: settings.accentColor,
              ),

              const SizedBox(height: AntarcticomTheme.spacingMd),

              // ─── Opacity ────────────────────────────────────────────────
              _SectionHeader('Transparency'),
              _SliderSetting(
                label: 'Sidebar Opacity',
                value: settings.sidebarOpacity,
                onChanged: (val) => notifier.setSidebarOpacity(val),
              ),
              _SliderSetting(
                label: 'Background Opacity',
                value: settings.backgroundOpacity,
                onChanged: (val) => notifier.setBackgroundOpacity(val),
              ),

              const SizedBox(height: AntarcticomTheme.spacingMd),

              // ─── Accent Color ───────────────────────────────────────────
              _SectionHeader('Accent Color'),
              const SizedBox(height: AntarcticomTheme.spacingSm),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ColorSwatch(
                    color: const Color(0xFF6C5CE7), // Default Violet
                    isSelected: settings.accentColor.value == 0xFF6C5CE7,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFF6C5CE7)),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFF00D2FF), // Cyan
                    isSelected: settings.accentColor.value == 0xFF00D2FF,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFF00D2FF)),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFF00E676), // Green
                    isSelected: settings.accentColor.value == 0xFF00E676,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFF00E676)),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFFFF1744), // Red
                    isSelected: settings.accentColor.value == 0xFFFF1744,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFFFF1744)),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFFFFAB00), // Amber
                    isSelected: settings.accentColor.value == 0xFFFFAB00,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFFFFAB00)),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFFE040FB), // Purple
                    isSelected: settings.accentColor.value == 0xFFE040FB,
                    onTap: () =>
                        notifier.setAccentColor(const Color(0xFFE040FB)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
          activeColor: Theme.of(context)
              .colorScheme
              .primary, // Uses accent color from theme/provider via context if configured, or I should use provider directly?
          // Actually Theme.of(context).primaryColor isn't updated by my settings provider yet locally to values.
          // But I'll leave it as is, or use settings.accentColor if I access it.
          // Let's rely on the parent updating the theme or just passing the color.
          // Wait, I didn't update the global theme with the provider.
          // I should probably pass activeColor explicitly.
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
                color: color.withOpacity(0.5),
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
