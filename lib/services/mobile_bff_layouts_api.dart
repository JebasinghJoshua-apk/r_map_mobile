import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_aware_http_client.dart';

class MobileBffLayoutsApi {
  MobileBffLayoutsApi({http.Client? client})
      : _client = client ?? AuthAwareHttpClient.instance;

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 12);

  Uri _uri(String path) {
    final normalizedBase = ApiConstants.mobileBffBaseUrl.endsWith('/')
        ? ApiConstants.mobileBffBaseUrl
            .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
        : ApiConstants.mobileBffBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  static String additionalDetailsForInput(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '';
    }
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized.replaceAll('~~', '\n');
  }

  static String? additionalDetailsForStorage(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return null;
    }

    return lines.join('~~');
  }

  Future<LayoutDetailDto> getLayoutDetail({
    required String layoutId,
    String? bearerToken,
  }) async {
    final trimmedId = layoutId.trim();
    if (trimmedId.isEmpty) {
      throw const LayoutsApiException('Invalid layout id');
    }

    final uri = _uri('/mobile/layouts/$trimmedId');

    http.Response response;
    try {
      final token = bearerToken?.trim();
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        final normalized = token.toLowerCase().startsWith('bearer ')
            ? token.substring('bearer '.length)
            : token;
        headers['Authorization'] = 'Bearer $normalized';
      }

      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on SocketException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException('Network error. Please try again.');
    } on TimeoutException {
      throw const LayoutsApiException('Request timed out. Please try again.');
    } on FormatException {
      throw const LayoutsApiException('Unexpected response from server');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const LayoutsApiException('Unexpected response from server');
      }
      return LayoutDetailDto.fromJson(decoded.cast<String, dynamic>());
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const LayoutsApiException('Not authorized to view layout details');
    }

    throw LayoutsApiException(
      _tryMessage(response.body) ??
          'Layout details fetch failed (${response.statusCode})',
    );
  }

  String? _tryMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
      if (decoded is String) {
        return decoded;
      }
    } catch (_) {
      // ignore
    }
    return body.isEmpty ? null : body;
  }

  void _logNetworkHelp(Uri requestUri) {
    if (!kDebugMode) return;
    debugPrint(
      'Layouts API request failed. MobileBFF: ${ApiConstants.mobileBffBaseUrl}. Request: $requestUri',
    );
  }

  /// Creates a new layout draft with boundary and basic details.
  ///
  /// Returns the created [LayoutDraftResponse] containing the layout ID
  /// which can be used to generate a QR code.
  Future<LayoutDraftResponse> createLayoutDraft({
    required String name,
    required List<List<double>> boundaryLatLng,
    bool isFarmLand = false,
    String? area,
    String? surveyNumber,
    String? approvalNumber,
    String? locationDetails,
    String? additionalDetails,
    String? contactName,
    String? contactNumbers,
    String? description,
    int? plotsCount,
    required String bearerToken,
  }) async {
    final uri = _uri('/mobile/layouts/draft');

    final payload = <String, dynamic>{
      'name': name.trim(),
      'layoutBoundaryLatLng': boundaryLatLng,
      'isFarmLand': isFarmLand,
    };

    if (area != null && area.trim().isNotEmpty) {
      payload['area'] = area.trim();
    }
    if (surveyNumber != null && surveyNumber.trim().isNotEmpty) {
      payload['surveyNumber'] = surveyNumber.trim();
    }
    if (approvalNumber != null && approvalNumber.trim().isNotEmpty) {
      payload['approvalNumber'] = approvalNumber.trim();
    }
    if (locationDetails != null && locationDetails.trim().isNotEmpty) {
      payload['locationDetails'] = locationDetails.trim();
    }
    final normalizedAdditionalDetails =
        additionalDetailsForStorage(additionalDetails);
    if (normalizedAdditionalDetails != null) {
      payload['additionalDetails'] = normalizedAdditionalDetails;
    }
    if (contactNumbers != null && contactNumbers.trim().isNotEmpty) {
      payload['contactNumbers'] = contactNumbers.trim();
    }
    if (contactName != null && contactName.trim().isNotEmpty) {
      payload['contactName'] = contactName.trim();
    }
    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (plotsCount != null && plotsCount > 0) {
      payload['plotsCount'] = plotsCount;
    }

    http.Response response;
    try {
      final token = bearerToken.trim();
      final normalized = token.toLowerCase().startsWith('bearer ')
          ? token.substring('bearer '.length)
          : token;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $normalized',
      };

      response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on SocketException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException('Network error. Please try again.');
    } on TimeoutException {
      throw const LayoutsApiException('Request timed out. Please try again.');
    } on FormatException {
      throw const LayoutsApiException('Unexpected response from server');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const LayoutsApiException('Unexpected response from server');
      }
      return LayoutDraftResponse.fromJson(decoded.cast<String, dynamic>());
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const LayoutsApiException('Not authorized to create layouts');
    }

    throw LayoutsApiException(
      _tryMessage(response.body) ??
          'Layout creation failed (${response.statusCode})',
    );
  }

  Future<void> updateLayout({
    required String layoutId,
    required String name,
    bool? isFarmLand,
    String? area,
    int? plotsCount,
    String? surveyNumber,
    String? approvalNumber,
    String? locationDetails,
    String? additionalDetails,
    String? contactName,
    String? contactNumbers,
    String? description,
    required String bearerToken,
  }) async {
    final trimmedId = layoutId.trim();
    if (trimmedId.isEmpty) {
      throw const LayoutsApiException('Invalid layout id');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const LayoutsApiException('Layout name is required');
    }

    final uri = _uri('/mobile/layouts/$trimmedId');

    final normalizedAdditionalDetails =
      additionalDetailsForStorage(additionalDetails);

    final payload = <String, dynamic>{
      'name': trimmedName,
      if (isFarmLand != null) 'isFarmLand': isFarmLand,
      if (area != null) 'area': area.trim().isEmpty ? null : area.trim(),
      if (plotsCount != null && plotsCount > 0) 'plotsCount': plotsCount,
      if (surveyNumber != null)
        'surveyNumber': surveyNumber.trim().isEmpty ? null : surveyNumber.trim(),
      if (approvalNumber != null)
        'approvalNumber':
            approvalNumber.trim().isEmpty ? null : approvalNumber.trim(),
      if (locationDetails != null)
        'locationDetails':
            locationDetails.trim().isEmpty ? null : locationDetails.trim(),
      if (additionalDetails != null)
        'additionalDetails': normalizedAdditionalDetails,
      if (contactName != null)
        'contactName': contactName.trim().isEmpty ? null : contactName.trim(),
      if (contactNumbers != null)
        'contactNumbers':
            contactNumbers.trim().isEmpty ? null : contactNumbers.trim(),
      if (description != null) 'description': description,
    };

    http.Response response;
    try {
      final token = bearerToken.trim();
      final normalized = token.toLowerCase().startsWith('bearer ')
          ? token.substring('bearer '.length)
          : token;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $normalized',
      };

      response = await _client
          .put(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on SocketException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      _logNetworkHelp(uri);
      throw const LayoutsApiException('Network error. Please try again.');
    } on TimeoutException {
      throw const LayoutsApiException('Request timed out. Please try again.');
    } on FormatException {
      throw const LayoutsApiException('Unexpected response from server');
    }

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const LayoutsApiException('Not authorized to update layouts');
    }

    throw LayoutsApiException(
      _tryMessage(response.body) ??
          'Layout update failed (${response.statusCode})',
    );
  }
}

