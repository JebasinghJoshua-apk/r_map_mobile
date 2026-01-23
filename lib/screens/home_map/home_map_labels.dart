part of '../home_map_screen.dart';

extension _HomeMapLabels on _HomeMapScreenState {
  Future<_LabelMarkerResult> _buildLabelMarkers({
    required MapViewportResponse response,
    required double zoom,
    required double pixelRatio,
  }) async {
    final shouldShowPlotLabels = zoom >= _minPlotLabelZoom;
    final shouldShowRoadLabels = zoom >= _minRoadLabelZoom;
    final shouldShowAmenityLabels = zoom >= _minAmenityLabelZoom;
    if (!shouldShowPlotLabels &&
        !shouldShowRoadLabels &&
        !shouldShowAmenityLabels) {
      return const _LabelMarkerResult(
        plotLabelMarkers: <Marker>{},
        roadLabelMarkers: <Marker>{},
        amenityLabelMarkers: <Marker>{},
      );
    }

    final nextPlotLabels = <Marker>{};
    final nextRoadLabels = <Marker>{};
    final nextAmenityLabels = <Marker>{};
    var totalLabels = 0;

    const defaultShadows = <Shadow>[
      Shadow(
        color: Color(0xD0000000),
        blurRadius: 3,
        offset: Offset(0, 0),
      ),
    ];

    if (shouldShowPlotLabels) {
      final plotFontSize = _plotLabelFontSize(zoom);
      for (final plot in response.plots) {
        if (totalLabels >= _maxLabelMarkers) break;

        final label = plot.plotNumber.trim();
        if (label.isEmpty) continue;

        final pos = plot.centerPoint;
        if (pos == null) continue;

        final icon = await _iconFactory.getTextLabelIcon(
          text: label,
          pixelRatio: pixelRatio,
          fontSize: plotFontSize,
          textColor: Colors.white,
          shadows: defaultShadows,
          backgroundColor: null,
          padding: EdgeInsets.zero,
          borderRadius: 0,
        );

        nextPlotLabels.add(
          Marker(
            markerId: MarkerId('plot-label:${plot.plotId}'),
            position: pos,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndex: 120,
            // Plot labels sit above polygons. If we let taps fall through, the
            // map's `onTap` handler can fire and immediately close the panel.
            // Make the label itself open the same plot details panel.
            onTap: () => _handlePlotTapped(plot),
            consumeTapEvents: true,
            infoWindow: InfoWindow.noText,
          ),
        );
        totalLabels++;
      }
    }

    if (shouldShowRoadLabels) {
      final roadFontSize = _roadLabelFontSize(zoom);
      for (final road in response.roads) {
        if (totalLabels >= _maxLabelMarkers) break;

        final name = road.name.trim();
        if (name.isEmpty) continue;

        _LineLabelPlacement? placement;

        final lines = GeoJson.tryParseLineStrings(road.roadGeoJson);
        if (lines.isNotEmpty) {
          placement = _computeLineLabelPlacement(lines.first);
        } else {
          final polygons = GeoJson.tryParsePolygons(road.roadGeoJson);
          if (polygons.isNotEmpty) {
            placement = _computeLineLabelPlacement(polygons.first);
          }
        }

        if (placement == null) continue;

        final icon = await _iconFactory.getTextLabelIcon(
          text: name,
          pixelRatio: pixelRatio,
          fontSize: roadFontSize,
          textColor: Colors.white,
          shadows: defaultShadows,
          backgroundColor: null,
          padding: EdgeInsets.zero,
          borderRadius: 0,
        );

        nextRoadLabels.add(
          Marker(
            markerId: MarkerId('road-label:${road.roadId}'),
            position: placement.position,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndex: 110,
            rotation: placement.rotationDegrees,
            flat: true,
            consumeTapEvents: false,
          ),
        );
        totalLabels++;
      }
    }

    if (shouldShowAmenityLabels) {
      for (final amenity in response.amenities) {
        if (totalLabels >= _maxLabelMarkers) break;

        final label = _amenityLabelText(amenity);
        if (label.isEmpty) continue;

        final amenityFontSize = _amenityLabelFontSize(amenity, label, zoom);

        final polygons = GeoJson.tryParsePolygons(amenity.boundaryGeoJson);
        if (polygons.isEmpty) continue;

        final pos = _centroid(polygons.first);
        if (pos == null) continue;

        final icon = await _iconFactory.getTextLabelIcon(
          text: label,
          pixelRatio: pixelRatio,
          fontSize: amenityFontSize,
          textColor: Colors.white,
          shadows: defaultShadows,
          backgroundColor: null,
          padding: EdgeInsets.zero,
          borderRadius: 0,
        );

        nextAmenityLabels.add(
          Marker(
            markerId: MarkerId('amenity-label:${amenity.amenityId}'),
            position: pos,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndex: 105,
            consumeTapEvents: false,
          ),
        );
        totalLabels++;
      }
    }

    return _LabelMarkerResult(
      plotLabelMarkers: Set<Marker>.unmodifiable(nextPlotLabels),
      roadLabelMarkers: Set<Marker>.unmodifiable(nextRoadLabels),
      amenityLabelMarkers: Set<Marker>.unmodifiable(nextAmenityLabels),
    );
  }

