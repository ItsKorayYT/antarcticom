import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

enum TaskbarPosition { left, right, top, bottom }

enum AppBackgroundTheme {
  stars,
  sun,
  moon,
  field,
  liquidDark,
  liquidLight,
  liquidCustom
}

class AppSettings {
  final double sidebarOpacity;
  final double backgroundOpacity;
  final Color accentColor;
  final Color liquidCustomColor;
  final bool enableStarfield; // Kept for legacy compatibility check
  final double starDensity;
  final TaskbarPosition taskbarPosition;
  final AppBackgroundTheme backgroundTheme;
  final AppUiTheme uiTheme;

  const AppSettings({
    this.sidebarOpacity = 0.85,
    this.backgroundOpacity = 0.5,
    this.accentColor = const Color(0xFF6C5CE7),
    this.liquidCustomColor = const Color(0xFF14B8A6), // Default Teal Tint
    this.enableStarfield = true,
    this.starDensity = 0.5,
    this.taskbarPosition = TaskbarPosition.bottom,
    this.backgroundTheme = AppBackgroundTheme.stars,
    this.uiTheme = AppUiTheme.defaultDark,
    this.rainbowMode = false,
    this.moonX = 0.8,
    this.moonY = 0.2,
    this.sunX = 0.8,
    this.sunY = 0.2,
    this.showBirds = true,
    this.showOwls = true,
    this.showShootingStars = false,
    this.shootingStarFrequency = 0.5,
    this.selectedInputDeviceId,
    this.selectedOutputDeviceId,
    this.enableNoiseSuppression = true,
    this.enableEchoCancellation = true,
  });

  final bool rainbowMode;
  final double moonX;
  final double moonY;
  final double sunX;
  final double sunY;
  final bool showBirds;
  final bool showOwls;
  final bool showShootingStars;
  final double shootingStarFrequency; // 0.0 (Rare) to 1.0 (Frequent)
  final String? selectedInputDeviceId;
  final String? selectedOutputDeviceId;
  final bool enableNoiseSuppression;
  final bool enableEchoCancellation;

  AppSettings copyWith({
    double? sidebarOpacity,
    double? backgroundOpacity,
    Color? accentColor,
    Color? liquidCustomColor,
    bool? enableStarfield,
    double? starDensity,
    TaskbarPosition? taskbarPosition,
    AppBackgroundTheme? backgroundTheme,
    AppUiTheme? uiTheme,
    bool? rainbowMode,
    double? moonX,
    double? moonY,
    double? sunX,
    double? sunY,
    bool? showBirds,
    bool? showOwls,
    bool? showShootingStars,
    double? shootingStarFrequency,
    String? selectedInputDeviceId,
    String? selectedOutputDeviceId,
    bool? enableNoiseSuppression,
    bool? enableEchoCancellation,
  }) {
    return AppSettings(
      sidebarOpacity: sidebarOpacity ?? this.sidebarOpacity,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      accentColor: accentColor ?? this.accentColor,
      liquidCustomColor: liquidCustomColor ?? this.liquidCustomColor,
      enableStarfield: enableStarfield ?? this.enableStarfield,
      starDensity: starDensity ?? this.starDensity,
      taskbarPosition: taskbarPosition ?? this.taskbarPosition,
      backgroundTheme: backgroundTheme ?? this.backgroundTheme,
      uiTheme: uiTheme ?? this.uiTheme,
      rainbowMode: rainbowMode ?? this.rainbowMode,
      moonX: moonX ?? this.moonX,
      moonY: moonY ?? this.moonY,
      sunX: sunX ?? this.sunX,
      sunY: sunY ?? this.sunY,
      showBirds: showBirds ?? this.showBirds,
      showOwls: showOwls ?? this.showOwls,
      showShootingStars: showShootingStars ?? this.showShootingStars,
      shootingStarFrequency:
          shootingStarFrequency ?? this.shootingStarFrequency,
      selectedInputDeviceId:
          selectedInputDeviceId ?? this.selectedInputDeviceId,
      selectedOutputDeviceId:
          selectedOutputDeviceId ?? this.selectedOutputDeviceId,
      enableNoiseSuppression:
          enableNoiseSuppression ?? this.enableNoiseSuppression,
      enableEchoCancellation:
          enableEchoCancellation ?? this.enableEchoCancellation,
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
  static const _keyLiquidCustomColor = 'liquid_custom_color';
  static const _keyStarfield = 'enable_starfield';
  static const _keyTaskbarPos = 'taskbar_pos';
  static const _keyBgTheme = 'bg_theme';
  static const _keyUiTheme = 'ui_theme'; // New key for UI theme
  static const _keyRainbow = 'rainbow_mode';
  static const _keyMoonX = 'moon_x';
  static const _keyMoonY = 'moon_y';
  static const _keySunX = 'sun_x';
  static const _keySunY = 'sun_y';
  static const _keyShowBirds = 'show_birds';
  static const _keyShowOwls = 'show_owls';
  static const _keyShowShootingStars = 'show_shooting_stars';
  static const _keyShootingStarFreq = 'shooting_star_freq';
  static const _keyInputDeviceId = 'input_device_id';
  static const _keyOutputDeviceId = 'output_device_id';

  Future<void> setUiTheme(AppUiTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUiTheme, theme.index);

    AppBackgroundTheme newBg = state.backgroundTheme;
    if (theme == AppUiTheme.liquidGlass) {
      if (newBg != AppBackgroundTheme.liquidDark &&
          newBg != AppBackgroundTheme.liquidLight &&
          newBg != AppBackgroundTheme.liquidCustom) {
        newBg = AppBackgroundTheme.liquidDark;
      }
    } else {
      if (newBg == AppBackgroundTheme.liquidDark ||
          newBg == AppBackgroundTheme.liquidLight ||
          newBg == AppBackgroundTheme.liquidCustom) {
        newBg = AppBackgroundTheme.stars;
      }
    }

    state = state.copyWith(uiTheme: theme, backgroundTheme: newBg);
    await prefs.setInt(_keyBgTheme, newBg.index);
  }

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

  Future<void> setShootingStarFrequency(double value) async {
    state = state.copyWith(shootingStarFrequency: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyShootingStarFreq, value);
  }

  Future<void> setInputDevice(String? id) async {
    state = state.copyWith(selectedInputDeviceId: id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyInputDeviceId);
    } else {
      await prefs.setString(_keyInputDeviceId, id);
    }
  }

