class ApiConstants {
  static const String mobileBffBaseUrl = String.fromEnvironment(
    'MOBILE_BFF_BASE_URL',
    // For Android emulators, host machine is available at 10.0.2.2.
    // For physical devices, pass your LAN IP via --dart-define.
    defaultValue: 'http://10.0.2.2:5150',
  );
}
