class ApiConstants {
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

  // Base URL for serving uploaded media (usually the API host).
  static const String uploadsBaseUrl = String.fromEnvironment(
    'UPLOADS_BASE_URL',
    defaultValue: apiBaseUrl,
  );
}
