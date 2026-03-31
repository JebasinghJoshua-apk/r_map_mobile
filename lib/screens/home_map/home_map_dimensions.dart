part of '../home_map_screen.dart';

/// Minimum zoom level at which edge dimension labels are shown on the
/// selected plot polygon.
const double _minDimensionLabelZoom = 20.0;

extension _HomeMapDimensions on _HomeMapScreenState {
  /// Parses the dimensions array from plot metadata (same keys as the bottom
  /// panel sketch card).  Returns null when the API doesn't provide them.
  static List<double>? _parsePlotDimensions(MapPlotFeature plot) {
    final meta = plot.metadata;
    final raw = (meta['dimensions'] ??
            meta['plotDimensions'] ??
            meta['plot_dimensions'] ??
            meta['dimension'])
        ?.trim();
    if (raw == null || raw.isEmpty) return null;

    final values = <double>[];
    void pushValue(Object? v) {
      if (v == null) return;
      final asNum = v is num ? v.toDouble() : double.tryParse(v.toString());
      if (asNum != null && asNum.isFinite && asNum > 0) {
        values.add(asNum);
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          pushValue(item);
        }
      } else {
        throw const FormatException('not-array');
      }
    } catch (_) {
      for (final token in raw
          .split(RegExp(r'[\s,;|]+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)) {
        pushValue(token);
      }
    }

    if (values.isEmpty) return null;
    return values;
  }

  /// Builds dimension-label markers for each edge of the selected plot's
  /// polygon boundary using the API-provided dimensions from metadata.
  /// Returns an empty set when no plot is selected, no dimensions are
  /// available, or zoom is below the threshold.
  Future<Set<Marker>> _buildDimensionMarkers({
    required MapPlotFeature plot,
    required double zoom,
    required double pixelRatio,
    bool isHybrid = true,
  }) async {
    if (zoom < _minDimensionLabelZoom) return const <Marker>{};

    final dims = _parsePlotDimensions(plot);
    if (dims == null || dims.isEmpty) return const <Marker>{};

    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (polygons.isEmpty) return const <Marker>{};

    final labelTextColor = isHybrid ? Colors.white : const Color(0xFF1F2937);
    final shadows = isHybrid
        ? const <Shadow>[
            Shadow(color: Color(0xD0000000), blurRadius: 3),
          ]
        : const <Shadow>[
            Shadow(color: Color(0x60FFFFFF), blurRadius: 2),
          ];
    final fontSize = _dimensionFontSize(zoom);

    final pending = <_PendingDimensionLabel>[];

    for (var polyIdx = 0; polyIdx < polygons.length; polyIdx++) {
      final ring = polygons[polyIdx];
      if (ring.length < 3) continue;

      // For closed rings the last point == first — don't label the closing edge.
      final edgeCount =
          _isClosedRing(ring) ? ring.length - 1 : ring.length - 1;

      for (var i = 0; i < edgeCount; i++) {
        final a = ring[i];
        final b = ring[i + 1];

        // Cycle through provided dimensions (same as the sketch painter).
        final dimValue = dims[i % dims.length];
        if (dimValue <= 0) continue;

        final label = _formatFeetLabel(dimValue);

        final midLat = (a.latitude + b.latitude) / 2;
        final midLng = (a.longitude + b.longitude) / 2;

        // Place label exactly on the edge midpoint.
        final position = LatLng(midLat, midLng);

        final rotation = _edgeRotationDegrees(a, b);

        pending.add(_PendingDimensionLabel(
          position: position,
          label: label,
          rotation: rotation,
          polyIndex: polyIdx,
          edgeIndex: i,
        ));
      }
    }

    if (pending.isEmpty) return const <Marker>{};

    // Render all dimension icons in parallel.
    final icons = await Future.wait(
      pending.map((p) => _iconFactory.getTextLabelIcon(
            text: p.label,
            pixelRatio: pixelRatio,
            fontSize: fontSize,
            textColor: labelTextColor,
            shadows: shadows,
            backgroundColor: const Color(0xCC374151),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            borderRadius: 3,
            fontWeight: FontWeight.w700,
          )),
    );

    final markers = <Marker>{};
    for (var i = 0; i < pending.length; i++) {
      final p = pending[i];
      markers.add(
        Marker(
          markerId: MarkerId(
            'dim:${plot.plotId}:${p.polyIndex}:${p.edgeIndex}',
          ),
          position: p.position,
          icon: icons[i],
          anchor: const Offset(0.5, 0.5),
          rotation: p.rotation,
          flat: true,
          zIndex: 200,
          consumeTapEvents: false,
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    return Set<Marker>.unmodifiable(markers);
  }

  /// Format a feet value for the dimension label (e.g. "30 ft", "32.5 ft").
  String _formatFeetLabel(double v) {
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 0.01) {
      return '${rounded.toInt()} ft';
    }
    return '${v.toStringAsFixed(1)} ft';
  }

  /// Returns the rotation (in degrees, CW-positive for flat markers) to
  /// align a label with the edge from [a] to [b].
  double _edgeRotationDegrees(LatLng a, LatLng b) {
    final lat0 = (a.latitude + b.latitude) / 2;
    final cosLat0 = math.cos(_degToRad(lat0));
    final dx = (b.longitude - a.longitude) * cosLat0;
    final dy = b.latitude - a.latitude;
    var angleDeg = (math.atan2(-dy, dx) * 180) / math.pi;
    if (angleDeg >= 90) angleDeg -= 180;
    if (angleDeg < -90) angleDeg += 180;
    return angleDeg;
  }

  /// Stepped font-size scaling for dimension labels.
  double _dimensionFontSize(double zoom) {
    if (zoom >= 21.0) return 14;
    if (zoom >= 20.5) return 13;
    if (zoom >= 20.2) return 12;
    if (zoom >= 20.0) return 9;
    return 8;
  }

  /// Average centroid of a polygon ring.
  LatLng _ringCentroid(List<LatLng> ring) {
    var sumLat = 0.0;
    var sumLng = 0.0;
    final count = _isClosedRing(ring) ? ring.length - 1 : ring.length;
    for (var i = 0; i < count; i++) {
      sumLat += ring[i].latitude;
      sumLng += ring[i].longitude;
    }
    return LatLng(sumLat / count, sumLng / count);
  }
}

class _PendingDimensionLabel {
  const _PendingDimensionLabel({
    required this.position,
    required this.label,
    required this.rotation,
    required this.polyIndex,
    required this.edgeIndex,
  });

  final LatLng position;
  final String label;
  final double rotation;
  final int polyIndex;
  final int edgeIndex;
}