/// Response from creating a layout draft.
class LayoutDraftResponse {
  const LayoutDraftResponse({
    required this.id,
    required this.name,
    required this.isFarmLand,
    this.area,
    this.surveyNumber,
    this.approvalNumber,
    this.locationDetails,
    this.additionalDetails,
    this.contactNumbers,
    this.description,
    this.plotsCount,
    required this.isDraft,
    required this.createdAt,
    this.shortCode,
  });

  final String id;
  final String name;
  final bool isFarmLand;
  final String? area;
  final String? surveyNumber;
  final String? approvalNumber;
  final String? locationDetails;
  final String? additionalDetails;
  final String? contactNumbers;
  final String? description;
  final int? plotsCount;
  final bool isDraft;
  final DateTime createdAt;

  /// Short code for QR URLs (e.g., "A3x9Kp" → rmap.in/s/A3x9Kp)
  final String? shortCode;

  static LayoutDraftResponse fromJson(Map<String, dynamic> json) {
    return LayoutDraftResponse(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      isFarmLand: (json['isFarmLand'] as bool?) ?? false,
      area: json['area'] as String?,
      surveyNumber: json['surveyNumber'] as String?,
      approvalNumber: json['approvalNumber'] as String?,
      locationDetails: json['locationDetails'] as String?,
      additionalDetails: json['additionalDetails'] as String?,
      contactNumbers: json['contactNumbers'] as String?,
      description: json['description'] as String?,
      plotsCount: _asIntGlobal(json['plotsCount']),
      isDraft: (json['isDraft'] as bool?) ?? true,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      shortCode: json['shortCode'] as String?,
    );
  }
}

