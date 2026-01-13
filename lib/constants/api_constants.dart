class ApiConstants {
  static const String _defaultAndroidEmulatorBffBaseUrl =
      'http://10.0.2.2:5150';
  static const String _defaultAndroidEmulatorApiBaseUrl =
      'http://10.0.2.2:5132';

  static const String mobileBffBaseUrl = String.fromEnvironment(
    'MOBILE_BFF_BASE_URL',
    // For Android emulators, host machine is available at 10.0.2.2.
    // For physical devices, pass your LAN IP via --dart-define.
    defaultValue: 'http://10.0.2.2:5150',
  );

  // Base URL for the upstream API (used for resolving /uploads/* URLs).
  // Defaults to the local dev API port.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // For Android emulators, host machine is available at 10.0.2.2.
    defaultValue: 'http://10.0.2.2:5132',
  );

  // Optional explicit overrides (empty when not provided).
  static const String apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL');
  static const String uploadsBaseUrlOverride =
      String.fromEnvironment('UPLOADS_BASE_URL');

  // Base URL for serving uploaded media (usually the API host).
  static const String uploadsBaseUrl = String.fromEnvironment(
    'UPLOADS_BASE_URL',
    defaultValue: apiBaseUrl,
  );

  /// Resolved base URL used for `/uploads/*` media.
  ///
  /// Why this exists:
  /// - On Android emulators `10.0.2.2` is correct.
  /// - On real devices, if only `MOBILE_BFF_BASE_URL` is provided, the default
  ///   `API_BASE_URL` (`10.0.2.2`) is wrong, causing images to fail to load.
  ///
  /// Precedence:
  /// 1) `UPLOADS_BASE_URL`
  /// 2) `API_BASE_URL`
  /// 3) Derived from `MOBILE_BFF_BASE_URL` (preferred for real devices)
  /// 4) Default `uploadsBaseUrl`
  static String get effectiveUploadsBaseUrl {
    final uploadsOverride = uploadsBaseUrlOverride.trim();
    if (uploadsOverride.isNotEmpty) return uploadsOverride;

    final apiOverride = apiBaseUrlOverride.trim();
    if (apiOverride.isNotEmpty) return apiOverride;

    final bff = mobileBffBaseUrl.trim();

    // Prefer the BFF host for media so the device only needs to reach the BFF.
    // The BFF proxies /uploads/* to the upstream API.
    final derivedFromBff = _deriveUploadsBaseFromBff(bff);
    if (derivedFromBff != null) return derivedFromBff;

    final api = apiBaseUrl.trim();

    if (api == _defaultAndroidEmulatorApiBaseUrl &&
        bff.isNotEmpty &&
        bff != _defaultAndroidEmulatorBffBaseUrl) {
      final derived = _deriveApiHostFromBff(bff);
      if (derived != null) return derived;
    }

    return uploadsBaseUrl.trim();
  }

  static String? _deriveApiHostFromBff(String bffBaseUrl) {
    try {
      final uri = Uri.parse(bffBaseUrl);
      if (!uri.hasScheme || uri.host.isEmpty) return null;

      // Assume API is running on same host as the Mobile BFF.
      // Keep scheme and host; force API port (local dev convention).
      final apiUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: 5132,
      );
      return apiUri.toString();
    } catch (_) {
      return null;
    }
  }

  static String? _deriveUploadsBaseFromBff(String bffBaseUrl) {
    if (bffBaseUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(bffBaseUrl);
      if (!uri.hasScheme || uri.host.isEmpty) return null;

      // Keep BFF host/port. The Mobile BFF exposes a /uploads/* proxy route.
      final bffRoot = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      );
      return bffRoot.toString();
    } catch (_) {
      return null;
    }
  }
}
