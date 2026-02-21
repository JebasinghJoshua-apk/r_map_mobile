import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/auth_session.dart';

class MobileBffAuthApi {
  MobileBffAuthApi({http.Client? client}) : _client = client ?? http.Client();

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

  Future<AuthSession> login({
    required String phoneOrEmail,
    required String password,
  }) async {
    final uri = _uri('/mobile/auth/login');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phoneOrEmail': phoneOrEmail,
              'password': password,
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const AuthApiException(
        'Cannot connect to the server. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const AuthApiException('Network error. Please try again.');
    } on FormatException {
      throw const AuthApiException('Unexpected response from server');
    } on TimeoutException {
      throw const AuthApiException(
        'Request timed out. Please try again.',
      );
    }

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseSession(json);
    }

    if (response.statusCode == 401) {
      throw const AuthApiException('Invalid phone number/email or password');
    }

    throw AuthApiException(
        _tryMessage(response.body) ?? 'Login failed (${response.statusCode})');
  }

  Future<AuthSession> register({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
  }) async {
    final uri = _uri('/mobile/auth/register');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firstName': firstName,
              'lastName': lastName,
              'phoneNumber': phoneNumber,
              'password': password,
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const AuthApiException(
        'No internet connection. Please check your network and try again.',
      );
    } on HttpException {
      await _logNetworkDiagnostics(uri);
      debugPrint(_networkHelpMessage());
      throw const AuthApiException('Network error. Please try again.');
    } on FormatException {
      throw const AuthApiException('Unexpected response from server');
    } on TimeoutException {
      throw const AuthApiException(
        'Request timed out. Please try again.',
      );
    }

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseSession(json);
    }

    if (response.statusCode == 400) {
      throw AuthApiException(
          _tryMessage(response.body) ?? 'Invalid registration details');
    }

    throw AuthApiException(_tryMessage(response.body) ??
        'Registration failed (${response.statusCode})');
  }

  /// Sends OTP to the specified phone number.
  /// Returns [SendOtpResult] with success status and channel used.
  Future<SendOtpResult> sendOtp({
    required String phoneNumber,
    OtpPurpose purpose = OtpPurpose.login,
  }) async {
    final uri = _uri('/mobile/auth/otp/send');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phoneNumber': phoneNumber,
              'purpose': purpose.index + 1, // 1=Login, 2=Register
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot connect to the server. Please check your network.',
      );
    } on TimeoutException {
      throw const AuthApiException('Request timed out. Please try again.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    return SendOtpResult(
      success: json['success'] as bool? ?? false,
      requestId: json['requestId'] as String?,
      channel: json['channel'] as String?,
      message: json['message'] as String?,
      retryAfterSeconds: json['retryAfterSeconds'] as int?,
    );
  }

  /// Verifies OTP code for the specified phone number.
  /// Returns [VerifyOtpResult] with token if successful, or registration flag.
  Future<VerifyOtpResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    OtpPurpose purpose = OtpPurpose.login,
  }) async {
    final uri = _uri('/mobile/auth/otp/verify');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phoneNumber': phoneNumber,
              'otpCode': otpCode,
              'purpose': purpose.index + 1,
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot connect to the server. Please check your network.',
      );
    } on TimeoutException {
      throw const AuthApiException('Request timed out. Please try again.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final success = json['success'] as bool? ?? false;

    if (success && json['token'] != null) {
      // User exists, return session
      return VerifyOtpResult(
        success: true,
        session: _parseSession(json),
        requiresRegistration: false,
      );
    }

    if (success && (json['requiresRegistration'] as bool? ?? false)) {
      // Phone verified but user doesn't exist
      return VerifyOtpResult(
        success: true,
        session: null,
        requiresRegistration: true,
        message: json['message'] as String?,
      );
    }

    return VerifyOtpResult(
      success: false,
      session: null,
      requiresRegistration: false,
      message: json['message'] as String? ?? 'OTP verification failed',
    );
  }

  /// Registers a new user with OTP verification.
  /// Phone must be verified first with [verifyOtp].
  Future<AuthSession> registerWithOtp({
    required String phoneNumber,
    required String otpCode,
    String? name,
  }) async {
    final uri = _uri('/mobile/auth/otp/register');
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phoneNumber': phoneNumber,
              'otpCode': otpCode,
              'name': name,
            }),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const AuthApiException(
        'Cannot connect to the server. Please check your network.',
      );
    } on TimeoutException {
      throw const AuthApiException('Request timed out. Please try again.');
    }

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseSession(json);
    }

    throw AuthApiException(_tryMessage(response.body) ??
        'Registration failed (${response.statusCode})');
  }

  AuthSession _parseSession(Map<String, dynamic> json) {
    final token = (json['token'] as String?) ?? '';
    final userJson =
        (json['user'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    return AuthSession(
      token: token,
      user: AuthUser(
        id: (userJson['id'] as String?) ?? '',
        firstName: (userJson['firstName'] as String?) ?? '',
        lastName: (userJson['lastName'] as String?) ?? '',
        email: userJson['email'] as String?,
        phoneNumber: (userJson['phoneNumber'] as String?) ?? '',
        role: (userJson['role'] as String?) ?? '',
      ),
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

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum OtpPurpose {
  login,
  register,
  passwordReset,
  phoneVerification,
}

class SendOtpResult {
  const SendOtpResult({
    required this.success,
    this.requestId,
    this.channel,
    this.message,
    this.retryAfterSeconds,
  });

  final bool success;
  final String? requestId;
  final String? channel; // "whatsapp" or "sms"
  final String? message;
  final int? retryAfterSeconds;
}

class VerifyOtpResult {
  const VerifyOtpResult({
    required this.success,
    this.session,
    required this.requiresRegistration,
    this.message,
  });

  final bool success;
  final AuthSession? session;
  final bool requiresRegistration;
  final String? message;
}
