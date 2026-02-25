class ApiConstants {
  static const String _defaultAndroidEmulatorBffBaseUrl =
      'http://10.0.2.2:5150';
  static const String _defaultAndroidEmulatorApiBaseUrl =
      'http://10.0.2.2:5132';

  /// Public web-app URL used when constructing shareable links.
  /// Override via: --dart-define=WEB_BASE_URL=https://your-site.example
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://rmap.in',
  );

  static const String mobileBffBaseUrl = String.fromEnvironment(
    'MOBILE_BFF_BASE_URL',
    // Defaults to Azure production. For local dev, override via:
    //   --dart-define=MOBILE_BFF_BASE_URL=http://192.168.1.38:5150
    defaultValue: 'https://rmap-prod-mobilebff.azurewebsites.net',
  );

  // Base URL for the upstream API (used for resolving /uploads/* URLs).
  // Defaults to the local dev API port.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Defaults to Azure production. For local dev, override via:
    //   --dart-define=API_BASE_URL=http://192.168.1.38:5132
    defaultValue: 'https://rmap-prod-api.azurewebsites.net',
  );

  // Optional explicit overrides (empty when not provided).
  static const String apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL');
  static const String uploadsBaseUrlOverride =
      String.fromEnvironment('UPLOADS_BASE_URL');

  /// Azure CDN/Front Door base URL for serving images.
  /// When configured, images are served from the global CDN edge.
  /// Override via: --dart-define=CDN_BASE_URL=https://rmap-images-xxx.azurefd.net
  static const String cdnBaseUrl = String.fromEnvironment(
    'CDN_BASE_URL',
    defaultValue: '',
  );

  // Base URL for serving uploaded media (usually the API host).
  static const String uploadsBaseUrl = String.fromEnvironment(
    'UPLOADS_BASE_URL',
    defaultValue: apiBaseUrl,
  );

  /// Toggle custom Firebase Performance traces.
  ///
  /// Enabled by default. Override via:
  ///   --dart-define=ENABLE_FIREBASE_PERF_TRACES=false
  static const bool enableFirebasePerfTraces = bool.fromEnvironment(
    'ENABLE_FIREBASE_PERF_TRACES',
    defaultValue: false,
  );

  /// Resolved base URL used for `/uploads/*` media.
  ///
  /// Why this exists:
  /// - On Android emulators `10.0.2.2` is correct.
  /// - On real devices, if only `MOBILE_BFF_BASE_URL` is provided, the default
  ///   `API_BASE_URL` (`10.0.2.2`) is wrong, causing images to fail to load.
  ///
  /// Precedence:
  /// 1) `CDN_BASE_URL` (Azure Front Door CDN for fastest global delivery)
  /// 2) `UPLOADS_BASE_URL`
  /// 3) `API_BASE_URL`
  /// 4) Derived from `MOBILE_BFF_BASE_URL` (preferred for real devices)
  /// 5) Default `uploadsBaseUrl`
  static String get effectiveUploadsBaseUrl {
    // CDN takes highest priority for optimal performance
    final cdn = cdnBaseUrl.trim();
    if (cdn.isNotEmpty) return cdn;

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

  /// Returns true if CDN is configured for image delivery.
  static bool get isCdnConfigured => cdnBaseUrl.trim().isNotEmpty;

  /// Returns the CDN URL if configured, null otherwise.
  static String? get effectiveCdnBaseUrl {
    final cdn = cdnBaseUrl.trim();
    return cdn.isNotEmpty ? cdn : null;
  }
}
