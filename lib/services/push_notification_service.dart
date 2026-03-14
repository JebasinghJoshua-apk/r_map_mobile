import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

/// Handles FCM token registration, permission requests, and incoming
/// push notifications. Designed as a singleton initialised once at app start.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Currently known FCM token (null until initialised).
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Callback invoked when a notification tap should navigate somewhere.
  /// The map contains the `data` payload from the FCM message.
  void Function(Map<String, dynamic> data)? onNotificationTap;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  // ── Public API ────────────────────────────────────────────────────

  /// Call once from main.dart after Firebase.initializeApp().
  Future<void> initialize() async {
    // Request permission (Android 13+ requires runtime permission).
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[Push] permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[Push] User denied notification permission');
      return;
    }

    // Listen for token refreshes.
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[Push] FCM token refreshed');
      _fcmToken = newToken;
      // Re-register with server if we have an auth token.
      _onTokenRefresh?.call(newToken);
    });

    // Handle messages while the app is in the foreground.
    _foregroundSub =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when the app is opened from background.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if the app was opened from a terminated state via notification.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay slightly so the NavigatorState is ready.
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationTap(initialMessage);
      });
    }

    try {
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint(
            '[Push] APNS token not available yet; skipping FCM token fetch.',
          );
          return;
        }
      }

      _fcmToken = await _messaging.getToken();
      debugPrint('[Push] FCM token: ${_fcmToken?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[Push] Unable to fetch FCM token: $e');
    }
  }

  /// Register FCM token + location with the backend.
  /// Call after login / on app resume.
  Future<void> registerDevice({
    required String authToken,
    double? latitude,
    double? longitude,
  }) async {
    if (_fcmToken == null) return;

    final uri = _bffUri('/mobile/devices/register');
    final bodyMap = {
      'fcmToken': _fcmToken,
      'platform': Platform.isIOS ? 'ios' : 'android',
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(bodyMap),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('[Push] Device registered successfully');
      } else {
        debugPrint(
            '[Push] Device registration failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[Push] Device registration error: $e');
    }
  }

  /// Unregister device on logout.
  Future<void> unregisterDevice({required String authToken}) async {
    if (_fcmToken == null) return;

    final uri = _bffUri('/mobile/devices/unregister');
    try {
      final response = await http
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'fcmToken': _fcmToken}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[Push] Device unregistered: ${response.statusCode}');
    } catch (e) {
      debugPrint('[Push] Device unregister error: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
  }

  // ── Token refresh callback (set by AuthState) ────────────────────

  void Function(String newToken)? _onTokenRefresh;

  /// Set a callback that will be invoked when the FCM token refreshes,
  /// so the caller can re-register with the server.
  set onTokenRefresh(void Function(String newToken)? callback) {
    _onTokenRefresh = callback;
  }

  // ── Private helpers ───────────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
        '[Push] Foreground message: ${message.notification?.title ?? message.messageId}');
    // The notification is automatically shown in the system tray on Android
    // when the "notification" key is present. No need to create a local
    // notification manually.
  }

  /// Track the last tapped message ID to prevent duplicates
  /// (getInitialMessage and onMessageOpenedApp can both fire on cold start).
  String? _lastTappedMessageId;

  void _handleNotificationTap(RemoteMessage message) {
    final msgId = message.messageId ?? '${message.data}';
    debugPrint(
        '[Push] _handleNotificationTap called: msgId=$msgId, data=${message.data}');

    // Deduplicate: prevent processing the same message twice.
    if (_lastTappedMessageId != null && _lastTappedMessageId == msgId) {
      debugPrint('[Push] Duplicate tap ignored (msgId=$msgId)');
      return;
    }
    _lastTappedMessageId = msgId;

    onNotificationTap?.call(message.data);
  }

  Uri _bffUri(String path) {
    final base = ApiConstants.mobileBffBaseUrl.endsWith('/')
        ? ApiConstants.mobileBffBaseUrl
            .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
        : ApiConstants.mobileBffBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }
}
