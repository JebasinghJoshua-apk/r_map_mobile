import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_viewport_models.dart';

LatLng? parseLayoutMapFocusPoint(String? geoJson) {
  if (geoJson == null || geoJson.trim().isEmpty) return null;
  try {
    final point = jsonDecode(geoJson);
    if (point is Map<String, dynamic> && point['type'] == 'Point') {
      final coordinates = point['coordinates'];
      if (coordinates is List && coordinates.length == 2) {
        final lng = coordinates[0];
        final lat = coordinates[1];
        if (lng is num &&
            lat is num &&
            lng.isFinite &&
            lat.isFinite &&
            lng >= -180 &&
            lng <= 180 &&
            lat >= -90 &&
            lat <= 90) {
          return LatLng(lat.toDouble(), lng.toDouble());
        }
      }
    }
  } on FormatException catch (error) {
    debugPrint('[MapFocus] Invalid GeoJSON: $error');
    return null;
  }
  debugPrint('[MapFocus] Expected a Point with valid longitude and latitude');
  return null;
}

class LayoutMapFocus {
  const LayoutMapFocus({
    required this.target,
    required this.zoom,
    required this.boundaryGeoJson,
  });

  factory LayoutMapFocus.resolve(
    MapPropertyFeature feature, {
    required LatLng fallbackTarget,
    required double fallbackZoom,
    required double? configuredZoom,
  }) {
    final focusPoint = feature.propertyType.trim() == 'Layout'
        ? parseLayoutMapFocusPoint(feature.metadata['mapFocusPoint'])
        : null;
    return LayoutMapFocus(
      target: focusPoint ??
          (configuredZoom != null
              ? feature.centerPoint ?? fallbackTarget
              : fallbackTarget),
      zoom: configuredZoom ?? fallbackZoom,
      // Fitting the boundary would override the explicitly selected focus point.
      boundaryGeoJson: focusPoint == null && configuredZoom == null
          ? feature.boundaryGeoJson
          : null,
    );
  }

  final LatLng target;
  final double zoom;
  final String? boundaryGeoJson;
}
