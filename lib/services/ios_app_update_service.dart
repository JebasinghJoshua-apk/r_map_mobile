import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/toast_message.dart';

class IosAppUpdate {
  const IosAppUpdate({required this.version, required this.storeUrl});

  final String version;
  final Uri storeUrl;
}

class IosAppUpdateService {
  IosAppUpdateService({
    http.Client? client,
    DateTime Function()? now,
    Future<bool> Function(Uri)? openStore,
  })  : _client = client,
        _now = now ?? DateTime.now,
        _openStore = openStore ??
            ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  static final instance = IosAppUpdateService();
  static const _lastCheckKey = 'ios_update_last_check';
  static const _dismissedVersionKey = 'ios_update_dismissed_version';
  static const _country =
      String.fromEnvironment('APP_STORE_COUNTRY', defaultValue: 'in');

  final http.Client? _client;
  final DateTime Function() _now;
  final Future<bool> Function(Uri) _openStore;
  bool _checking = false;
  bool _promptOpen = false;

  Future<IosAppUpdate?> checkForUpdate() async {
    if (_checking) return null;
    _checking = true;
    http.Client? client;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = _now();
      final lastCheck = prefs.getInt(_lastCheckKey);
      if (lastCheck != null) {
        final elapsed =
            now.difference(DateTime.fromMillisecondsSinceEpoch(lastCheck));
        if (!elapsed.isNegative && elapsed < const Duration(hours: 24)) {
          return null;
        }
      }

      final info = await PackageInfo.fromPlatform();
      // Throttle failed/offline requests too, including across app restarts.
      if (!await prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch)) {
        throw StateError('Could not save App Store update check time');
      }
      client = _client ?? http.Client();
      final response = await client
          .get(Uri.https('itunes.apple.com', '/lookup', {
            'bundleId': info.packageName,
            'country': _country,
          }))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw http.ClientException(
            'App Store lookup failed: HTTP ${response.statusCode}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Invalid App Store lookup response');
      }
      final results = body['results'];
      if (results is! List) {
        throw const FormatException('Invalid App Store results');
      }
      if (results.isEmpty) return null;
      for (final result in results) {
        if (result is! Map<String, dynamic> ||
            result['bundleId'] != info.packageName) {
          continue;
        }
        final version = result['version'];
        final url = result['trackViewUrl'];
        if (version is! String || url is! String) {
          throw const FormatException('Missing App Store version or URL');
        }
        if (!_isNewerVersion(version, info.version) ||
            prefs.getString(_dismissedVersionKey) == version) {
          return null;
        }
        final storeUrl = Uri.parse(url);
        if (storeUrl.scheme != 'https' || storeUrl.host != 'apps.apple.com') {
          throw const FormatException('Invalid App Store destination');
        }
        return IosAppUpdate(version: version, storeUrl: storeUrl);
      }
      throw const FormatException('App Store returned a different bundle');
    } catch (error, stack) {
      debugPrint('[AppStoreUpdate] Check failed: $error');
      debugPrintStack(stackTrace: stack);
      return null;
    } finally {
      if (_client == null) client?.close();
      _checking = false;
    }
  }

  Future<void> checkAndPrompt(BuildContext context) async {
    if (_promptOpen) return;
    final update = await checkForUpdate();
    if (update == null || !context.mounted) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      debugPrint('[AppStoreUpdate] Prompt deferred: home screen is not active');
      return;
    }

    _promptOpen = true;
    try {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'R Map ${update.version} is available on the App Store. '
            'Would you like to update?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (shouldUpdate != true) {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_dismissedVersionKey, update.version)) {
          throw StateError('Could not save dismissed App Store version');
        }
      } else {
        try {
          if (!await _openStore(update.storeUrl)) {
            throw StateError('App Store could not be opened');
          }
        } catch (error, stack) {
          debugPrint('[AppStoreUpdate] Open failed: $error');
          debugPrintStack(stackTrace: stack);
          if (context.mounted) {
            ToastMessage.show(context,
                'Unable to open the App Store. Please try again later.');
          }
        }
      }
    } catch (error, stack) {
      debugPrint('[AppStoreUpdate] Prompt failed: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      _promptOpen = false;
    }
  }

  bool _isNewerVersion(String available, String installed) {
    List<int> parts(String version) {
      final value = version.split('+').first;
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(value)) {
        throw FormatException('Invalid app version', version);
      }
      return value.split('.').map(int.parse).toList();
    }

    final availableParts = parts(available);
    final installedParts = parts(installed);
    final length = availableParts.length > installedParts.length
        ? availableParts.length
        : installedParts.length;
    for (var index = 0; index < length; index++) {
      final a = index < availableParts.length ? availableParts[index] : 0;
      final b = index < installedParts.length ? installedParts[index] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}
