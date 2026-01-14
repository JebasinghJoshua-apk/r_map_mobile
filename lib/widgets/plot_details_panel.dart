import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_viewport_models.dart';
import '../utils/geojson.dart';
import '../utils/route_observer.dart';

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
  final Future<void> Function(String)? onUpdateStatus;

  @override
  State<PlotDetailsPanel> createState() => _PlotDetailsPanelState();
}

class _PlotDetailsPanelState extends State<PlotDetailsPanel> with RouteAware {
  late String _statusValue;
  bool _isUpdatingStatus = false;

  void _handleLayoutDetailsPressed() {
    _dismissKeyboard();
    // Let callers navigate without inheriting any lingering focus.
    Future.microtask(() => widget.onLayoutDetails?.call());
  }

  void _showShareSheet() {
    final plotId = widget.plot.plotId.trim();
    final plotNumber = widget.plot.plotNumber.trim();
    final shareUrl = plotId.isNotEmpty
        ? 'https://rmap.local/plot/$plotId'
        : plotNumber.isNotEmpty
            ? 'https://rmap.local/plot-number/$plotNumber'
            : 'https://rmap.local/plot';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Share to WhatsApp'),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('TODO: Share to WhatsApp'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('Share to Facebook'),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('TODO: Share to Facebook'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copy URL'),
                subtitle: Text(shareUrl,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () async {
                  Navigator.of(context).pop();
                  await Clipboard.setData(ClipboardData(text: shareUrl));
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('URL copied (placeholder)'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  @override
  void initState() {
    super.initState();
    _statusValue = _resolvePlotStatusLabel(widget.plot, widget.isSold);
  }

  @override
  void didUpdateWidget(covariant PlotDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plot.plotId != widget.plot.plotId ||
        oldWidget.isSold != widget.isSold) {
      _statusValue = _resolvePlotStatusLabel(widget.plot, widget.isSold);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // We just returned to this panel (e.g. from Layout Details). Make sure
    // no lingering focus causes the keyboard to appear.
    _dismissKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dismissKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final plotNumber =
        widget.plot.plotNumber.trim().isEmpty ? '—' : widget.plot.plotNumber;

    final statusTheme = _plotStatusTheme(_statusValue);
    final statusText = _statusValue.trim().isEmpty
        ? 'STATUS'
        : _statusValue.trim().toUpperCase();

    final areaText = (widget.areaLabel ?? '').trim();
    final totalSqftText = areaText.isEmpty ? '—' : areaText;

    final dimensions = _tryParsePlotDimensionsFeet(widget.plot);
    final plotRing = _tryParsePlotBoundaryRing(widget.plot);

    final tagsLine = widget.tags.where((t) => t.trim().isNotEmpty).join(', ');

    final showInfoRow = tagsLine.trim().isNotEmpty;

    final canEditStatus = widget.onUpdateStatus != null &&
        (widget.plot.layoutId?.trim().isNotEmpty ?? false);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
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
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFFEFF6FF),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 12.0;
                        const leftFlex = 3.0;
                        const rightFlex = 2.0;
                        const sketchAspectRatio = 152 / 112;

                        final contentWidth = constraints.maxWidth;
                        final leftWidth = (contentWidth - gap) *
                            (leftFlex / (leftFlex + rightFlex));
                        final sketchHeight = leftWidth / sketchAspectRatio;

                        return SizedBox(
                          height: sketchHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _PlotSketchCard(
                                  borderColor: const Color(0xFF15803D),
                                  dimensions: dimensions,
                                  boundaryRing: plotRing,
                                ),
                              ),
                              const SizedBox(width: gap),
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  // Leave a touch of breathing room from the top.
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Text(
                                        'Plot #$plotNumber',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      Text(
                                        totalSqftText,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF4B5563),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusTheme.bg,
                                            border: Border.all(
                                              color: statusTheme.border,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusTheme.color,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: TextButton.icon(
                                          onPressed: _showShareSheet,
                                          style: TextButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF2563EB)
                                                    .withOpacity(0.10),
                                            side: const BorderSide(
                                              color: Color(0xFF93C5FD),
                                              width: 1,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            minimumSize: const Size(0, 32),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: const Icon(
                                            Icons.share_outlined,
                                            size: 14,
                                            color: Color(0xFF1D4ED8),
                                          ),
                                          label: const Text(
                                            'Share',
                                            style: TextStyle(
                                              color: Color(0xFF1D4ED8),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (widget.onLayoutDetails != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: TextButton(
                                            onPressed:
                                                _handleLayoutDetailsPressed,
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              minimumSize: const Size(0, 0),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: const Text(
                                              'Layout Details →',
                                              style: TextStyle(
                                                color: Color(0xFF1D4ED8),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _CloseIconButton(onPressed: widget.onClose),
                    ),
                  ],
                ),
              ),
              if (showInfoRow)
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Text(
                    tagsLine,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canEditStatus)
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
                            const Flexible(
                              flex: 2,
                              child: Text(
                                'UPDATE STATUS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: 40,
                                child: DropdownButtonFormField<String>(
                                  value: _statusValue,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Available',
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text('Available'),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Booked',
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text('Booked'),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Sold',
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text('Sold'),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Blocked',
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: Text('Blocked'),
                                      ),
                                    ),
                                  ],
                                  onChanged: (widget.onUpdateStatus == null ||
                                          _isUpdatingStatus)
                                      ? null
                                      : (v) async {
                                          if (v == null) return;

                                          _dismissKeyboard();

                                          final previous = _statusValue;
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          setState(() {
                                            _statusValue = v;
                                            _isUpdatingStatus = true;
                                          });

                                          try {
                                            await widget.onUpdateStatus
                                                ?.call(v);
                                          } catch (e) {
                                            debugPrint(
                                                'Failed to update plot status: $e');
                                            if (mounted) {
                                              setState(() {
                                                _statusValue = previous;
                                              });
                                            }

                                            final message = e.toString().trim();
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  message.isEmpty
                                                      ? 'Failed to update status. Please try again.'
                                                      : message,
                                                ),
                                              ),
                                            );
                                          } finally {
                                            _dismissKeyboard();
                                            if (mounted) {
                                              setState(() {
                                                _isUpdatingStatus = false;
                                              });
                                            }
                                          }
                                        },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
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
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: widget.onClose,
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: Color(0xFFD1D5DB)),
                                foregroundColor: const Color(0xFF111827),
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            ],
          ),
        ),
      ),
    );
  }

  static List<double>? _tryParsePlotDimensionsFeet(MapPlotFeature plot) {
    // Only display dimensions when provided by the API.
    // Parsing mirrors the web implementation in:
    // r-map-ui/src/components/Map/utils/tooltipContent.ts (parseDimensionsMetadata)
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

  static List<LatLng>? _tryParsePlotBoundaryRing(MapPlotFeature plot) {
    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (polygons.isEmpty) return null;
    final ring = polygons.first;
    if (ring.length < 3) return null;
    return ring;
  }

  static String _resolvePlotStatusLabel(
      MapPlotFeature plot, bool isSoldFallback) {
    final meta = plot.metadata;
    final raw = (meta['plotStatus'] ??
            meta['plot_status'] ??
            meta['status'] ??
            meta['availability'])
        ?.trim();

    final normalized = (raw ?? '').trim().toLowerCase();
    final normalizedKey = normalized == '0'
        ? 'available'
        : normalized == '1'
            ? 'booked'
            : (normalized == '2' || normalized == 'sld')
                ? 'sold'
                : normalized == '3'
                    ? 'blocked'
                    : normalized;

    if (normalizedKey == 'available') return 'Available';
    if (normalizedKey == 'booked') return 'Booked';
    if (normalizedKey == 'sold') return 'Sold';
    if (normalizedKey == 'blocked') return 'Blocked';

    if (isSoldFallback) return 'Sold';
    return 'Available';
  }

  static _PlotStatusTheme _plotStatusTheme(String statusLabel) {
    final normalized = statusLabel.trim().toLowerCase();

    // Mirror the web `PLOT_STATUS_THEME` in:
    // r-map-ui/src/components/Map/utils/tooltipContent.ts
    switch (normalized) {
      case 'available':
        return const _PlotStatusTheme(
          bg: Color(0x99BBF7D0),
          color: Color(0xFF059669),
          border: Color(0xFF34D399),
        );
      case 'booked':
        return const _PlotStatusTheme(
          bg: Color(0xA6FED7AA),
          color: Color(0xFF92400E),
          border: Color(0xFFFB923C),
        );
      case 'sold':
        return const _PlotStatusTheme(
          bg: Color(0xB2FECACA),
          color: Color(0xFF7F1D1D),
          border: Color(0xFFF87171),
        );
      case 'blocked':
        return const _PlotStatusTheme(
          bg: Color(0xE6E2E8F0),
          color: Color(0xFF0F172A),
          border: Color(0xFF94A3B8),
        );
      default:
        return const _PlotStatusTheme(
          bg: Color(0x00FFFFFF),
          color: Color(0xFF111827),
          border: Color(0x00000000),
        );
    }
  }
}

