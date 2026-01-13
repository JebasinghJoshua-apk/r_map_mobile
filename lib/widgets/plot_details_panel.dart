import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_viewport_models.dart';
import '../utils/geojson.dart';

class PlotDetailsPanel extends StatefulWidget {
  const PlotDetailsPanel({
    super.key,
    required this.plot,
    required this.isSold,
    required this.areaLabel,
    required this.tags,
    required this.onClose,
    this.onLayoutDetails,
    this.onUpdateStatus,
  });

  final MapPlotFeature plot;
  final bool isSold;
  final String? areaLabel;
  final List<String> tags;
  final VoidCallback onClose;
  final VoidCallback? onLayoutDetails;
  final ValueChanged<String>? onUpdateStatus;

  @override
  State<PlotDetailsPanel> createState() => _PlotDetailsPanelState();
}

class _PlotDetailsPanelState extends State<PlotDetailsPanel> {
  late String _statusValue;

  @override
  void initState() {
    super.initState();
    _statusValue = widget.isSold ? 'Sold' : 'Available';
  }

  @override
  void didUpdateWidget(covariant PlotDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSold != widget.isSold) {
      _statusValue = widget.isSold ? 'Sold' : 'Available';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plotNumber =
        widget.plot.plotNumber.trim().isEmpty ? '—' : widget.plot.plotNumber;

    final isSold = widget.isSold;
    final statusText = isSold ? 'SOLD' : 'AVAILABLE';

    // Match the web screenshot: AVAILABLE is green, SOLD is red.
    final statusColor =
        isSold ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    final areaText = (widget.areaLabel ?? '').trim();
    final totalSqftText = areaText.isEmpty ? '—' : areaText;

    final dimensions = _tryComputePlotEdgeDimensionsFeet(widget.plot);

    final tagsLine = widget.tags.where((t) => t.trim().isNotEmpty).join(', ');

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 16,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: _CloseIconButton(onPressed: widget.onClose),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PlotSketchCard(
                      borderColor: const Color(0xFF16A34A),
                      dimensions: dimensions,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Plot #$plotNumber',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.35),
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            totalSqftText,
                            style: const TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tagsLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onLayoutDetails,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Layout Details →',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'UPDATE STATUS',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          value: _statusValue,
                          items: const [
                            DropdownMenuItem(
                              value: 'Available',
                              child: Text('Available'),
                            ),
                            DropdownMenuItem(
                              value: 'Sold',
                              child: Text('Sold'),
                            ),
                          ],
                          onChanged: widget.onUpdateStatus == null
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  setState(() {
                                    _statusValue = v;
                                  });
                                  widget.onUpdateStatus?.call(v);
                                },
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFD1D5DB),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: widget.onClose,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          foregroundColor: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _PlotDimensionsFeet? _tryComputePlotEdgeDimensionsFeet(
    MapPlotFeature plot,
  ) {
    // Only display dimensions when provided by the API.
    return _tryParsePlotEdgeDimensionsFromMetadata(plot);
  }

  static _PlotDimensionsFeet? _tryParsePlotEdgeDimensionsFromMetadata(
    MapPlotFeature plot,
  ) {
    final meta = plot.metadata;
    final raw = (meta['dimensions'] ??
            meta['plotDimensions'] ??
            meta['plot_dimensions'] ??
            meta['dimension'])
        ?.trim();
    if (raw == null || raw.isEmpty) return null;

    final parts = raw
        .split(RegExp(r'[\s,]+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 4) return null;

    double? parseFeet(String raw) {
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(raw);
      if (match == null) return null;
      return double.tryParse(match.group(1) ?? '');
    }

    final values = <double>[];
    for (final part in parts.take(4)) {
      final v = parseFeet(part);
      if (v == null || !v.isFinite || v <= 0) return null;
      values.add(v);
    }

    // If we can compute the geometry-derived edges, use it as a hint to pick
    // the best ordering/rotation of metadata dimensions.
    final computed = _tryComputePlotEdgeDimensionsFromBoundary(plot);
    if (computed == null) {
      // Common backend ordering (as provided): left, top, right, bottom.
      return _PlotDimensionsFeet(
        topFeet: values[1],
        rightFeet: values[2],
        bottomFeet: values[3],
        leftFeet: values[0],
      );
    }

    final target = <double>[
      computed.topFeet,
      computed.rightFeet,
      computed.bottomFeet,
      computed.leftFeet,
    ];

    List<double> rotate(List<double> v, int k) {
      final kk = k % v.length;
      return <double>[...v.sublist(kk), ...v.sublist(0, kk)];
    }

    final candidates = <List<double>>[];
    for (var k = 0; k < 4; k++) {
      candidates.add(rotate(values, k));
    }
    final reversed = values.reversed.toList(growable: false);
    for (var k = 0; k < 4; k++) {
      candidates.add(rotate(reversed, k));
    }

    double score(List<double> candidate) {
      var sum = 0.0;
      for (var i = 0; i < 4; i++) {
        sum += (candidate[i] - target[i]).abs();
      }
      return sum;
    }

    var best = candidates.first;
    var bestScore = score(best);
    for (final c in candidates.skip(1)) {
      final s = score(c);
      if (s < bestScore) {
        best = c;
        bestScore = s;
      }
    }

    return _PlotDimensionsFeet(
      topFeet: best[0],
      rightFeet: best[1],
      bottomFeet: best[2],
      leftFeet: best[3],
    );
  }

  static _PlotDimensionsFeet? _tryComputePlotEdgeDimensionsFromBoundary(
    MapPlotFeature plot,
  ) {
    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (polygons.isEmpty) return null;

    var points = polygons.first;
    if (points.length < 3) return null;

    points = _removeDuplicateClosingPoint(points);
    if (points.length < 3) return null;

    final corners = _pickFourCorners(points);
    if (corners == null) return null;

    final a = corners[0];
    final b = corners[1];
    final c = corners[2];
    final d = corners[3];

    final top = _metersToFeet(_haversineMeters(a, b));
    final right = _metersToFeet(_haversineMeters(b, c));
    final bottom = _metersToFeet(_haversineMeters(c, d));
    final left = _metersToFeet(_haversineMeters(d, a));

    return _PlotDimensionsFeet(
      topFeet: top,
      rightFeet: right,
      bottomFeet: bottom,
      leftFeet: left,
    );
  }

  static List<LatLng> _removeDuplicateClosingPoint(List<LatLng> points) {
    if (points.length < 2) return points;
    final first = points.first;
    final last = points.last;
    final dLat = (first.latitude - last.latitude).abs();
    final dLng = (first.longitude - last.longitude).abs();
    if (dLat < 1e-9 && dLng < 1e-9) {
      return points.sublist(0, points.length - 1);
    }
    return points;
  }

  static List<LatLng>? _pickFourCorners(List<LatLng> points) {
    if (points.length == 4) return points;
    if (points.length < 4) return null;

    // Many plot polygons are rectangles; if the backend includes more points,
    // pick 4 evenly spaced points to keep labels stable.
    final n = points.length;
    const i0 = 0;
    final i1 = (n / 4).round().clamp(1, n - 1);
    final i2 = (n / 2).round().clamp(2, n - 1);
    final i3 = (3 * n / 4).round().clamp(3, n - 1);

    final corners = <LatLng>[points[i0], points[i1], points[i2], points[i3]];
    if (_hasDuplicates(corners)) return null;
    return corners;
  }

  static bool _hasDuplicates(List<LatLng> points) {
    final set = <String>{};
    for (final p in points) {
      final key =
          '${p.latitude.toStringAsFixed(9)},${p.longitude.toStringAsFixed(9)}';
      if (set.contains(key)) return true;
      set.add(key);
    }
    return false;
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final aa =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return r * c;
  }

  static double _toRad(double deg) => deg * (math.pi / 180.0);

  static double _metersToFeet(double meters) => meters * 3.280839895;
}

class _CloseIconButton extends StatelessWidget {
  const _CloseIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Icon(Icons.close, size: 18),
        ),
      ),
    );
  }
}

