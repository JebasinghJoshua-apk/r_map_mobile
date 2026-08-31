part of '../home_map_screen.dart';

extension _HomeMapLabels on _HomeMapScreenState {
  Future<_LabelMarkerResult> _buildLabelMarkers({
    required MapViewportResponse response,
    required double zoom,
    required double pixelRatio,
    bool isHybrid = true,
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

    // Use white text for hybrid/satellite, dark gray for normal map
    final labelTextColor = isHybrid ? Colors.white : const Color(0xFF374151);

    final defaultShadows = isHybrid
        ? const <Shadow>[
            Shadow(
              color: Color(0xD0000000),
              blurRadius: 3,
              offset: Offset(0, 0),
            ),
          ]
        : const <Shadow>[
            Shadow(
              color: Color(0x60FFFFFF),
              blurRadius: 2,
              offset: Offset(0, 0),
            ),
          ];

    // Collect all pending labels first, then render icons in parallel
    final pendingPlotLabels = <_PendingPlotLabel>[];
    final pendingRoadLabels = <_PendingRoadLabel>[];
    final pendingAmenityLabels = <_PendingAmenityLabel>[];
    var totalLabels = 0;

    // Phase 1: Collect plot labels
    if (shouldShowPlotLabels) {
      final plotFontSize = _plotLabelFontSize(zoom);

      for (final plot in response.plots) {
        if (totalLabels >= _maxLabelMarkers) break;

        final label = _simplifyPlotNumberLabel(plot.plotNumber);
        if (label.isEmpty) continue;

        final pos = plot.centerPoint;
        if (pos == null) continue;

        pendingPlotLabels.add(_PendingPlotLabel(
          plot: plot,
          label: label,
          position: pos,
          fontSize: plotFontSize,
        ));
        totalLabels++;
      }
    }

    // Phase 1: Collect road labels
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

        pendingRoadLabels.add(_PendingRoadLabel(
          road: road,
          name: name,
          placement: placement,
          fontSize: roadFontSize,
        ));
        totalLabels++;
      }
    }

    // Phase 1: Collect amenity labels
    if (shouldShowAmenityLabels) {
      for (final amenity in response.amenities) {
        if (totalLabels >= _maxLabelMarkers) break;

        final label = _amenityLabelText(amenity);
        if (label.isEmpty) continue;

        final amenityFontSize = _amenityLabelFontSize(amenity, label, zoom);

        final polygons = GeoJson.tryParsePolygons(amenity.boundaryGeoJson);
        if (polygons.isEmpty) continue;

        final isEbLine = label.trim().toLowerCase() == 'eb line';
        final placement =
            isEbLine ? _computeLineLabelPlacement(polygons.first) : null;
        final pos = placement?.position ?? _centroid(polygons.first);
        if (pos == null) continue;

        pendingAmenityLabels.add(_PendingAmenityLabel(
          amenity: amenity,
          label: label,
          position: pos,
          fontSize: amenityFontSize,
          rotationDegrees: placement?.rotationDegrees,
        ));
        totalLabels++;
      }
    }

    // Phase 2: Render all icons in parallel
    final plotIconFutures =
        pendingPlotLabels.map((p) => _iconFactory.getTextLabelIcon(
              text: p.label,
              pixelRatio: pixelRatio,
              fontSize: p.fontSize,
              textColor: labelTextColor,
              shadows: defaultShadows,
              backgroundColor: null,
              padding: EdgeInsets.zero,
              borderRadius: 0,
            ));

    // Road labels always use white with dark shadow for visibility
    const roadShadows = <Shadow>[
      Shadow(
        color: Color(0xD0000000),
        blurRadius: 3,
        offset: Offset(0, 0),
      ),
    ];
    final roadIconFutures =
        pendingRoadLabels.map((r) => _iconFactory.getTextLabelIcon(
              text: r.name,
              pixelRatio: pixelRatio,
              fontSize: r.fontSize,
              textColor: Colors.white,
              shadows: roadShadows,
              backgroundColor: null,
              padding: EdgeInsets.zero,
              borderRadius: 0,
            ));

    final amenityIconFutures =
        pendingAmenityLabels.map((a) => _iconFactory.getTextLabelIcon(
              text: a.label,
              pixelRatio: pixelRatio,
              fontSize: a.fontSize,
              textColor: labelTextColor,
              shadows: defaultShadows,
              backgroundColor: null,
              padding: EdgeInsets.zero,
              borderRadius: 0,
            ));

    // Wait for all icons in parallel
    final plotIcons = await Future.wait(plotIconFutures);
    final roadIcons = await Future.wait(roadIconFutures);
    final amenityIcons = await Future.wait(amenityIconFutures);

