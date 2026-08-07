import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/constants.dart';

/// A newer release found on GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.downloadUrl,
    required this.notes,
    required this.sizeBytes,
  });

  /// Version of the available release, e.g. "1.0.42".
  final String version;

  /// Version currently installed.
  final String currentVersion;

  /// Direct download URL of the release APK asset.
  final String downloadUrl;

  /// Release notes (may be empty).
  final String notes;

  /// APK size in bytes (0 when unknown).
  final int sizeBytes;

  String get sizeLabel => sizeBytes > 0
      ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '';
}

/// Checks GitHub Releases for a newer build and installs it.
///
/// The repo is public, so the Releases API needs no authentication. The APK is
/// downloaded into the app's external files directory and handed to Android's
/// package installer via [OpenFilex] (which ships its own FileProvider).
///
/// Updates only install over the existing app because every CI build is signed
/// with the same committed keystore — see android/app/build.gradle.kts.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest';

  /// Returns update info when a newer release exists, otherwise null.
  /// Never throws — network/parse failures resolve to null.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String current = info.version;

      final http.Response response = await _client.get(
        Uri.parse(_latestReleaseUrl),
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint('UpdateService: HTTP ${response.statusCode}');
        return null;
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String tag = (json['tag_name'] as String?) ?? '';
      final String latest = normalizeVersion(tag);
      if (latest.isEmpty) return null;
      if (!isNewer(latest, current)) return null;

      // Find the APK asset.
      final List<dynamic> assets =
          (json['assets'] as List<dynamic>?) ?? const <dynamic>[];
      for (final dynamic raw in assets) {
        final Map<String, dynamic> asset = raw as Map<String, dynamic>;
        final String name = (asset['name'] as String?) ?? '';
        if (!name.toLowerCase().endsWith('.apk')) continue;
        final String url = (asset['browser_download_url'] as String?) ?? '';
        if (url.isEmpty) continue;
        return UpdateInfo(
          version: latest,
          currentVersion: current,
          downloadUrl: url,
          notes: (json['body'] as String?)?.trim() ?? '',
          sizeBytes: (asset['size'] as num?)?.toInt() ?? 0,
        );
      }
      return null;
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate failed: $e');
      return null;
    }
  }

  /// Downloads the APK, reporting progress 0..1, then launches the system
  /// installer. Returns null on success or a human-readable error message.
  Future<String?> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final Directory? dir = await getExternalStorageDirectory();
      if (dir == null) return 'No storage available for the download.';
      final File file = File('${dir.path}/ar-synth-${update.version}.apk');

      final http.Request request =
          http.Request('GET', Uri.parse(update.downloadUrl));
      final http.StreamedResponse response = await _client.send(request);
      if (response.statusCode != 200) {
        return 'Download failed (HTTP ${response.statusCode}).';
      }

      final int total = response.contentLength ?? update.sizeBytes;
      int received = 0;
      final IOSink sink = file.openWrite();
      try {
        await for (final List<int> chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }

      final OpenResult result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        return 'Could not open the installer: ${result.message}. '
            'Allow "install unknown apps" for AR Synth and retry.';
      }
      return null;
    } catch (e) {
      return 'Update failed: $e';
    }
  }

  void dispose() => _client.close();
}

/// Strips a leading "v" and any build metadata from a release tag.
/// `v1.0.42` -> `1.0.42`; returns '' when no version-like value is found.
String normalizeVersion(String tag) {
  final RegExpMatch? m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(tag);
  return m?.group(1) ?? '';
}

/// True when [candidate] is a strictly higher version than [current].
/// Compares dot-separated numeric components, shorter versions padded with 0.
bool isNewer(String candidate, String current) {
  final List<int> a = _parts(candidate);
  final List<int> b = _parts(current);
  final int len = a.length > b.length ? a.length : b.length;
  for (int i = 0; i < len; i++) {
    final int x = i < a.length ? a[i] : 0;
    final int y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

List<int> _parts(String version) {
  final String cleaned = normalizeVersion(version);
  if (cleaned.isEmpty) return const <int>[];
  return cleaned
      .split('.')
      .map((String s) => int.tryParse(s) ?? 0)
      .toList(growable: false);
}
