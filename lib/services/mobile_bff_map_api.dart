import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/image_summary.dart';
import '../models/map_viewport_models.dart';
import '../models/my_property_list_item.dart';
import '../models/nearby_property_card.dart';
import '../models/property_detail.dart';

class MobileBffMapApi {
  MobileBffMapApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 12);

  Uri _uri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedBase = ApiConstants.mobileBffBaseUrl.endsWith('/')
        ? ApiConstants.mobileBffBaseUrl
            .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
        : ApiConstants.mobileBffBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    final baseUri = Uri.parse('$normalizedBase$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return baseUri;
    }

    final query = _buildQueryString(queryParameters);
    return baseUri.replace(query: query);
  }

  String _buildQueryString(Map<String, dynamic> queryParameters) {
    final parts = <String>[];
    for (final entry in queryParameters.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) {
        continue;
      }

      if (value is List) {
        for (final item in value) {
          if (item == null) continue;
          parts.add(
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(item.toString())}',
          );
        }
        continue;
      }

      parts.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value.toString())}',
      );
    }
    return parts.join('&');
  }

  Future<MapViewportResponse> getViewport({
    required LatLngBounds bounds,
    required double zoom,
    List<String>? propertyTypes,
    String? bearerToken,
  }) async {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;

    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final filters = (propertyTypes ?? const <String>[])
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final uri = _uri(
      '/mobile/map/viewport',
      {
        'minLat': minLat,
        'maxLat': maxLat,
        'minLng': minLng,
        'maxLng': maxLng,
        'zoom': zoom,
        if (filters.isNotEmpty) 'propertyTypes': filters,
      },
    );

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException(
        'Request timed out. Please try again.',
      );
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const MapApiException('Unexpected response from server');
      }
      return MapViewportResponse.fromJson(decoded.cast<String, dynamic>());
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Viewport fetch failed (${response.statusCode})',
    );
  }

  Future<List<ImageSummary>> getPropertyMedia({
    required String propertyType,
    required String entityId,
    String? bearerToken,
  }) async {
    final uri = _uri('/mobile/properties/$propertyType/$entityId/media');

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException(
        'Request timed out. Please try again.',
      );
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const MapApiException('Unexpected response from server');
      }

      final images = decoded
          .whereType<Map>()
          .map((e) => ImageSummary.fromJson(e.cast<String, dynamic>()))
          .where((img) => img.fileUrl.trim().isNotEmpty)
          .toList();

      images.sort((a, b) {
        final pa = a.isPrimary ? 0 : 1;
        final pb = b.isPrimary ? 0 : 1;
        final byPrimary = pa.compareTo(pb);
        if (byPrimary != 0) return byPrimary;
        final byOrder = a.displayOrder.compareTo(b.displayOrder);
        if (byOrder != 0) return byOrder;
        return a.fileUrl.compareTo(b.fileUrl);
      });

      return images;
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to view photos.');
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Property media fetch failed (${response.statusCode})',
    );
  }

  Future<List<NearbyPropertyCard>> getNearbyLayouts({
    required LatLng anchor,
    int limit = 15,
    double? radiusKm,
    String? bearerToken,
  }) async {
    final uri = _uri(
      '/mobile/properties/nearby',
      {
        'lat': anchor.latitude,
        'lng': anchor.longitude,
        'propertyType': 'Layout',
        'limit': limit,
        if (radiusKm != null) 'radiusKm': radiusKm,
      },
    );

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const MapApiException('Unexpected response from server');
      }

      return decoded
          .whereType<Map>()
          .map((e) => NearbyPropertyCard.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id.trim().isNotEmpty)
          .toList(growable: false);
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Nearby layouts fetch failed (${response.statusCode})',
    );
  }

  Future<List<MyPropertyListItem>> getMyProperties({
    String? bearerToken,
  }) async {
    final uri = _uri('/mobile/properties/my');

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const MapApiException('Unexpected response from server');
      }

      return decoded
          .whereType<Map>()
          .map((e) => MyPropertyListItem.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to view your properties.');
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'My properties fetch failed (${response.statusCode})',
    );
  }

  Future<void> deleteProperty({
    required String propertyType,
    required String propertyId,
    String? bearerToken,
  }) async {
    final safeType = Uri.encodeComponent(propertyType.trim());
    final uri = _uri('/mobile/properties/$safeType/$propertyId');

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .delete(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to delete properties.');
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Property delete failed (${response.statusCode})',
    );
  }

  Future<PropertyDetail> getPropertyDetail({
    required String propertyId,
    String? bearerToken,
  }) async {
    final uri = _uri('/mobile/properties/$propertyId');

    http.Response response;
    try {
      final headers = <String, String>{};
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const MapApiException('Unexpected response from server');
      }

      return PropertyDetail.fromJson(decoded.cast<String, dynamic>());
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to view your property.');
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Property detail fetch failed (${response.statusCode})',
    );
  }

  Future<Map<String, dynamic>> createPropertyByType({
    required String propertyType,
    required Map<String, dynamic> payload,
    String? bearerToken,
  }) async {
    final normalized = propertyType.trim().toLowerCase();
    final path = switch (normalized) {
      'independent-houses' => '/mobile/independent-houses',
      'apartment-flats' => '/mobile/apartment-flats',
      'individual-plots' => '/mobile/individual-plots',
      'lands' => '/mobile/lands',
      'commercial-spaces' => '/mobile/commercial-spaces',
      _ => '/mobile/$normalized',
    };

    final uri = _uri(path);

    http.Response response;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        headers['Authorization'] = 'Bearer $token';
      }

      response = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const MapApiException('Unexpected response from server');
      }
      return decoded.cast<String, dynamic>();
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to save this property.');
    }

    throw MapApiException(
      _tryMessage(response.body) ??
          'Property save failed (${response.statusCode})',
    );
  }

  Future<Map<String, dynamic>> uploadPropertyImage({
    required String propertyId,
    required File file,
    String? bearerToken,
    bool isPrimary = false,
    int displayOrder = 1,
    String? description,
    String? altText,
  }) async {
    final uri = _uri('/mobile/properties/$propertyId/images');

    http.StreamedResponse response;
    try {
      final request = http.MultipartRequest('POST', uri);
      if (bearerToken != null && bearerToken.trim().isNotEmpty) {
        final token = bearerToken.toLowerCase().startsWith('bearer ')
            ? bearerToken.substring('bearer '.length)
            : bearerToken;
        request.headers['Authorization'] = 'Bearer $token';
      }

      // IMPORTANT: keep these names aligned with
      // R.MAP.MobileBff.Models.PropertyImageUploadRequest
      request.fields['IsPrimary'] = isPrimary ? 'true' : 'false';
      request.fields['DisplayOrder'] = displayOrder.toString();
      if (description != null && description.trim().isNotEmpty) {
        request.fields['Description'] = description.trim();
      }
      if (altText != null && altText.trim().isNotEmpty) {
        request.fields['AltText'] = altText.trim();
      }

      request.files.add(await http.MultipartFile.fromPath('File', file.path));

      response = await request.send().timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const MapApiException('Network error. Please try again.');
    } on FormatException {
      throw const MapApiException('Unexpected response from server');
    } on TimeoutException {
      throw const MapApiException('Request timed out. Please try again.');
    }

    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const MapApiException('Unexpected response from server');
      }
      return decoded.cast<String, dynamic>();
    }

    if (response.statusCode == 401) {
      throw const MapApiException('Please login to upload images.');
    }

    throw MapApiException(
      _tryMessage(responseBody) ??
          'Image upload failed (${response.statusCode})',
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

  String _networkHelpMessage() {
    const base = ApiConstants.mobileBffBaseUrl;
    return 'Cannot reach Mobile BFF at $base. '
        'If using a real phone, set MOBILE_BFF_BASE_URL to your PC LAN IP (e.g. http://192.168.x.x:5150). '
        'If using an Android emulator, use http://10.0.2.2:5150. '
        'Also ensure MobileBff is running and Windows Firewall allows port 5150. '
        'On Android, debug builds must allow cleartext HTTP. '
        'Tip: try opening $base/health in your phone browser; if that fails, the phone is not reaching your PC (different Wi-Fi/VPN/guest isolation/firewall).';
  }

  Future<void> _logNetworkDiagnostics(Uri requestUri) async {
    if (!kDebugMode) {
      return;
    }

    try {
      final baseUri = Uri.tryParse(ApiConstants.mobileBffBaseUrl);
      debugPrint('--- MobileBFF network diagnostics ---');
      debugPrint('Base: ${ApiConstants.mobileBffBaseUrl}');
      debugPrint('Request: $requestUri');

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
        includeLinkLocal: true,
      );

      final ipv4 = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ipv4.add('${iface.name}:${addr.address}');
        }
      }

      if (ipv4.isEmpty) {
        debugPrint('Device IPv4: <none>');
      } else {
        debugPrint('Device IPv4: ${ipv4.join(', ')}');
      }

      final host = (baseUri != null && baseUri.host.isNotEmpty)
          ? baseUri.host
          : requestUri.host;
      final port = (baseUri?.hasPort ?? false)
          ? baseUri!.port
          : (requestUri.hasPort
              ? requestUri.port
              : (requestUri.scheme == 'https' ? 443 : 80));

      debugPrint('TCP probe: $host:$port');
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      debugPrint('TCP probe result: connected (HTTP may still fail)');
      debugPrint('--- end diagnostics ---');
    } catch (e) {
      debugPrint('MobileBFF diagnostics failed: $e');
    }
  }
}

class MapApiException implements Exception {
  const MapApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
