class PropertyDetail {
  const PropertyDetail({
    required this.id,
    required this.propertyBoundaryGeoJson,
    required this.centerPointGeoJson,
    this.totalArea,
    this.pricePerSqFt,
  });

  final String id;
  final String? propertyBoundaryGeoJson;
  final String? centerPointGeoJson;

  /// Total area in square feet, when available from the backend.
  final double? totalArea;

  /// Price per square foot, when available from the backend.
  final double? pricePerSqFt;

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static PropertyDetail fromJson(Map<String, dynamic> json) {
    return PropertyDetail(
      id: (json['id'] as String?) ?? '',
      propertyBoundaryGeoJson: json['propertyBoundaryGeoJson'] as String?,
      centerPointGeoJson: json['centerPointGeoJson'] as String?,
      totalArea: _asDouble(json['totalArea']),
      pricePerSqFt: _asDouble(json['pricePerSqFt']),
    );
  }
}