    // Phase 3: Create markers with rendered icons
    final nextPlotLabels = <Marker>{};
    for (var i = 0; i < pendingPlotLabels.length; i++) {
      final p = pendingPlotLabels[i];
      nextPlotLabels.add(
        Marker(
          markerId: MarkerId('plot-label:${p.plot.plotId}'),
          position: p.position,
          icon: plotIcons[i],
          anchor: const Offset(0.5, 0.5),
          zIndex: 120,
          onTap: () => _handlePlotTapped(p.plot),
          consumeTapEvents: true,
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    final nextRoadLabels = <Marker>{};
    for (var i = 0; i < pendingRoadLabels.length; i++) {
      final r = pendingRoadLabels[i];
      nextRoadLabels.add(
        Marker(
          markerId: MarkerId('road-label:${r.road.roadId}'),
          position: r.placement.position,
          icon: roadIcons[i],
          anchor: const Offset(0.5, 0.5),
          zIndex: 110,
          rotation: r.placement.rotationDegrees,
          flat: true,
          consumeTapEvents: false,
        ),
      );
    }

    final nextAmenityLabels = <Marker>{};
    for (var i = 0; i < pendingAmenityLabels.length; i++) {
      final a = pendingAmenityLabels[i];
      nextAmenityLabels.add(
        Marker(
          markerId: MarkerId('amenity-label:${a.amenity.amenityId}'),
          position: a.position,
          icon: amenityIcons[i],
          anchor: const Offset(0.5, 0.5),
          zIndex: 105,
          rotation: a.rotationDegrees ?? 0,
          flat: a.rotationDegrees != null,
          consumeTapEvents: false,
        ),
      );
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

    // Find the longest segment — matches the Next.js approach for consistent
    // label direction across platforms.
    final lat0 =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final cosLat0 = math.cos(_degToRad(lat0));

    LatLng? bestStart;
    LatLng? bestEnd;
    var bestScore = 0.0;

    for (var i = 0; i < points.length - 1; i++) {
      final s = points[i];
      final e = points[i + 1];
      final dx = (e.longitude - s.longitude) * cosLat0;
      final dy = e.latitude - s.latitude;
      final score = dx * dx + dy * dy;
      if (score > bestScore) {
        bestScore = score;
        bestStart = s;
        bestEnd = e;
      }
    }

    if (bestStart == null || bestEnd == null || bestScore <= 1e-18) {
      return null;
    }

    // Compute angle from the longest segment using atan2 (same as Next.js).
    // On the map: x = east (right), y = north (up on map, but screen y is down).
    // atan2(dy, dx) gives CCW from east in math coords.
    // CSS rotate() and flat marker rotation are both CW-positive in screen space.
    // Since screen-y is flipped vs map-y, negate dy to get the correct screen angle.
    final dx = (bestEnd.longitude - bestStart.longitude) * cosLat0;
    final dy = bestEnd.latitude - bestStart.latitude;
    var angleDeg = (math.atan2(-dy, dx) * 180) / math.pi;
    // Normalize to [-90, 90) so text is never upside-down.
    if (angleDeg >= 90) angleDeg -= 180;
    if (angleDeg < -90) angleDeg += 180;
    // Snap near-vertical labels (>80°) to -90° so all vertical roads
    // consistently read in the same direction regardless of polygon winding.
    if (angleDeg > 80) angleDeg = -90;

    // Use the angle directly as flat marker rotation (same as CSS rotate).
    return angleDeg;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;
}

/// Helper class for pending plot label data.
class _PendingPlotLabel {
  const _PendingPlotLabel({
    required this.plot,
    required this.label,
    required this.position,
    required this.fontSize,
  });

  final MapPlotFeature plot;
  final String label;
  final LatLng position;
  final double fontSize;
}

/// Helper class for pending road label data.
class _PendingRoadLabel {
  const _PendingRoadLabel({
    required this.road,
    required this.name,
    required this.placement,
    required this.fontSize,
  });

  final MapRoadFeature road;
  final String name;
  final _LineLabelPlacement placement;
  final double fontSize;
}

/// Strips common prefixes ("plot", "property", "site") and extracts the
/// numeric/alpha-numeric core.  Matches the web logic in
/// `r-map-ui/.../tooltipContent.ts → simplifyPlotNumberLabel`.
String _simplifyPlotNumberLabel(String? value) {
  if (value == null) return '';
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final withoutPrefix = trimmed.replaceFirst(
    RegExp(r'^(plot|property|site)\s*(no\.?|#)?\s*', caseSensitive: false),
    '',
  );
  final numericMatch =
      RegExp(r'[0-9]+[A-Za-z0-9/-]*').firstMatch(withoutPrefix);
  if (numericMatch != null) return numericMatch.group(0)!;
  return withoutPrefix;
}

/// Helper class for pending amenity label data.
class _PendingAmenityLabel {
  const _PendingAmenityLabel({
    required this.amenity,
    required this.label,
    required this.position,
    required this.fontSize,
    this.rotationDegrees,
  });

  final MapAmenityFeature amenity;
  final String label;
  final LatLng position;
  final double fontSize;
  final double? rotationDegrees;
}
