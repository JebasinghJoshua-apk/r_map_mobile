import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class MobileBffLayoutsApi {
  MobileBffLayoutsApi({http.Client? client})
      : _client = client ?? http.Client();

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

  Future<LayoutDetailDto> getLayoutDetail({
    required String layoutId,
    required String bearerToken,
  }) async {
    final trimmedId = layoutId.trim();
    if (trimmedId.isEmpty) {
      throw const LayoutsApiException('Invalid layout id');
    }

    final uri = _uri('/mobile/layouts/$trimmedId');

    http.Response response;
    try {
      final token = bearerToken.toLowerCase().startsWith('bearer ')
          ? bearerToken.substring('bearer '.length)
          : bearerToken;

      response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
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
    this.description,
    this.locationDetails,
    this.additionalDetails,
    this.contactNumbers,
    this.area,
    this.plotsCount,
    required this.createdAt,
    required this.isDraft,
    required this.images,
  });

  final String id;
  final String name;
  final String? description;
  final String? locationDetails;
  final String? additionalDetails;
  final String? contactNumbers;
  final String? area;
  final int? plotsCount;
  final DateTime createdAt;
  final bool isDraft;
  final List<LayoutImageDto> images;

  static LayoutDetailDto fromJson(Map<String, dynamic> json) {
    return LayoutDetailDto(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      locationDetails: json['locationDetails'] as String?,
      additionalDetails: json['additionalDetails'] as String?,
      contactNumbers: json['contactNumbers'] as String?,
      area: json['area'] as String?,
      plotsCount: _asInt(json['plotsCount']),
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
