import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/saved_property.dart';
import 'auth_aware_http_client.dart';

class MobileBffSavedPropertiesApi {
  MobileBffSavedPropertiesApi({http.Client? client})
      : _client = client ?? AuthAwareHttpClient.instance;

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  Uri _uri(String path) {
    final normalizedBase = ApiConstants.mobileBffBaseUrl.endsWith('/')
        ? ApiConstants.mobileBffBaseUrl
            .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
        : ApiConstants.mobileBffBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, String> _authHeaders(String bearerToken) {
    final token = bearerToken.toLowerCase().startsWith('bearer ')
        ? bearerToken.substring('bearer '.length)
        : bearerToken;
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<String>> getSavedPropertyIds(
      {required String bearerToken}) async {
    final uri = _uri('/mobile/saved-properties/ids');

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: _authHeaders(bearerToken))
          .timeout(_timeout);
    } on SocketException {
      throw const SavedPropertiesApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      throw const SavedPropertiesApiException(
          'Network error. Please try again.');
    } on TimeoutException {
      throw const SavedPropertiesApiException(
          'Request timed out. Please try again.');
    } on FormatException {
      throw const SavedPropertiesApiException(
          'Unexpected response from server');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SavedPropertiesApiException(_extractError(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const SavedPropertiesApiException(
          'Unexpected response from server');
    }

    return decoded
        .map((e) => (e ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<SavedProperty>> getSavedProperties({
    required String bearerToken,
  }) async {
    final uri = _uri('/mobile/saved-properties');

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: _authHeaders(bearerToken))
          .timeout(_timeout);
    } on SocketException {
      throw const SavedPropertiesApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      throw const SavedPropertiesApiException(
          'Network error. Please try again.');
    } on TimeoutException {
      throw const SavedPropertiesApiException(
          'Request timed out. Please try again.');
    } on FormatException {
      throw const SavedPropertiesApiException(
          'Unexpected response from server');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SavedPropertiesApiException(_extractError(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const SavedPropertiesApiException(
          'Unexpected response from server');
    }

    return decoded
        .whereType<Map>()
        .map((e) => SavedProperty.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<bool> isPropertySaved({
    required String propertyId,
    required String bearerToken,
  }) async {
    final trimmed = propertyId.trim();
    if (trimmed.isEmpty) {
      throw const SavedPropertiesApiException('PropertyId is required');
    }

    final uri = _uri('/mobile/saved-properties/$trimmed/exists');

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: _authHeaders(bearerToken))
          .timeout(_timeout);
    } on SocketException {
      throw const SavedPropertiesApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      throw const SavedPropertiesApiException(
          'Network error. Please try again.');
    } on TimeoutException {
      throw const SavedPropertiesApiException(
          'Request timed out. Please try again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SavedPropertiesApiException(_extractError(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is bool) return decoded;
    if (decoded is String) return decoded.toLowerCase() == 'true';
    return false;
  }

  Future<void> saveProperty({
    required String propertyId,
    required String bearerToken,
  }) async {
    final trimmed = propertyId.trim();
    if (trimmed.isEmpty) {
      throw const SavedPropertiesApiException('PropertyId is required');
    }

    final uri = _uri('/mobile/saved-properties/$trimmed');

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: _authHeaders(bearerToken))
          .timeout(_timeout);
    } on SocketException {
      throw const SavedPropertiesApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      throw const SavedPropertiesApiException(
          'Network error. Please try again.');
    } on TimeoutException {
      throw const SavedPropertiesApiException(
          'Request timed out. Please try again.');
    }

    if (response.statusCode == 204) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SavedPropertiesApiException(_extractError(response));
    }
  }

  Future<void> unsaveProperty({
    required String propertyId,
    required String bearerToken,
  }) async {
    final trimmed = propertyId.trim();
    if (trimmed.isEmpty) {
      throw const SavedPropertiesApiException('PropertyId is required');
    }

    final uri = _uri('/mobile/saved-properties/$trimmed');

    http.Response response;
    try {
      response = await _client
          .delete(uri, headers: _authHeaders(bearerToken))
          .timeout(_timeout);
    } on SocketException {
      throw const SavedPropertiesApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      throw const SavedPropertiesApiException(
          'Network error. Please try again.');
    } on TimeoutException {
      throw const SavedPropertiesApiException(
          'Request timed out. Please try again.');
    }

    if (response.statusCode == 204) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SavedPropertiesApiException(_extractError(response));
    }
  }

  String _extractError(http.Response response) {
    // Keep the message short and user-safe.
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // ignore
    }

    final trimmed = response.body.trim();
    if (trimmed.isNotEmpty) {
      return trimmed.length > 180 ? trimmed.substring(0, 180) : trimmed;
    }

    debugPrint('Saved properties API failed: ${response.statusCode}');
    return 'Request failed. Please try again.';
  }
}

class SavedPropertiesApiException implements Exception {
  const SavedPropertiesApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
