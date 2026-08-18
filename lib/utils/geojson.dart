import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeoJson {
  GeoJson._();

  /// Encodes a [Polygon] GeoJSON from a list of [LatLng] points.
  /// Returns null if fewer than 3 points are supplied.
  static String? polygonToGeoJson(List<LatLng> points) {
    if (points.length < 4) return null;

    final ring = <List<double>>[];
    for (final p in points) {
      ring.add(<double>[p.longitude, p.latitude]);
    }

    final first = points.first;
    final last = points.last;
    if (first.latitude != last.latitude || first.longitude != last.longitude) {
      ring.add(<double>[first.longitude, first.latitude]);
    }

    final geometry = <String, dynamic>{
      'type': 'Polygon',
      'coordinates': [ring],
    };

    return jsonEncode(geometry);
  }

  static List<Map<String, dynamic>> _extractGeometries(Object decoded) {
    if (decoded is! Map) return const <Map<String, dynamic>>[];
    final map = decoded.cast<String, dynamic>();

    final type = (map['type'] as String?) ?? (map['Type'] as String?);
    final t = type?.toLowerCase();

    if (t == 'feature') {
      final geometry = map['geometry'] ?? map['Geometry'];
      if (geometry is Map) {
        return <Map<String, dynamic>>[geometry.cast<String, dynamic>()];
      }
      return const <Map<String, dynamic>>[];
    }

    if (t == 'featurecollection') {
      final features = map['features'] ?? map['Features'];
      if (features is! List) return const <Map<String, dynamic>>[];
      final geometries = <Map<String, dynamic>>[];
      for (final feature in features) {
        if (feature is! Map) continue;
        final g = feature['geometry'] ?? feature['Geometry'];
        if (g is Map) {
          geometries.add(g.cast<String, dynamic>());
        }
      }
      return geometries;
    }

    // Assume it's already a geometry object.
    return <Map<String, dynamic>>[map];
  }

  /// Parses a GeoJSON Point and returns a [LatLng].
  ///
  /// Supported shape:
  /// `{ "type": "Point", "coordinates": [lng, lat] }`
  static LatLng? tryParsePoint(String? geoJson) {
    if (geoJson == null || geoJson.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(geoJson);
      final geometries = _extractGeometries(decoded);
      if (geometries.isEmpty) return null;

      final geometry = geometries.first;
      final type =
          (geometry['type'] as String?) ?? (geometry['Type'] as String?);
      if (type?.toLowerCase() != 'point') return null;

      final coords = geometry['coordinates'] ?? geometry['Coordinates'];
      if (coords is! List || coords.length < 2) return null;

      final lng = _asDouble(coords[0]);
      final lat = _asDouble(coords[1]);
      if (lat == null || lng == null) return null;

      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  /// Parses a GeoJSON Polygon or MultiPolygon.
  ///
  /// Returns a list of polygons, where each polygon is a list of [LatLng] points.
  /// Holes are currently ignored (only the outer ring is used).
  static List<List<LatLng>> tryParsePolygons(String? geoJson) {
    if (geoJson == null || geoJson.trim().isEmpty) {
      return const <List<LatLng>>[];
    }

    try {
      final decoded = jsonDecode(geoJson);
      final geometries = _extractGeometries(decoded);
      if (geometries.isEmpty) return const <List<LatLng>>[];

      final result = <List<LatLng>>[];
      for (final geometry in geometries) {
        final type =
            (geometry['type'] as String?) ?? (geometry['Type'] as String?);
        final t = type?.toLowerCase();
        final coords = geometry['coordinates'] ?? geometry['Coordinates'];

        if (t == 'polygon') {
          final outer = _parsePolygonOuterRing(coords);
          if (outer.isNotEmpty) {
            result.add(outer);
          }
          continue;
        }

        if (t == 'multipolygon') {
          if (coords is! List) continue;
          for (final polygonCoords in coords) {
            final outer = _parsePolygonOuterRing(polygonCoords);
            if (outer.isNotEmpty) {
              result.add(outer);
            }
          }
          continue;
        }
      }

      return result;
    } catch (_) {
      return const <List<LatLng>>[];
    }
  }

  /// Parses a GeoJSON LineString or MultiLineString.
  ///
  /// Returns a list of line strings, where each line is a list of [LatLng] points.
  static List<List<LatLng>> tryParseLineStrings(String? geoJson) {
    if (geoJson == null || geoJson.trim().isEmpty) {
      return const <List<LatLng>>[];
    }

    try {
      final decoded = jsonDecode(geoJson);
      final geometries = _extractGeometries(decoded);
      if (geometries.isEmpty) return const <List<LatLng>>[];

      final result = <List<LatLng>>[];
      for (final geometry in geometries) {
        final type =
            (geometry['type'] as String?) ?? (geometry['Type'] as String?);
        final t = type?.toLowerCase();
        final coords = geometry['coordinates'] ?? geometry['Coordinates'];

        if (t == 'linestring') {
          final line = _parseLineString(coords);
          if (line.isNotEmpty) {
            result.add(line);
          }
          continue;
        }

        if (t == 'multilinestring') {
          if (coords is! List) continue;
          for (final lineCoords in coords) {
            final line = _parseLineString(lineCoords);
            if (line.isNotEmpty) {
              result.add(line);
            }
          }
          continue;
        }
      }

      return result;
    } catch (_) {
      return const <List<LatLng>>[];
    }
  }

  static List<LatLng> _parseLineString(Object? lineCoordinates) {
    // LineString coordinates: [ [lng,lat], [lng,lat], ... ]
    if (lineCoordinates is! List || lineCoordinates.isEmpty) {
      return const <LatLng>[];
    }

    final points = <LatLng>[];
    for (final pair in lineCoordinates) {
      if (pair is! List || pair.length < 2) continue;
      final lng = _asDouble(pair[0]);
      final lat = _asDouble(pair[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    return points;
  }

  static List<LatLng> _parsePolygonOuterRing(Object? polygonCoordinates) {
    // Polygon coordinates: [ [ [lng,lat], [lng,lat], ... ] , [hole...], ...]
    if (polygonCoordinates is! List || polygonCoordinates.isEmpty) {
      return const <LatLng>[];
    }

    final outerRing = polygonCoordinates.first;
    if (outerRing is! List || outerRing.isEmpty) {
      return const <LatLng>[];
    }

    final points = <LatLng>[];
    for (final pair in outerRing) {
      if (pair is! List || pair.length < 2) continue;
      final lng = _asDouble(pair[0]);
      final lat = _asDouble(pair[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    // google_maps_flutter will close the polygon automatically.
    return points;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
