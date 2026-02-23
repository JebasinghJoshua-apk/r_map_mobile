import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geojson.dart';

class MyPropertyListItem {
  const MyPropertyListItem({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.propertyType,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    required this.pinCode,
    required this.centerPointGeoJson,
    required this.plotsCount,
    required this.approvalStatus,
    required this.createdAt,
    required this.updatedAt,
    this.shortCode,
  });

  final String id;
  final String propertyId;
  final String name;
  final String propertyType;

  /// Short code for QR URLs (e.g., "A3x9Kp" → rmap.in/s/A3x9Kp)
  final String? shortCode;

  final String address;
  final String city;
  final String state;
  final String country;
  final String pinCode;

  final String? centerPointGeoJson;

  final int? plotsCount;

  final String approvalStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the property is approved (approvalStatus == "Approved")
  bool get isApproved => approvalStatus.toLowerCase() == 'approved';

  LatLng? get centerPoint => GeoJson.tryParsePoint(centerPointGeoJson);

  String get locationLabel {
    final parts = <String>[];
    if (address.trim().isNotEmpty) parts.add(address.trim());
    if (city.trim().isNotEmpty) parts.add(city.trim());
    if (state.trim().isNotEmpty) parts.add(state.trim());
    if (pinCode.trim().isNotEmpty) parts.add(pinCode.trim());
    if (country.trim().isNotEmpty) parts.add(country.trim());
    return parts.join(', ');
  }

  static MyPropertyListItem fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final id = (json['id'] as String?) ?? '';
    final propertyId =
        (json['propertyId'] as String?) ?? (json['PropertyId'] as String?);

    return MyPropertyListItem(
      id: id,
      propertyId:
          (propertyId == null || propertyId.trim().isEmpty) ? id : propertyId,
      name: (json['name'] as String?) ?? '',
      propertyType: (json['propertyType'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      state: (json['state'] as String?) ?? '',
      country: (json['country'] as String?) ?? '',
      pinCode: (json['pinCode'] as String?) ?? '',
      centerPointGeoJson: json['centerPointGeoJson'] as String?,
      plotsCount: json['plotsCount'] as int?,
      approvalStatus: (json['approvalStatus'] as String?) ?? 'Pending',
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      shortCode: json['shortCode'] as String?,
    );
  }
}