class _PlotStatusTheme {
  const _PlotStatusTheme({
    required this.bg,
    required this.color,
    required this.border,
  });

  final Color bg;
  final Color color;
  final Color border;
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
    required this.boundaryRing,
  });

  final Color borderColor;
  final List<double>? dimensions;
  final List<LatLng>? boundaryRing;

  @override
  Widget build(BuildContext context) {
    // Keep the same visual proportions as the original fixed-size card
    // (152x112) while letting the parent decide the width.
    return AspectRatio(
      aspectRatio: 152 / 112,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CustomPaint(
            painter: _PlotSketchPainter(
              borderColor: borderColor,
              dimensions: dimensions,
              boundaryRing: boundaryRing,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PlotSketchPainter extends CustomPainter {
  _PlotSketchPainter({
    required this.borderColor,
    required this.dimensions,
    required this.boundaryRing,
  });

  final Color borderColor;
  final List<double>? dimensions;
  final List<LatLng>? boundaryRing;

  @override
  void paint(Canvas canvas, Size size) {
    // Mirror web mini SVG logic (r-map-ui/src/components/Map/utils/tooltipContent.ts):
    // - Normalize plot boundary points into the viewbox with padding
    // - Draw polygon
    // - Place labels at edge midpoints, offset outward from centroid
    // Then apply a small final clockwise tilt.
    const rotationRadians = 0.22; // ~12.6 degrees clockwise

    Offset rotateAround(Offset p, Offset center, double angle) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      return Offset(
        center.dx + (dx * cosA - dy * sinA),
        center.dy + (dx * sinA + dy * cosA),
      );
    }

    final pad = math.min(size.width * (18 / 140), size.height * (18 / 100));
    final usableWidth = math.max(1.0, size.width - pad * 2);
    final usableHeight = math.max(1.0, size.height - pad * 2);

    var points = <Offset>[];
    if (boundaryRing != null && boundaryRing!.length >= 3) {
      final xs = boundaryRing!.map((p) => p.longitude).toList(growable: false);
      final ys = boundaryRing!.map((p) => p.latitude).toList(growable: false);
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min);
      final maxY = ys.reduce(math.max);
      final spanX = math.max(maxX - minX, 1e-6);
      final spanY = math.max(maxY - minY, 1e-6);

      points = boundaryRing!
          .map(
            (p) => Offset(
              pad + ((p.longitude - minX) / spanX) * usableWidth,
              pad + ((maxY - p.latitude) / spanY) * usableHeight,
            ),
          )
          .toList(growable: false);
    } else {
      // Fallback when we have no boundary geometry.
      points = <Offset>[
        Offset(size.width * 0.30, size.height * 0.22),
        Offset(size.width * 0.78, size.height * 0.14),
        Offset(size.width * 0.68, size.height * 0.86),
        Offset(size.width * 0.20, size.height * 0.94),
      ];
    }

    // Drop a duplicate closing point if present.
    if (points.length >= 2) {
      final last = points.last;
      final first = points.first;
      if ((last - first).distance < 0.001) {
        points = points.sublist(0, points.length - 1);
      }
    }
    if (points.length < 3) return;

    // Centroid used for tilt + label placement.
    var centroid = const Offset(0, 0);
    for (final p in points) {
      centroid += p;
    }
    centroid = centroid / points.length.toDouble();

    points = points
        .map((p) => rotateAround(p, centroid, rotationRadians))
        .toList(growable: false);

    final path = Path()..addPolygon(points, true);

    final scale = size.height / 100;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      // Web tooltip plot: rgba(16,185,129,0.25)
      ..color = const Color(0xFF10B981).withOpacity(0.25);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * scale
      ..strokeJoin = StrokeJoin.round
      ..color = borderColor;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    final dims = (dimensions ?? const <double>[])
        .where((v) => v.isFinite && v > 0)
        .toList(growable: false);
    if (dims.isEmpty) return;

    String formatFeet(double v) {
      if (!v.isFinite) return '0 ft';
      final rounded = v.roundToDouble();
      final showInt = (v - rounded).abs() < 1e-6;
      final text = showInt
          ? rounded.toInt().toString()
          : v.toStringAsFixed(1).replaceAll(RegExp(r'\\.0$'), '');
      return '$text ft';
    }

    final textStyle = TextStyle(
      color: const Color(0xFF0F172A),
      fontSize: 10 * scale,
      fontWeight: FontWeight.w600,
    );

    void drawRotatedLabel(String text, Offset labelCenter, double angle) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      var a = angle;
      if (a > math.pi / 2 || a < -math.pi / 2) {
        a += math.pi;
      }

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(a);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    final labelOffset = 12 * scale;
    final segmentCount = points.length;
    for (var i = 0; i < segmentCount; i += 1) {
      final start = points[i];
      final end = points[(i + 1) % segmentCount];
      final value = dims[i % dims.length];

      final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);

      final toMid = Offset(mid.dx - centroid.dx, mid.dy - centroid.dy);
      final len = math.max(1e-6, toMid.distance);
      final outward = Offset(toMid.dx / len, toMid.dy / len);
      final labelCenter = mid + outward * labelOffset;

      drawRotatedLabel(formatFeet(value), labelCenter, angle);
    }
  }

  @override
  bool shouldRepaint(covariant _PlotSketchPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.dimensions != dimensions ||
        oldDelegate.boundaryRing != boundaryRing;
  }
}
