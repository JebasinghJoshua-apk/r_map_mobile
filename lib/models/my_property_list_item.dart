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
    required this.isApproved,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String propertyId;
  final String name;
  final String propertyType;

  final String address;
  final String city;
  final String state;
  final String country;
  final String pinCode;

  final String? centerPointGeoJson;

  final int? plotsCount;

  final bool isApproved;
  final DateTime createdAt;
  final DateTime updatedAt;

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
      propertyId: (propertyId == null || propertyId.trim().isEmpty)
          ? id
          : propertyId,
      name: (json['name'] as String?) ?? '',
      propertyType: (json['propertyType'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      state: (json['state'] as String?) ?? '',
      country: (json['country'] as String?) ?? '',
      pinCode: (json['pinCode'] as String?) ?? '',
      centerPointGeoJson: json['centerPointGeoJson'] as String?,
      plotsCount: json['plotsCount'] as int?,
      isApproved: (json['isApproved'] as bool?) ?? false,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }
}
