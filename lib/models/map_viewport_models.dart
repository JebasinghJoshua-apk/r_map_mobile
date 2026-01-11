import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/geojson.dart';

enum MapDetailLevel {
  minimal,
  summary,
  detailed,
  unknown,
}

MapDetailLevel mapDetailLevelFromJson(Object? value) {
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'minimal':
        return MapDetailLevel.minimal;
      case 'summary':
        return MapDetailLevel.summary;
      case 'detailed':
        return MapDetailLevel.detailed;
    }
  }
  return MapDetailLevel.unknown;
}

class MapViewportResponse {
  const MapViewportResponse({
    required this.detailLevel,
    required this.properties,
    required this.plots,
    required this.roads,
    required this.amenities,
  });

  final MapDetailLevel detailLevel;
  final List<MapPropertyFeature> properties;
  final List<MapPlotFeature> plots;
  final List<MapRoadFeature> roads;
  final List<MapAmenityFeature> amenities;

  static MapViewportResponse fromJson(Map<String, dynamic> json) {
    final props = _asList(json['properties']).map(MapPropertyFeature.fromJson);
    final plots = _asList(json['plots']).map(MapPlotFeature.fromJson);
    final roads = _asList(json['roads']).map(MapRoadFeature.fromJson);
    final amenities =
        _asList(json['amenities']).map(MapAmenityFeature.fromJson);

    return MapViewportResponse(
      detailLevel: mapDetailLevelFromJson(json['detailLevel']),
      properties: props.toList(growable: false),
      plots: plots.toList(growable: false),
      roads: roads.toList(growable: false),
      amenities: amenities.toList(growable: false),
    );
  }
}

class MapPropertyFeature {
  const MapPropertyFeature({
    required this.propertyId,
    required this.featureId,
    required this.propertyType,
    required this.name,
    required this.isOwnedByCurrentUser,
    required this.listingType,
    required this.boundaryGeoJson,
    required this.centerGeoJson,
    required this.metadata,
  });

  final String propertyId;
  final String featureId;
  final String propertyType;
  final String name;
  final bool isOwnedByCurrentUser;
  final String? listingType;
  final String? boundaryGeoJson;
  final String? centerGeoJson;
  final Map<String, String?> metadata;

  LatLng? get centerPoint => GeoJson.tryParsePoint(centerGeoJson);

  static MapPropertyFeature fromJson(Map<String, dynamic> json) {
    return MapPropertyFeature(
      propertyId: (json['propertyId'] as String?) ?? '',
      featureId: (json['featureId'] as String?) ?? '',
      propertyType: (json['propertyType'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      isOwnedByCurrentUser: (json['isOwnedByCurrentUser'] as bool?) ?? false,
      listingType: json['listingType'] as String?,
      boundaryGeoJson: json['boundaryGeoJson'] as String?,
      centerGeoJson: json['centerGeoJson'] as String?,
      metadata: _asStringMap(json['metadata']),
    );
  }
}

class MapPlotFeature {
  const MapPlotFeature({
    required this.plotId,
    required this.layoutId,
    required this.individualPlotsId,
    required this.plotNumber,
    required this.boundaryGeoJson,
    required this.centerGeoJson,
    required this.metadata,
  });

  final String plotId;
  final String? layoutId;
  final String? individualPlotsId;
  final String plotNumber;
  final String? boundaryGeoJson;
  final String? centerGeoJson;
  final Map<String, String?> metadata;

  LatLng? get centerPoint => GeoJson.tryParsePoint(centerGeoJson);

  static MapPlotFeature fromJson(Map<String, dynamic> json) {
    return MapPlotFeature(
      plotId: (json['plotId'] as String?) ?? '',
      layoutId: json['layoutId'] as String?,
      individualPlotsId: json['individualPlotsId'] as String?,
      plotNumber: (json['plotNumber'] as String?) ?? '',
      boundaryGeoJson: json['boundaryGeoJson'] as String?,
      centerGeoJson: json['centerGeoJson'] as String?,
      metadata: _asStringMap(json['metadata']),
    );
  }
}

class MapRoadFeature {
  const MapRoadFeature({
    required this.roadId,
    required this.layoutId,
    required this.individualPlotsId,
    required this.landId,
    required this.commercialSpaceId,
    required this.name,
    required this.widthInFeet,
    required this.roadGeoJson,
    required this.metadata,
  });

  final String roadId;
  final String? layoutId;
  final String? individualPlotsId;
  final String? landId;
  final String? commercialSpaceId;
  final String name;
  final int? widthInFeet;
  final String? roadGeoJson;
  final Map<String, String?> metadata;

  static MapRoadFeature fromJson(Map<String, dynamic> json) {
    return MapRoadFeature(
      roadId: (json['roadId'] as String?) ?? '',
      layoutId: json['layoutId'] as String?,
      individualPlotsId: json['individualPlotsId'] as String?,
      landId: json['landId'] as String?,
      commercialSpaceId: json['commercialSpaceId'] as String?,
      name: (json['name'] as String?) ?? '',
      widthInFeet: _asInt(json['widthInFeet']),
      roadGeoJson: json['roadGeoJson'] as String?,
      metadata: _asStringMap(json['metadata']),
    );
  }
}

class MapAmenityFeature {
  const MapAmenityFeature({
    required this.amenityId,
    required this.layoutId,
    required this.name,
    required this.boundaryGeoJson,
    required this.metadata,
  });

  final String amenityId;
  final String layoutId;
  final String name;
  final String? boundaryGeoJson;
  final Map<String, String?> metadata;

  static MapAmenityFeature fromJson(Map<String, dynamic> json) {
    return MapAmenityFeature(
      amenityId: (json['amenityId'] as String?) ?? '',
      layoutId: (json['layoutId'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      boundaryGeoJson: json['boundaryGeoJson'] as String?,
      metadata: _asStringMap(json['metadata']),
    );
  }
}

Iterable<Map<String, dynamic>> _asList(Object? value) {
  if (value is List) {
    return value.whereType<Map>().map((e) => e.cast<String, dynamic>());
  }
  return const Iterable.empty();
}

Map<String, String?> _asStringMap(Object? value) {
  if (value is Map) {
    final casted = value.cast<String, dynamic>();
    return casted.map((key, v) => MapEntry(key, v?.toString()));
  }
  return <String, String?>{};
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
