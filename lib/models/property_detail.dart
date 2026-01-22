class PropertyDetail {
  const PropertyDetail({
    required this.id,
    required this.propertyBoundaryGeoJson,
    required this.centerPointGeoJson,
  });

  final String id;
  final String? propertyBoundaryGeoJson;
  final String? centerPointGeoJson;

  static PropertyDetail fromJson(Map<String, dynamic> json) {
    return PropertyDetail(
      id: (json['id'] as String?) ?? '',
      propertyBoundaryGeoJson: json['propertyBoundaryGeoJson'] as String?,
      centerPointGeoJson: json['centerPointGeoJson'] as String?,
    );
  }
}
