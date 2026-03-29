import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A callback invoked when a 401 response is received, indicating the
/// user's session has expired.
typedef SessionExpiredCallback = void Function();

/// HTTP client wrapper that detects 401 responses and fires a single
/// [onSessionExpired] callback so the app can prompt re-authentication.
///
/// Uses [http.BaseClient] so it can be injected into any service that
/// accepts an [http.Client].
class AuthAwareHttpClient extends http.BaseClient {
  AuthAwareHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Global callback triggered (at most once) when a 401 is detected.
  /// Set this from the top-level app widget.
  static SessionExpiredCallback? onSessionExpired;

  /// Guards against firing the callback multiple times when several
  /// parallel requests fail with 401 simultaneously.
  static bool _sessionExpiredFired = false;

  /// Reset the guard so the callback can fire again after re-login.
  static void reset() {
    _sessionExpiredFired = false;
  }

  /// Shared singleton so every API service gets the same instance.
  static final AuthAwareHttpClient instance = AuthAwareHttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);

    if (response.statusCode == 401 &&
        !_sessionExpiredFired &&
        onSessionExpired != null) {
      // Skip auth endpoints — a 401 there means wrong credentials, not
      // an expired session.
      final path = request.url.path;
      if (!path.endsWith('/auth/login') &&
          !path.endsWith('/auth/register') &&
          !path.endsWith('/auth/send-otp') &&
          !path.endsWith('/auth/verify-otp') &&
          !path.endsWith('/auth/register-with-otp')) {
        _sessionExpiredFired = true;
        debugPrint('[AuthAwareHttpClient] 401 detected – session expired');
        onSessionExpired!();
      }
    }

    return response;
  }

  @override
  void close() => _inner.close();
}
