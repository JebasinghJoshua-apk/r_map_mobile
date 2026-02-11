import 'dart:convert';
import 'package:http/http.dart' as http;

class IpGeolocationResult {
  final double latitude;
  final double longitude;
  final String? city;
  final String? region;
  final String? country;

  const IpGeolocationResult({
    required this.latitude,
    required this.longitude,
    this.city,
    this.region,
    this.country,
  });
}

/// Fetches approximate location based on the user's IP address.
/// No permissions required, city-level accuracy (~1-5km).
class IpGeolocationService {
  static const Duration _timeout = Duration(seconds: 3);

  /// Returns the user's approximate location based on IP, or null if unavailable.
  static Future<IpGeolocationResult?> getLocation() async {
    try {
      // Using ip-api.com (free, no API key required, 45 requests/minute limit)
      final response = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=status,lat,lon,city,regionName,country'))
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;

      final lat = data['lat'];
      final lon = data['lon'];
      if (lat == null || lon == null) return null;

      return IpGeolocationResult(
        latitude: (lat as num).toDouble(),
        longitude: (lon as num).toDouble(),
        city: data['city'] as String?,
        region: data['regionName'] as String?,
        country: data['country'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