int? _asIntGlobal(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

class LayoutsApiException implements Exception {
  const LayoutsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LayoutDetailDto {
  const LayoutDetailDto({
    required this.id,
    required this.name,
    required this.isFarmLand,
    this.description,
    this.surveyNumber,
    this.approvalNumber,
    this.locationDetails,
    this.additionalDetails,
    this.contactName,
    this.contactNumbers,
    this.area,
    this.plotsCount,
    this.shortCode,
    required this.createdAt,
    required this.isDraft,
    required this.images,
  });

  final String id;
  final String name;
  final bool isFarmLand;
  final String? description;
  final String? surveyNumber;
  final String? approvalNumber;
  final String? locationDetails;
  final String? additionalDetails;
  final String? contactName;
  final String? contactNumbers;
  final String? area;
  final int? plotsCount;

  /// Short code for generating compact share URLs (e.g., rmap.in/s/ABC123).
  final String? shortCode;
  final DateTime createdAt;
  final bool isDraft;
  final List<LayoutImageDto> images;

  static LayoutDetailDto fromJson(Map<String, dynamic> json) {
    return LayoutDetailDto(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      isFarmLand: (json['isFarmLand'] as bool?) ?? false,
      description: json['description'] as String?,
      surveyNumber: json['surveyNumber'] as String?,
      approvalNumber: json['approvalNumber'] as String?,
      locationDetails: json['locationDetails'] as String?,
      additionalDetails: json['additionalDetails'] as String?,
      contactName: json['contactName'] as String?,
      contactNumbers: json['contactNumbers'] as String?,
      area: json['area'] as String?,
      plotsCount: _asInt(json['plotsCount']),
      shortCode: json['shortCode'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isDraft: (json['isDraft'] as bool?) ?? false,
      images: _asList(json['images'])
          .map((e) => LayoutImageDto.fromJson(e))
          .toList(growable: false),
    );
  }
}

class LayoutImageDto {
  const LayoutImageDto({
    required this.id,
    required this.fileUrl,
    this.altText,
    this.description,
    this.isPrimary,
    this.displayOrder,
  });

  final String id;
  final String fileUrl;
  final String? altText;
  final String? description;
  final bool? isPrimary;
  final int? displayOrder;

  static LayoutImageDto fromJson(Map<String, dynamic> json) {
    return LayoutImageDto(
      id: (json['id'] as String?) ?? '',
      fileUrl: (json['fileUrl'] as String?) ?? '',
      altText: json['altText'] as String?,
      description: json['description'] as String?,
      isPrimary: json['isPrimary'] as bool?,
      displayOrder: _asInt(json['displayOrder']),
    );
  }
}

Iterable<Map<String, dynamic>> _asList(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map((e) => e.cast<String, dynamic>());
  }
  return const Iterable.empty();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
