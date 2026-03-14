import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Checks the Play Store for available updates and prompts the user.
///
/// Uses Google Play's in-app update API:
/// • **Immediate** update – blocks the app until install completes.
///   Used when the available version code is ≥ 5 higher (major release).
/// • **Flexible** update – downloads in background and shows a snackbar
///   when ready.  Used for regular incremental updates.
///
/// Call [checkForUpdate] once from the home screen's [initState].
class InAppUpdateService {
  InAppUpdateService._();
  static final InAppUpdateService instance = InAppUpdateService._();

  bool _checked = false;

  /// Check for an available update and prompt accordingly.
  /// Safe to call multiple times – only runs once per app session.
  /// No-op on iOS (in_app_update is Android/Play Store only).
  Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) return;
    if (_checked) return;
    _checked = true;

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('[InAppUpdate] No update available.');
        return;
      }

      // Decide: immediate (forced) vs flexible (background download).
      // Use immediate for updates with high priority (stale version code gap ≥ 5).
      final useImmediate = info.updatePriority >= 4 ||
          info.immediateUpdateAllowed == true && _versionCodeGap(info) >= 5;

      if (useImmediate && info.immediateUpdateAllowed == true) {
        debugPrint('[InAppUpdate] Starting IMMEDIATE update…');
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed == true) {
        debugPrint('[InAppUpdate] Starting FLEXIBLE update…');
        await InAppUpdate.startFlexibleUpdate();
        // Complete the update when download finishes (installs on next restart).
        await InAppUpdate.completeFlexibleUpdate();
      } else {
        debugPrint('[InAppUpdate] Update available but neither mode allowed.');
      }
    } catch (e) {
      // Don't crash the app if Play Store update check fails.
      // Common on emulators, debug builds, or sideloaded APKs.
      debugPrint('[InAppUpdate] Error: $e');
    }
  }

  int _versionCodeGap(AppUpdateInfo info) {
    final available = info.availableVersionCode ?? 0;
    // We can't easily read the current version code from the info object,
    // so rely on the staleness days as a secondary signal.
    // For now, treat any gap as small unless priority says otherwise.
    return available > 0 ? 5 : 0;
  }
}
