import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import '../services/analytics_service.dart';
import '../services/mobile_bff_auth_api.dart';

class AuthState extends ChangeNotifier {
  AuthState({MobileBffAuthApi? api}) : _api = api ?? MobileBffAuthApi();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  final MobileBffAuthApi _api;

  AuthSession? _session;
  AuthSession? get session => _session;

  bool get isAuthenticated => _session != null && _session!.token.isNotEmpty;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);

    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      _session = null;
      notifyListeners();
      return;
    }

    try {
      final userMap = (jsonDecode(userJson) as Map).cast<String, dynamic>();
      _session = AuthSession(token: token, user: AuthUser.fromJson(userMap));
    } catch (_) {
      _session = null;
    }

    notifyListeners();
  }

  Future<void> login({
    required String phoneOrEmail,
    required String password,
  }) async {
    final session =
        await _api.login(phoneOrEmail: phoneOrEmail, password: password);
    await _persist(session);
    _session = session;
    AnalyticsService.instance.setUserId(session.user.id);
    AnalyticsService.instance.logLogin();
    notifyListeners();
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
  }) async {
    final session = await _api.register(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      password: password,
    );
    await _persist(session);
    _session = session;
    AnalyticsService.instance.setUserId(session.user.id);
    AnalyticsService.instance.logSignUp();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _session = null;
    AnalyticsService.instance.setUserId(null);
    AnalyticsService.instance.logLogout();
    notifyListeners();
  }

  /// Sends OTP to the specified phone number.
  Future<SendOtpResult> sendOtp({
    required String phoneNumber,
    OtpPurpose purpose = OtpPurpose.login,
  }) async {
    return _api.sendOtp(phoneNumber: phoneNumber, purpose: purpose);
  }

  /// Verifies OTP and logs in if user exists.
  /// Returns [VerifyOtpResult] - check requiresRegistration to know if user needs to register.
  Future<VerifyOtpResult> verifyOtp({
    required String phoneNumber,
    required String otpCode,
    OtpPurpose purpose = OtpPurpose.login,
  }) async {
    final result = await _api.verifyOtp(
      phoneNumber: phoneNumber,
      otpCode: otpCode,
      purpose: purpose,
    );

    if (result.success && result.session != null) {
      await _persist(result.session!);
      _session = result.session;
      AnalyticsService.instance.setUserId(result.session!.user.id);
      AnalyticsService.instance.logLogin();
      notifyListeners();
    }

    return result;
  }

  /// Registers a new user after OTP verification.
  Future<void> registerWithOtp({
    required String phoneNumber,
    required String otpCode,
    String? name,
  }) async {
    final session = await _api.registerWithOtp(
      phoneNumber: phoneNumber,
      otpCode: otpCode,
      name: name,
    );
    await _persist(session);
    _session = session;
    AnalyticsService.instance.setUserId(session.user.id);
    AnalyticsService.instance.logSignUp();
    notifyListeners();
  }

  Future<void> _persist(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
  }
}
