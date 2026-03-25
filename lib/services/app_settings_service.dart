import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class AppSettings {
  const AppSettings({
    required this.contactPhone,
    required this.contactEmail,
    required this.contactAddress,
  });

  final String contactPhone;
  final String contactEmail;
  final String contactAddress;

  static const AppSettings empty = AppSettings(
    contactPhone: '',
    contactEmail: '',
    contactAddress: '',
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      contactPhone: (json['contactPhone'] as String?) ?? '',
      contactEmail: (json['contactEmail'] as String?) ?? '',
      contactAddress: (json['contactAddress'] as String?) ?? '',
    );
  }
}

class AppSettingsService {
  AppSettingsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  /// Cached settings so we don't fetch on every profile menu open.
  AppSettings? _cached;

  /// Returns cached settings if available, otherwise fetches from the API.
  Future<AppSettings> getSettings({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached!;

    try {
      final base = ApiConstants.mobileBffBaseUrl.endsWith('/')
          ? ApiConstants.mobileBffBaseUrl
              .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
          : ApiConstants.mobileBffBaseUrl;
      final uri = Uri.parse('$base/mobile/app-settings');
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _cached = AppSettings.fromJson(json);
        return _cached!;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to fetch app settings: $e');
      }
    }

    return _cached ?? AppSettings.empty;
  }
}
