import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PropertyPolygonEditorScreen extends StatefulWidget {
  const PropertyPolygonEditorScreen({
    super.key,
    required this.mode,
    this.initialCenter,
  });

  final PropertyPolygonEditorMode mode;
  final LatLng? initialCenter;

  @override
  State<PropertyPolygonEditorScreen> createState() =>
      _PropertyPolygonEditorScreenState();
}

enum PropertyPolygonEditorMode {
  add,
  edit,
}

class _PropertyPolygonEditorScreenState
    extends State<PropertyPolygonEditorScreen> {
  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629); // India

  late final LatLng _center = widget.initialCenter ?? _fallbackCenter;
  final List<LatLng> _points = <LatLng>[];

  final Map<String, BitmapDescriptor> _labelIconCache =
      <String, BitmapDescriptor>{};
  final Map<int, BitmapDescriptor> _edgeLabelIcons = <int, BitmapDescriptor>{};

  GoogleMapController? _controller;

  MapType _mapType = MapType.normal;
  String? _lightMapStyle;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMapStyle());
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_light.json');
      if (!mounted) return;
      setState(() {
        _lightMapStyle = style;
      });
    } catch (_) {
      // Style is optional; keep default map style if asset is missing.
    }
  }

  void _addPoint(LatLng p) {
    setState(() {
      _points.add(p);
    });
    HapticFeedback.selectionClick();
    unawaited(_refreshEdgeLabels());
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
    });
    unawaited(_refreshEdgeLabels());
  }

  void _clear() {
    if (_points.isEmpty) return;
    setState(() {
      _points.clear();
    });
    unawaited(_refreshEdgeLabels());
  }

  void _updatePoint(int index, LatLng p) {
    if (index < 0 || index >= _points.length) return;
    setState(() {
      _points[index] = p;
    });
    unawaited(_refreshEdgeLabels());
  }

  bool get _canFinish => _points.length >= 3;

  Future<void> _zoomIn() async {
    await _controller?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }

  void _toggleMapType() {
    setState(() {
      // Match main screen: toggle between normal map and hybrid (satellite + labels).
      _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    });
  }

  Widget _mapZoomControl() {
    const radius = 8.0;
    const size = 36.0;
    const borderColor = Color(0xFFE2E8F0);

    Widget segment({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      required BorderRadius borderRadius,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 18,
                color: const Color(0xFF1F2937),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              icon: Icons.add,
              tooltip: 'Zoom in',
              onPressed: () => unawaited(_zoomIn()),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: borderColor),
            segment(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onPressed: () => unawaited(_zoomOut()),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(radius),
                bottomRight: Radius.circular(radius),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    const radius = 8.0;
    const size = 36.0;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.white,
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF1F2937),
            ),
          ),
        ),
      ),
    );
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadiusMeters = 6371000.0;

    double toRad(double deg) => deg * (math.pi / 180.0);

    final lat1 = toRad(a.latitude);
    final lat2 = toRad(b.latitude);
    final dLat = toRad(b.latitude - a.latitude);
    final dLng = toRad(b.longitude - a.longitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h =
        sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusMeters * c;
  }

  static String _formatFeet(double meters) {
    final feet = meters * 3.280839895;
    // Match the screenshot style: 1 decimal + apostrophe.
    return "${feet.toStringAsFixed(1)}'";
  }

  static LatLng _midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  Future<BitmapDescriptor> _labelIcon(String text) async {
    final cached = _labelIconCache[text];
    if (cached != null) return cached;

    final bytes = await _renderLabelPng(text);
    final icon = BitmapDescriptor.bytes(bytes);
    _labelIconCache[text] = icon;
    return icon;
  }

  Future<Uint8List> _renderLabelPng(String text) async {
    // Canvas-rendered marker so labels are always visible on the map.
    const paddingX = 2.0;
    const paddingY = 2.0;
    const fontSize = 11.0;

    // White text like the main map, without a background.
    // Add a subtle outline to keep it readable on light areas.
    final outlinePainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xCC000000),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final fillPainter = TextPainter(
      text: const TextSpan(),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    fillPainter.text = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
    fillPainter.layout();

    final textW = math.max(outlinePainter.width, fillPainter.width);
    final textH = math.max(outlinePainter.height, fillPainter.height);
    final w = textW + paddingX * 2;
    final h = textH + paddingY * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const offset = Offset(paddingX, paddingY);
    outlinePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.ceil(), h.ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _refreshEdgeLabels() async {
    if (!mounted) return;

    // Only show labels when we have at least 2 points.
    if (_points.length < 2) {
      if (!mounted) return;
      setState(() {
        _edgeLabelIcons.clear();
      });
      return;
    }

    final lastIndex = _points.length - 1;
    final willClose = _points.length >= 3;
    final edgeCount = willClose ? _points.length : lastIndex;

    final icons = <int, BitmapDescriptor>{};
    for (var i = 0; i < edgeCount; i++) {
      final a = _points[i];
      final b = _points[(i + 1) % _points.length];
      final meters = _distanceMeters(a, b);
      final label = _formatFeet(meters);
      icons[i] = await _labelIcon(label);
    }

    if (!mounted) return;
    setState(() {
      _edgeLabelIcons
        ..clear()
        ..addAll(icons);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == PropertyPolygonEditorMode.add
        ? 'Add property'
        : 'Edit property';

    final polygon = _points.length >= 3
        ? Polygon(
            polygonId: const PolygonId('draft'),
            points: _points,
            strokeWidth: 2,
            strokeColor: const Color(0xFF0FAD97),
            fillColor: const Color(0x330FAD97),
          )
        : null;

    final vertexMarkers = <Marker>{
      for (var i = 0; i < _points.length; i++)
        Marker(
          markerId: MarkerId('v$i'),
          position: _points[i],
          draggable: true,
          onDragEnd: (p) => _updatePoint(i, p),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
    };

    final edgeMarkers = <Marker>{};
    if (_points.length >= 2) {
      final willClose = _points.length >= 3;
      final lastIndex = _points.length - 1;
      final edgeCount = willClose ? _points.length : lastIndex;
      for (var i = 0; i < edgeCount; i++) {
        final a = _points[i];
        final b = _points[(i + 1) % _points.length];
        final mid = _midpoint(a, b);
        final icon = _edgeLabelIcons[i] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        edgeMarkers.add(
          Marker(
            markerId: MarkerId('e$i'),
            position: mid,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndex: 2,
            // Important: labels should NOT block taps used to add points.
            consumeTapEvents: false,
          ),
        );
      }
    }

    final markers = <Marker>{...vertexMarkers, ...edgeMarkers};

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Undo last point',
            onPressed: _points.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _points.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
          TextButton(
            onPressed:
                _canFinish ? () => Navigator.of(context).pop(_points) : null,
            child: const Text(
              'Next',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 16),
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            markers: markers,
            polygons: {
              if (polygon != null) polygon,
            },
            onTap: _addPoint,
            onLongPress: _addPoint,
            onMapCreated: (c) => _controller = c,
          ),
          Positioned(
            left: 16,
            bottom: 92,
            child: _mapControlButton(
              icon: _mapType == MapType.hybrid
                  ? Icons.map_outlined
                  : Icons.satellite_alt_outlined,
              tooltip: _mapType == MapType.hybrid
                  ? 'Switch to map view'
                  : 'Switch to satellite view',
              onPressed: _toggleMapType,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 92,
            child: _mapZoomControl(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined,
                        size: 18, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _canFinish
                            ? 'Tap map to add points. Press Next to continue.'
                            : 'Tap map to add points (${_points.length}/3).',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