  Future<void> setOutputDevice(String? id) async {
    state = state.copyWith(selectedOutputDeviceId: id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyOutputDeviceId);
    } else {
      await prefs.setString(_keyOutputDeviceId, id);
    }
  }

  Future<void> toggleNoiseSuppression(bool value) async {
    state = state.copyWith(enableNoiseSuppression: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_noise_suppression', value);
  }

  Future<void> toggleEchoCancellation(bool value) async {
    state = state.copyWith(enableEchoCancellation: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_echo_cancellation', value);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final sidebarOpacity = prefs.getDouble(_keySidebarOpacity) ?? 0.85;
    final bgOpacity = prefs.getDouble(_keyBgOpacity) ?? 0.5;
    final starfield = prefs.getBool(_keyStarfield) ?? true;
    final accentValue = prefs.getInt(_keyAccentColor);
    final liquidCustomValue = prefs.getInt(_keyLiquidCustomColor);

    final taskbarIndex =
        prefs.getInt(_keyTaskbarPos) ?? TaskbarPosition.bottom.index;
    final backgroundThemeIndex =
        prefs.getInt(_keyBgTheme) ?? AppBackgroundTheme.stars.index;
    final uiThemeIndex =
        prefs.getInt(_keyUiTheme) ?? AppUiTheme.defaultDark.index;

    final rainbow = prefs.getBool(_keyRainbow) ?? false;
    final mX = prefs.getDouble(_keyMoonX) ?? 0.8;
    final mY = prefs.getDouble(_keyMoonY) ?? 0.2;
    final sX = prefs.getDouble(_keySunX) ?? 0.8;
    final sY = prefs.getDouble(_keySunY) ?? 0.2;
    final birds = prefs.getBool(_keyShowBirds) ?? true;
    final owls = prefs.getBool(_keyShowOwls) ?? true;
    final stars = prefs.getBool(_keyShowShootingStars) ?? false;
    final starFreq = prefs.getDouble(_keyShootingStarFreq) ?? 0.5;
    final inputId = prefs.getString(_keyInputDeviceId);
    final outputId = prefs.getString(_keyOutputDeviceId);
    final noiseSuppression = prefs.getBool('enable_noise_suppression') ?? true;
    final echoCancellation = prefs.getBool('enable_echo_cancellation') ?? true;

    final TaskbarPosition loadedPosition;
    if (taskbarIndex >= 0 && taskbarIndex < TaskbarPosition.values.length) {
      loadedPosition = TaskbarPosition.values[taskbarIndex];
    } else {
      loadedPosition = TaskbarPosition.bottom;
    }

    final AppBackgroundTheme loadedBgTheme;
    if (backgroundThemeIndex >= 0 &&
        backgroundThemeIndex < AppBackgroundTheme.values.length) {
      loadedBgTheme = AppBackgroundTheme.values[backgroundThemeIndex];
    } else {
      loadedBgTheme = AppBackgroundTheme.stars;
    }

    final AppUiTheme loadedUiTheme;
    if (uiThemeIndex >= 0 && uiThemeIndex < AppUiTheme.values.length) {
      loadedUiTheme = AppUiTheme.values[uiThemeIndex];
    } else {
      loadedUiTheme = AppUiTheme.defaultDark;
    }

    state = AppSettings(
      sidebarOpacity: sidebarOpacity,
      backgroundOpacity: bgOpacity,
      enableStarfield: starfield,
      accentColor:
          accentValue != null ? Color(accentValue) : const Color(0xFF6C5CE7),
      liquidCustomColor: liquidCustomValue != null
          ? Color(liquidCustomValue)
          : const Color(0xFF14B8A6),
      taskbarPosition: loadedPosition,
      backgroundTheme: loadedBgTheme,
      uiTheme: loadedUiTheme,
      rainbowMode: rainbow,
      moonX: mX,
      moonY: mY,
      sunX: sX,
      sunY: sY,
      showBirds: birds,
      showOwls: owls,
      showShootingStars: stars,
      shootingStarFrequency: starFreq,
      selectedInputDeviceId: inputId,
      selectedOutputDeviceId: outputId,
      enableNoiseSuppression: noiseSuppression,
      enableEchoCancellation: echoCancellation,
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
    await prefs.setInt(_keyAccentColor, value.toARGB32());
  }

  Future<void> setLiquidCustomColor(Color value) async {
    state = state.copyWith(liquidCustomColor: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLiquidCustomColor, value.toARGB32());
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

  // ────────────────────────────────────────────────────────
  // Theming & Appearance Methods
  // ────────────────────────────────────────────────────────

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
