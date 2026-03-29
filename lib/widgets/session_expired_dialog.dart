import 'package:flutter/material.dart';

/// A dialog shown when the user's session has expired (server returned 401).
/// Prompts the user to log in again.
class SessionExpiredDialog {
  static bool _showing = false;

  /// Show the session-expired dialog. Only one instance is shown at a time.
  static Future<void> show(BuildContext context) async {
    if (_showing) return;
    _showing = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text(
          'Your session has expired. Please log in again to continue.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _showing = false;
  }
}
