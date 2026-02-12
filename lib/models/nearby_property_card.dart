class NearbyPropertyCard {
  const NearbyPropertyCard({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.hasLocation,
    required this.propertyType,
    required this.address,
    required this.city,
    required this.totalArea,
    required this.pricePerSqFt,
    required this.area,
    required this.plotsCount,
    required this.focusZoomLevel,
    required this.boundaryGeoJson,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final bool hasLocation;
  final String propertyType;
  final String address;
  final String city;
  final double? totalArea;
  final double? pricePerSqFt;
  final String? area;
  final int? plotsCount;
  final double? focusZoomLevel;
  final String? boundaryGeoJson;
  final double latitude;
  final double longitude;

  static NearbyPropertyCard fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'];
    DateTime createdAt;
    if (createdAtRaw is String && createdAtRaw.trim().isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw)?.toLocal() ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return NearbyPropertyCard(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      createdAt: createdAt,
      hasLocation: (json['hasLocation'] as bool?) ?? false,
      propertyType: (json['propertyType'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      totalArea: asDouble(json['totalArea']),
      pricePerSqFt: asDouble(json['pricePerSqFt']),
      area: json['area']?.toString(),
      plotsCount: asInt(json['plotsCount']),
      focusZoomLevel: asDouble(json['focusZoomLevel']),
      boundaryGeoJson: json['boundaryGeoJson']?.toString(),
      latitude: asDouble(json['latitude']) ?? 0,
      longitude: asDouble(json['longitude']) ?? 0,
    );
  }
}