class _PlotSketchCard extends StatelessWidget {
  const _PlotSketchCard({
    required this.borderColor,
    required this.dimensions,
  });

  final Color borderColor;
  final _PlotDimensionsFeet? dimensions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      height: 112,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: CustomPaint(
          painter: _PlotSketchPainter(
            borderColor: borderColor,
            dimensions: dimensions,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PlotDimensionsFeet {
  const _PlotDimensionsFeet({
    required this.topFeet,
    required this.rightFeet,
    required this.bottomFeet,
    required this.leftFeet,
  });

  final double topFeet;
  final double rightFeet;
  final double bottomFeet;
  final double leftFeet;
}

class _PlotSketchPainter extends CustomPainter {
  _PlotSketchPainter({required this.borderColor, required this.dimensions});

  final Color borderColor;
  final _PlotDimensionsFeet? dimensions;

  @override
  void paint(Canvas canvas, Size size) {
    final p0 = Offset(size.width * 0.22, size.height * 0.20);
    final p1 = Offset(size.width * 0.80, size.height * 0.12);
    final p2 = Offset(size.width * 0.70, size.height * 0.85);
    final p3 = Offset(size.width * 0.14, size.height * 0.74);

    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      // Web plots: #16A34A @ 0.3 opacity (see r-map-ui/src/constants/drawingStyles.ts)
      ..color = const Color(0xFF16A34A).withOpacity(0.30);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    if (dimensions == null) return;

    const textStyle = TextStyle(
      color: Color(0xFF111827),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );

    void drawRotatedLabel(
      String text,
      Offset center,
      double angle,
    ) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      // Keep label upright.
      var a = angle;
      if (a > math.pi / 2 || a < -math.pi / 2) {
        a += math.pi;
      }

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(a);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    Offset midpoint(Offset a, Offset b) =>
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

    Offset unitNormalOutward(Offset a, Offset b, Offset centerHint) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len <= 1e-6) return const Offset(0, -1);
      // Perpendicular (dy, -dx) (one of the normals)
      var nx = dy / len;
      var ny = -dx / len;

      final m = midpoint(a, b);
      // Pick the normal that points away from the polygon center.
      final toCenter = Offset(centerHint.dx - m.dx, centerHint.dy - m.dy);
      final dot = (nx * toCenter.dx) + (ny * toCenter.dy);
      if (dot > 0) {
        nx = -nx;
        ny = -ny;
      }
      return Offset(nx, ny);
    }

    String ft(double v) {
      final rounded = v.isFinite ? v.round().clamp(0, 9999) : 0;
      return '$rounded ft';
    }

    final centerHint = Offset(size.width / 2, size.height / 2);
    const pad = 10.0;

    void drawOnEdge(String text, Offset a, Offset b) {
      final m = midpoint(a, b);
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final n = unitNormalOutward(a, b, centerHint);
      drawRotatedLabel(text, m + (n * pad), angle);
    }

    // Match the web sketch label placement by aligning labels with edges.
    drawOnEdge(ft(dimensions!.topFeet), p0, p1);
    drawOnEdge(ft(dimensions!.rightFeet), p1, p2);
    drawOnEdge(ft(dimensions!.bottomFeet), p3, p2);
    drawOnEdge(ft(dimensions!.leftFeet), p0, p3);
  }

  @override
  bool shouldRepaint(covariant _PlotSketchPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.dimensions != dimensions;
  }
}
