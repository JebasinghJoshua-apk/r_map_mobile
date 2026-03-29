import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import 'auth_aware_http_client.dart';

class MobileBffPlotsApi {
  MobileBffPlotsApi({http.Client? client})
      : _client = client ?? AuthAwareHttpClient.instance;

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Uri _uri(String path) {
    final normalizedBase = ApiConstants.mobileBffBaseUrl.endsWith('/')
        ? ApiConstants.mobileBffBaseUrl
            .substring(0, ApiConstants.mobileBffBaseUrl.length - 1)
        : ApiConstants.mobileBffBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Future<void> updatePlotStatus({
    required String plotId,
    required String status,
    required String bearerToken,
  }) async {
    final trimmedId = plotId.trim();
    if (trimmedId.isEmpty) {
      throw const PlotsApiException('Invalid plot id');
    }

    final trimmedStatus = status.trim();
    if (trimmedStatus.isEmpty) {
      throw const PlotsApiException('Invalid status');
    }

    final uri = _uri('/mobile/plots/$trimmedId/status');

    http.Response response;
    try {
      final token = bearerToken.toLowerCase().startsWith('bearer ')
          ? bearerToken.substring('bearer '.length)
          : bearerToken;

      response = await _client
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'status': trimmedStatus}),
          )
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      throw const PlotsApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      throw const PlotsApiException('Network error. Please try again.');
    } on TimeoutException {
      throw const PlotsApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 204) {
      return;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const PlotsApiException('Not authorized to update status');
    }

    throw PlotsApiException(
      _tryMessage(response.body) ??
          'Update status failed (${response.statusCode})',
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

class PlotsApiException implements Exception {
  const PlotsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
