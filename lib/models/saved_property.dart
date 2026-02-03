import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geojson.dart';

class SavedProperty {
  const SavedProperty({
    required this.id,
    required this.propertyId,
    required this.savedAt,
    required this.property,
  });

  final String id;
  final String propertyId;
  final DateTime savedAt;
  final SavedPropertyProperty property;

  static SavedProperty fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return SavedProperty(
      id: (json['id'] as String?) ?? '',
      propertyId: (json['propertyId'] as String?) ?? '',
      savedAt: parseDate(json['savedAt']),
      property: SavedPropertyProperty.fromJson(
        (json['property'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class SavedPropertyProperty {
  const SavedPropertyProperty({
    required this.id,
    required this.name,
    required this.propertyTypeName,
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
  final String name;
  final String? propertyTypeName;

  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? pinCode;

  final String? centerPointGeoJson;
  final int? plotsCount;
  final bool? isApproved;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  LatLng? get centerPoint => GeoJson.tryParsePoint(centerPointGeoJson);

  String get locationLabel {
    final parts = <String>[];
    void add(String? value) {
      final t = (value ?? '').trim();
      if (t.isNotEmpty) parts.add(t);
    }

    add(address);
    add(city);
    add(state);
    add(pinCode);
    add(country);

    return parts.join(', ');
  }

  static SavedPropertyProperty fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return SavedPropertyProperty(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      propertyTypeName: (json['propertyTypeName'] as String?),
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      pinCode: json['pinCode'] as String?,
      centerPointGeoJson: json['centerPointGeoJson'] as String?,
      plotsCount: json['plotsCount'] as int?,
      isApproved: json['isApproved'] as bool?,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }
}
