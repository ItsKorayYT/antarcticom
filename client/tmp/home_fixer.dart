import 'dart:io';

void main() {
  final file = File(
      r'c:\Users\koray\Desktop\Newcord\client\lib\features\home\home_screen.dart');
  var content = file.readAsStringSync();

  final props = [
    'bgDeepest',
    'bgPrimary',
    'bgSecondary',
    'bgTertiary',
    'bgHover',
    'accentPrimary',
    'accentSecondary',
    'accentGradient',
    'online',
    'idle',
    'dnd',
    'offline',
    'textPrimary',
    'textSecondary',
    'textMuted',
    'danger',
    'dividerColor'
  ];

  for (final p in props) {
    // 1. Remove const from Icon, TextStyle, EdgeInsets anywhere close to the usage
    content = content.replaceAllMapped(
        RegExp('const\\s+TextStyle\\([^)]*?AntarcticomTheme\\.$p'),
        (m) => m.group(0)!.replaceFirst('const ', ''));
    content = content.replaceAllMapped(
        RegExp('const\\s+Icon\\([^)]*?AntarcticomTheme\\.$p'),
        (m) => m.group(0)!.replaceFirst('const ', ''));
    content = content.replaceAllMapped(
        RegExp('const\\s+BoxDecoration\\([^)]*?AntarcticomTheme\\.$p'),
        (m) => m.group(0)!.replaceFirst('const ', ''));
    content = content.replaceAllMapped(
        RegExp('const\\s+LinearGradient\\([^)]*?AntarcticomTheme\\.$p'),
        (m) => m.group(0)!.replaceFirst('const ', ''));

    // Let's just do a simpler pass to remove const:
    // This removes 'const ' before 'WidgetName(' if inside that Widget's argument list, AntarcticomTheme.$p is used
    content = content.replaceAllMapped(
        RegExp(r'const\s+([A-Z][a-zA-Z0-9_]*)\(([^)]*?)AntarcticomTheme\.' +
            p +
            r'([^)]*?)\)'),
        (m) => '${m.group(1)}(${m.group(2)}theme.$p${m.group(3)})');
    content = content.replaceAllMapped(
        RegExp(r'const\s+([A-Z][a-zA-Z0-9_]*)\(([^)]*?)theme\.' +
            p +
            r'([^)]*?)\)'),
        (m) => '${m.group(1)}(${m.group(2)}theme.$p${m.group(3)})');
    // Replace remaining usages
    content = content.replaceAll('AntarcticomTheme.$p', 'theme.$p');
  }

  file.writeAsStringSync(content);
}
