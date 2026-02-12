/// Lightweight layout boundary preview for quick polygon rendering
/// while full viewport data loads.
class LayoutBoundaryPreview {
  const LayoutBoundaryPreview({
    required this.layoutId,
    required this.propertyId,
    required this.name,
    this.boundaryGeoJson,
    this.centerGeoJson,
    this.centerLatitude,
    this.centerLongitude,
    this.focusZoomLevel,
    this.plotCount = 0,
    this.area,
    this.location,
  });

  final String layoutId;
  final String propertyId;
  final String name;
  final String? boundaryGeoJson;
  final String? centerGeoJson;
  final double? centerLatitude;
  final double? centerLongitude;
  final double? focusZoomLevel;
  final int plotCount;
  final String? area;
  final String? location;

  static LayoutBoundaryPreview fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return LayoutBoundaryPreview(
      layoutId: (json['layoutId'] ?? '').toString(),
      propertyId: (json['propertyId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      boundaryGeoJson: json['boundaryGeoJson']?.toString(),
      centerGeoJson: json['centerGeoJson']?.toString(),
      centerLatitude: asDouble(json['centerLatitude']),
      centerLongitude: asDouble(json['centerLongitude']),
      focusZoomLevel: asDouble(json['focusZoomLevel']),
      plotCount: asInt(json['plotCount']),
      area: json['area']?.toString(),
      location: json['location']?.toString(),
    );
  }
}
