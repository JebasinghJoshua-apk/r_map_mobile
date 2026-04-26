import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A callback invoked when a 401 response is received, indicating the
/// user's session has expired.
typedef SessionExpiredCallback = void Function();
typedef RefreshSessionCallback = Future<bool> Function();
typedef AccessTokenProvider = String? Function();

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

  /// Global callback used to silently refresh the access token once.
  static RefreshSessionCallback? onRefreshSession;

  /// Access token provider used to attach the newly refreshed token.
  static AccessTokenProvider? accessTokenProvider;

  /// Guards against firing the callback multiple times when several
  /// parallel requests fail with 401 simultaneously.
  static bool _sessionExpiredFired = false;
  static Future<bool>? _refreshInFlight;

  /// Reset the guard so the callback can fire again after re-login.
  static void reset() {
    _sessionExpiredFired = false;
    _refreshInFlight = null;
  }

  static Future<bool> refreshSessionIfPossible() => _refreshOnce();

  static String? currentAccessToken() => accessTokenProvider?.call();

  /// Shared singleton so every API service gets the same instance.
  static final AuthAwareHttpClient instance = AuthAwareHttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final retryRequest = _cloneRequest(request);
    final response = await _inner.send(request);

    if (response.statusCode != 401 || _isAuthEndpoint(request.url.path)) {
      return response;
    }

    if (retryRequest != null) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        final latestToken = accessTokenProvider?.call()?.trim();
        if (latestToken != null && latestToken.isNotEmpty) {
          retryRequest.headers['Authorization'] =
              'Bearer ${_normalizeToken(latestToken)}';
        }

        final retriedResponse = await _inner.send(retryRequest);
        if (retriedResponse.statusCode != 401) {
          return retriedResponse;
        }
      }
    }

    if (!_sessionExpiredFired && onSessionExpired != null) {
      _sessionExpiredFired = true;
      debugPrint('[AuthAwareHttpClient] 401 detected – session expired');
      onSessionExpired!();
    }

    return response;
  }

  @override
  void close() => _inner.close();

  static bool _isAuthEndpoint(String path) {
    return path.endsWith('/auth/login') ||
        path.endsWith('/auth/register') ||
        path.endsWith('/auth/otp/send') ||
        path.endsWith('/auth/otp/verify') ||
        path.endsWith('/auth/otp/register') ||
        path.endsWith('/auth/refresh');
  }

  static String _normalizeToken(String token) {
    return token.toLowerCase().startsWith('bearer ')
        ? token.substring('bearer '.length)
        : token;
  }

  static http.BaseRequest? _cloneRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final clone = http.Request(request.method, request.url)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;
      clone.headers.addAll(request.headers);
      return clone;
    }

    return null;
  }

  static Future<bool> _refreshOnce() {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }

    final callback = onRefreshSession;
    if (callback == null) {
      return Future.value(false);
    }

    _refreshInFlight = () async {
      try {
        return await callback();
      } catch (_) {
        return false;
      } finally {
        _refreshInFlight = null;
      }
    }();

    return _refreshInFlight!;
  }
}