  double _amenityLabelFontSize(
    MapAmenityFeature amenity,
    String label,
    double zoom,
  ) {
    final rawName = amenity.name.trim();
    final name = rawName.isNotEmpty ? rawName : label.trim();
    final isPark = name.toLowerCase().startsWith('park');
    if (!isPark) return _roadLabelFontSize(zoom);

    // Park-only stepped scaling by zoom level.
    // zoom < 18.5  -> 10
    // zoom >= 18.5 -> 14
    // zoom >= 19.0 -> 18
    // zoom >= 19.4 -> 22
    // zoom >= 19.8 -> 26
    // zoom >= 20.0 -> 30
    // zoom >= 20.2 -> 34
    // zoom >= 20.5 -> 38
    // zoom >= 20.7 -> 42
    if (zoom >= 20.7) return 42;
    if (zoom >= 20.5) return 38;
    if (zoom >= 20.2) return 34;
    if (zoom >= 20.0) return 30;
    if (zoom >= 19.8) return 26;
    if (zoom >= 19.4) return 22;
    if (zoom >= 19.0) return 18;
    if (zoom >= 18.5) return 14;
    return 10;
  }

  String _amenityLabelText(MapAmenityFeature amenity) {
    final name = amenity.name.trim();
    if (name.isNotEmpty) return name;

    final meta = amenity.metadata;
    for (final key in const <String>[
      'code',
      'shortName',
      'short_name',
      'abbr',
      'type',
      'name',
    ]) {
      final v = meta[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  double _plotLabelFontSize(double zoom) {
    // Plot-only stepped scaling by zoom level.
    // zoom < 18.5  -> 8
    // zoom >= 18.5 -> 10
    // zoom >= 19.0 -> 12
    // zoom >= 19.4 -> 13
    // zoom >= 19.8 -> 14
    // zoom >= 20.0 -> 15
    // zoom >= 20.2 -> 16
    // zoom >= 20.5 -> 17
    // zoom >= 20.7 -> 18
    if (zoom >= 20.7) return 18;
    if (zoom >= 20.5) return 17;
    if (zoom >= 20.2) return 16;
    if (zoom >= 20.0) return 15;
    if (zoom >= 19.8) return 14;
    if (zoom >= 19.4) return 13;
    if (zoom >= 19.0) return 12;
    if (zoom >= 18.5) return 10;
    return 8;
  }

  double _roadLabelFontSize(double zoom) {
    // Stepped scaling by zoom level.
    // 18.0  -> 8
    // 18.5  -> 9
    // 19.0  -> 10
    // 19.4  -> 11
    // 19.8  -> 12
    // 20.0  -> 13
    // 20.2  -> 14
    // 20.5  -> 15
    // 20.7  -> 16
    if (zoom >= 20.7) return 16;
    if (zoom >= 20.5) return 15;
    if (zoom >= 20.2) return 14;
    if (zoom >= 20.0) return 13;
    if (zoom >= 19.8) return 12;
    if (zoom >= 19.4) return 11;
    if (zoom >= 19.0) return 10;
    if (zoom >= 18.5) return 9;
    return 8;
  }

  _LineLabelPlacement? _computeLineLabelPlacement(List<LatLng> points) {
    if (points.length < 2) return null;

    // 1) Rotation: use a dominant direction (best-fit) over the whole geometry
    // to avoid slight deviations on segmented/curved lines.
    final dominantRotation = _dominantRotationDegrees(points);
    if (dominantRotation == null) return null;

    // 2) Position: use the half-length point along the line for polylines;
    // for closed rings (polygons), use centroid to avoid placing on an edge.
    final isClosedRing = _isClosedRing(points);
    final pos = isClosedRing
        ? _centroid(points)
        : (_pointAtFraction(points, 0.5) ?? _centroid(points));
    if (pos == null) return null;

    return _LineLabelPlacement(
        position: pos, rotationDegrees: dominantRotation);
  }

  bool _isClosedRing(List<LatLng> points) {
    if (points.length < 4) return false;
    final a = points.first;
    final b = points.last;
    return (a.latitude - b.latitude).abs() < 1e-9 &&
        (a.longitude - b.longitude).abs() < 1e-9;
  }

  LatLng? _centroid(List<LatLng> points) {
    if (points.isEmpty) return null;
    var sumLat = 0.0;
    var sumLng = 0.0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  LatLng? _pointAtFraction(List<LatLng> points, double fraction) {
    if (points.length < 2) return null;
    if (fraction <= 0) return points.first;
    if (fraction >= 1) return points.last;

    // Use a quick equirectangular distance approximation.
    final lat0 = (points.first.latitude + points.last.latitude) / 2;
    final cosLat0 = math.cos(_degToRad(lat0));

    double dist(LatLng a, LatLng b) {
      final dLat = (b.latitude - a.latitude);
      final dLng = (b.longitude - a.longitude) * cosLat0;
      return math.sqrt(dLat * dLat + dLng * dLng);
    }

    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += dist(points[i], points[i + 1]);
    }
    if (total <= 0) return null;

    final target = total * fraction;
    var acc = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final seg = dist(a, b);
      if (seg <= 0) continue;
      if (acc + seg >= target) {
        final t = (target - acc) / seg;
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
      acc += seg;
    }
    return points[points.length ~/ 2];
  }

  double? _dominantRotationDegrees(List<LatLng> points) {
    if (points.length < 2) return null;

    // Project to local-ish coordinates: x = lng*cos(lat0), y = lat.
    final lat0 =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final cosLat0 = math.cos(_degToRad(lat0));

    var meanX = 0.0;
    var meanY = 0.0;
    for (final p in points) {
      meanX += p.longitude * cosLat0;
      meanY += p.latitude;
    }
    meanX /= points.length;
    meanY /= points.length;

    var sxx = 0.0;
    var syy = 0.0;
    var sxy = 0.0;
    for (final p in points) {
      final x = p.longitude * cosLat0 - meanX;
      final y = p.latitude - meanY;
      sxx += x * x;
      syy += y * y;
      sxy += x * y;
    }

    // If variance is tiny, fallback to first/last bearing.
    if ((sxx + syy) <= 1e-12) {
      final a = points.first;
      final b = points.last;
      final bearingFromNorth = _bearingDegrees(a, b);
      var rotation = (bearingFromNorth - 90 + 360) % 360;
      if (rotation > 90 && rotation < 270) {
        rotation = (rotation + 180) % 360;
      }
      return rotation;
    }

    // PCA angle of principal axis, radians from +x (east), CCW.
    final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final angleDeg = _radToDeg(angle);

    // Convert to marker rotation: 0 means east/west text, positive clockwise.
    var rotation = (-angleDeg + 360) % 360;
    if (rotation > 90 && rotation < 270) {
      rotation = (rotation + 180) % 360;
    }
    return rotation;
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    final deg = (_radToDeg(brng) + 360) % 360;
    return deg;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;
  double _radToDeg(double rad) => rad * 180.0 / math.pi;
}
