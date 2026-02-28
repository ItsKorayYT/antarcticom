import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// Service that checks GitHub Releases for newer versions of Antarcticom.
class UpdateService {
  static const String _currentVersion = '0.1.0';
  static const String _repo = 'ItsKorayYT/antarcticom';
  static const String _releasesApi =
      'https://api.github.com/repos/$_repo/releases/latest';
  static const String _releasesPage =
      'https://github.com/$_repo/releases/latest';

  /// Returns the current app version string.
  static String get currentVersion => _currentVersion;

  /// Check for updates and show a dialog if a newer version is available.
  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        _releasesApi,
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200) return;

      final data = response.data;
      final latestTag = (data['tag_name'] as String?) ?? '';
      final latestVersion = latestTag.replaceFirst(RegExp(r'^v'), '');
      final releaseName = (data['name'] as String?) ?? latestTag;

      // Find the installer download URL from release assets
      String downloadUrl = _releasesPage;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.startsWith('AntarcticomSetup') && name.endsWith('.exe')) {
          downloadUrl = asset['browser_download_url'] as String;
          break;
        }
      }

      if (_isNewerVersion(latestVersion, _currentVersion)) {
        if (!context.mounted) return;
        _showUpdateDialog(context, latestVersion, releaseName, downloadUrl);
      }
    } catch (e) {
      // Silently fail — don't bother users if the check fails
      debugPrint('Update check failed: $e');
    }
  }

  /// Compare two semver strings. Returns true if [remote] > [local].
  static bool _isNewerVersion(String remote, String local) {
    final remoteParts =
        remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final localParts =
        local.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to same length
    while (remoteParts.length < 3) {
      remoteParts.add(0);
    }
    while (localParts.length < 3) {
      localParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > localParts[i]) return true;
      if (remoteParts[i] < localParts[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String releaseName,
    String downloadUrl,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.system_update,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text(
              'Update Available',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              releaseName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A new version ($version) is available.\nYou are currently on v$_currentVersion.',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _launchUrl(downloadUrl);
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  /// Opens a URL in the default browser using the Windows shell.
  static Future<void> _launchUrl(String url) async {
    try {
      // Use dart:io Process to open the URL in the default browser
      // This avoids adding url_launcher as a dependency
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (e) {
      debugPrint('Failed to open URL: $e');
    }
  }
}
