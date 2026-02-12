import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

class AppSettings {
  final double sidebarOpacity;
  final double backgroundOpacity;
  final Color accentColor;
  final bool enableStarfield;
  final double starDensity;

  const AppSettings({
    this.sidebarOpacity = 0.85,
    this.backgroundOpacity = 0.5,
    this.accentColor = AntarcticomTheme.accentPrimary,
    this.enableStarfield = true,
    this.starDensity = 0.5,
  });

  AppSettings copyWith({
    double? sidebarOpacity,
    double? backgroundOpacity,
    Color? accentColor,
    bool? enableStarfield,
    double? starDensity,
  }) {
    return AppSettings(
      sidebarOpacity: sidebarOpacity ?? this.sidebarOpacity,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      accentColor: accentColor ?? this.accentColor,
      enableStarfield: enableStarfield ?? this.enableStarfield,
      starDensity: starDensity ?? this.starDensity,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadSettings();
  }

  static const _keySidebarOpacity = 'sidebar_opacity';
  static const _keyBgOpacity = 'bg_opacity';
  static const _keyAccentColor = 'accent_color';
  static const _keyStarfield = 'enable_starfield';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sidebarOpacity = prefs.getDouble(_keySidebarOpacity) ?? 0.85;
    final bgOpacity = prefs.getDouble(_keyBgOpacity) ?? 0.5;
    final starfield = prefs.getBool(_keyStarfield) ?? true;
    final accentValue = prefs.getInt(_keyAccentColor);

    state = AppSettings(
      sidebarOpacity: sidebarOpacity,
      backgroundOpacity: bgOpacity,
      enableStarfield: starfield,
      accentColor: accentValue != null
          ? Color(accentValue)
          : AntarcticomTheme.accentPrimary,
    );
  }

  Future<void> setSidebarOpacity(double value) async {
    state = state.copyWith(sidebarOpacity: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySidebarOpacity, value);
  }

  Future<void> setBackgroundOpacity(double value) async {
    state = state.copyWith(backgroundOpacity: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBgOpacity, value);
  }

  Future<void> setAccentColor(Color value) async {
    state = state.copyWith(accentColor: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccentColor, value.value);
  }

  Future<void> toggleStarfield(bool value) async {
    state = state.copyWith(enableStarfield: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStarfield, value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
