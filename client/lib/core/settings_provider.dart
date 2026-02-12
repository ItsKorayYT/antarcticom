import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

enum TaskbarPosition { left, right, top, bottom }

enum AppBackgroundTheme { stars, sun, moon, field }

class AppSettings {
  final double sidebarOpacity;
  final double backgroundOpacity;
  final Color accentColor;
  final bool enableStarfield; // Kept for legacy compatibility check
  final double starDensity;
  final TaskbarPosition taskbarPosition;
  final AppBackgroundTheme backgroundTheme;

  const AppSettings({
    this.sidebarOpacity = 0.85,
    this.backgroundOpacity = 0.5,
    this.accentColor = AntarcticomTheme.accentPrimary,
    this.enableStarfield = true,
    this.starDensity = 0.5,
    this.taskbarPosition = TaskbarPosition.bottom,
    this.backgroundTheme = AppBackgroundTheme.stars,
    this.rainbowMode = false,
    this.moonX = 0.8,
    this.moonY = 0.2,
    this.sunX = 0.8,
    this.sunY = 0.2,
    this.showBirds = true,
    this.showOwls = true,
    this.showShootingStars = true,
  });

  final bool rainbowMode;
  final double moonX;
  final double moonY;
  final double sunX;
  final double sunY;
  final bool showBirds;
  final bool showOwls;
  final bool showShootingStars;

  AppSettings copyWith({
    double? sidebarOpacity,
    double? backgroundOpacity,
    Color? accentColor,
    bool? enableStarfield,
    double? starDensity,
    TaskbarPosition? taskbarPosition,
    AppBackgroundTheme? backgroundTheme,
    bool? rainbowMode,
    double? moonX,
    double? moonY,
    double? sunX,
    double? sunY,
    bool? showBirds,
    bool? showOwls,
    bool? showShootingStars,
  }) {
    return AppSettings(
      sidebarOpacity: sidebarOpacity ?? this.sidebarOpacity,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      accentColor: accentColor ?? this.accentColor,
      enableStarfield: enableStarfield ?? this.enableStarfield,
      starDensity: starDensity ?? this.starDensity,
      taskbarPosition: taskbarPosition ?? this.taskbarPosition,
      backgroundTheme: backgroundTheme ?? this.backgroundTheme,
      rainbowMode: rainbowMode ?? this.rainbowMode,
      moonX: moonX ?? this.moonX,
      moonY: moonY ?? this.moonY,
      sunX: sunX ?? this.sunX,
      sunY: sunY ?? this.sunY,
      showBirds: showBirds ?? this.showBirds,
      showOwls: showOwls ?? this.showOwls,
      showShootingStars: showShootingStars ?? this.showShootingStars,
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
  static const _keyTaskbarPos = 'taskbar_pos';
  static const _keyBgTheme = 'bg_theme';
  static const _keyRainbow = 'rainbow_mode';
  static const _keyMoonX = 'moon_x';
  static const _keyMoonY = 'moon_y';
  static const _keySunX = 'sun_x';
  static const _keySunY = 'sun_y';
  static const _keyShowBirds = 'show_birds';
  static const _keyShowOwls = 'show_owls';
  static const _keyShowShootingStars = 'show_shooting_stars';

  Future<void> setMoonPosition(double x, double y) async {
    state = state.copyWith(moonX: x, moonY: y);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMoonX, x);
    await prefs.setDouble(_keyMoonY, y);
  }

  Future<void> setSunPosition(double x, double y) async {
    state = state.copyWith(sunX: x, sunY: y);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySunX, x);
    await prefs.setDouble(_keySunY, y);
  }

  Future<void> toggleBirds(bool value) async {
    state = state.copyWith(showBirds: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowBirds, value);
  }

  Future<void> toggleOwls(bool value) async {
    state = state.copyWith(showOwls: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowOwls, value);
  }

  Future<void> toggleShootingStars(bool value) async {
    state = state.copyWith(showShootingStars: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowShootingStars, value);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sidebarOpacity = prefs.getDouble(_keySidebarOpacity) ?? 0.85;
    final bgOpacity = prefs.getDouble(_keyBgOpacity) ?? 0.5;
    final starfield = prefs.getBool(_keyStarfield) ?? true;
    final accentValue = prefs.getInt(_keyAccentColor);

    final taskbarIndex =
        prefs.getInt(_keyTaskbarPos) ?? TaskbarPosition.bottom.index;
    final themeIndex =
        prefs.getInt(_keyBgTheme) ?? AppBackgroundTheme.stars.index;
    final rainbow = prefs.getBool(_keyRainbow) ?? false;
    final mX = prefs.getDouble(_keyMoonX) ?? 0.8;
    final mY = prefs.getDouble(_keyMoonY) ?? 0.2;
    final sX = prefs.getDouble(_keySunX) ?? 0.8;
    final sY = prefs.getDouble(_keySunY) ?? 0.2;
    final birds = prefs.getBool(_keyShowBirds) ?? true;
    final owls = prefs.getBool(_keyShowOwls) ?? true;
    final stars = prefs.getBool(_keyShowShootingStars) ?? true;

    state = AppSettings(
      sidebarOpacity: sidebarOpacity,
      backgroundOpacity: bgOpacity,
      enableStarfield: starfield,
      accentColor: accentValue != null
          ? Color(accentValue)
          : AntarcticomTheme.accentPrimary,
      taskbarPosition:
          TaskbarPosition.values[taskbarIndex % TaskbarPosition.values.length],
      backgroundTheme: AppBackgroundTheme
          .values[themeIndex % AppBackgroundTheme.values.length],
      rainbowMode: rainbow,
      moonX: mX,
      moonY: mY,
      sunX: sX,
      sunY: sY,
      showBirds: birds,
      showOwls: owls,
      showShootingStars: stars,
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
    final newTheme =
        value ? AppBackgroundTheme.stars : AppBackgroundTheme.field;
    state = state.copyWith(enableStarfield: value, backgroundTheme: newTheme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStarfield, value);
    await prefs.setInt(_keyBgTheme, newTheme.index);
  }

  Future<void> setTaskbarPosition(TaskbarPosition position) async {
    state = state.copyWith(taskbarPosition: position);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTaskbarPos, position.index);
  }

  Future<void> setBackgroundTheme(AppBackgroundTheme theme) async {
    final isStars = theme == AppBackgroundTheme.stars;
    state = state.copyWith(backgroundTheme: theme, enableStarfield: isStars);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBgTheme, theme.index);
    await prefs.setBool(_keyStarfield, isStars);
  }

  Future<void> setRainbowMode(bool value) async {
    state = state.copyWith(rainbowMode: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRainbow, value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
