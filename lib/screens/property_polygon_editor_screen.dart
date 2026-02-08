import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_place/google_place.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/search_constants.dart';
import '../models/map_viewport_models.dart';
import '../services/mobile_bff_map_api.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';

class PropertyPolygonEditorScreen extends StatefulWidget {
  const PropertyPolygonEditorScreen({
    super.key,
    required this.mode,
    this.initialCenter,
    this.initialPoints,
    this.bearerToken,
    this.excludePropertyId,
    this.onNext,
    this.popOnNext = true,
  });

  final PropertyPolygonEditorMode mode;
  final LatLng? initialCenter;
  final List<LatLng>? initialPoints;
  final String? bearerToken;
  final String? excludePropertyId;
  final Future<void> Function(List<LatLng> points)? onNext;
  final bool popOnNext;

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
  static const Color _viewportGrayStroke = Color(0xFF4B5563);
  static const Color _viewportGrayFill = Color(0x654B5563);

  late final LatLng _center;
  List<LatLng> _points = <LatLng>[];
  int _geometryRevision = 0;

  final MobileBffMapApi _mapApi = MobileBffMapApi();
  Timer? _viewportDebounce;
  int _viewportSeq = 0;
  Set<Polygon> _viewportPropertyPolygons = const <Polygon>{};

  final Map<String, BitmapDescriptor> _labelIconCache =
      <String, BitmapDescriptor>{};
  final Map<int, BitmapDescriptor> _edgeLabelIcons = <int, BitmapDescriptor>{};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  GooglePlace? _googlePlace;
  Timer? _searchDebounce;
  int _autocompleteSeq = 0;
  bool _isAutocompleteLoading = false;
  final List<AutocompletePrediction> _predictions = <AutocompletePrediction>[];

  Timer? _dragUpdateThrottle;
  int? _pendingDragIndex;
  LatLng? _pendingDragPoint;

  GoogleMapController? _controller;

  MapType _mapType = MapType.hybrid;
  bool _showSatelliteLabels = true;
  String? _lightMapStyle;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMapStyle());

    _center = _resolveInitialCenter();

    final seedPoints = widget.initialPoints ?? const <LatLng>[];
    if (seedPoints.isNotEmpty) {
      final normalized = _normalizeInitialPoints(seedPoints);
      _points = normalized;
      if (_points.isNotEmpty) {
        _geometryRevision = 1;
        unawaited(_refreshEdgeLabels());
      }
    }

    final key = googlePlacesApiKey.trim();
    if (key.isNotEmpty && key != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(key);
    }

    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && mounted) {
        setState(() {
          _predictions.clear();
          _isAutocompleteLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _viewportDebounce?.cancel();
    _searchDebounce?.cancel();
    _dragUpdateThrottle?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _scheduleViewportFetch() {
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_fetchViewportPolygons());
    });
  }

  Future<void> _fetchViewportPolygons() async {
    final controller = _controller;
    if (controller == null) return;

    final requestId = ++_viewportSeq;
    LatLngBounds bounds;
    double zoom;
    try {
      bounds = await controller.getVisibleRegion();
      zoom = await controller.getZoomLevel();
    } catch (_) {
      return;
    }

    MapViewportResponse response;
    try {
      response = await _mapApi.getViewport(
        bounds: bounds,
        zoom: zoom,
        bearerToken: widget.bearerToken,
      );
    } catch (_) {
      return;
    }

    if (!mounted || requestId != _viewportSeq) return;

    final excludeId = widget.excludePropertyId?.trim();
    final polygons = <Polygon>{};
    for (final feature in response.properties) {
      if (excludeId != null && excludeId.isNotEmpty) {
        if (feature.propertyId.trim() == excludeId) {
          continue;
        }
      }

      final rings = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
      if (rings.isEmpty) continue;

      for (var i = 0; i < rings.length; i++) {
        final ring = rings[i];
        if (ring.length < 3) continue;
        polygons.add(
          Polygon(
            polygonId:
                PolygonId('vp:${feature.propertyId}:${feature.featureId}:$i'),
            points: ring,
            strokeColor: _viewportGrayStroke,
            fillColor: _viewportGrayFill,
            strokeWidth: 4,
            zIndex: 1,
            consumeTapEvents: false,
          ),
        );
      }
    }

    if (!mounted || requestId != _viewportSeq) return;
    setState(() {
      _viewportPropertyPolygons = Set<Polygon>.unmodifiable(polygons);
    });
  }

  LatLng _resolveInitialCenter() {
    final center = widget.initialCenter;
    if (center != null) return center;

    final points = widget.initialPoints;
    if (points != null && points.isNotEmpty) {
      return _boundsCenter(points);
    }

    return _fallbackCenter;
  }

  List<LatLng> _normalizeInitialPoints(List<LatLng> points) {
    if (points.length < 2) return List<LatLng>.from(points);
    final first = points.first;
    final last = points.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return List<LatLng>.from(points.sublist(0, points.length - 1));
    }
    return List<LatLng>.from(points);
  }

  LatLng _boundsCenter(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    return LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _closeSearchSuggestions({bool dismissKeyboard = false}) {
    if (!mounted) return;
    if (_predictions.isEmpty && !_isAutocompleteLoading) {
      if (dismissKeyboard) _dismissKeyboard();
      return;
    }
    setState(() {
      _predictions.clear();
      _isAutocompleteLoading = false;
    });
    if (dismissKeyboard) _dismissKeyboard();
  }

  Future<void> _moveCameraTo(LatLng target, {double zoom = 16}) async {
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  Future<void> _fitCameraToPoints(List<LatLng> points) async {
    final controller = _controller;
    if (controller == null || points.isEmpty) return;

    if (points.length == 1) {
      await _moveCameraTo(points.first, zoom: 17);
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  void _onSearchQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty || _googlePlace == null) {
      if (!mounted) return;
      setState(() {
        _predictions.clear();
        _isAutocompleteLoading = false;
      });
      return;
    }

    final int requestId = ++_autocompleteSeq;
    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      setState(() {
        _isAutocompleteLoading = true;
      });

      try {
        final response = await _googlePlace!.autocomplete.get(
          query,
          language: 'en',
          location: tamilNaduBiasPoint,
          radius: tamilNaduRadiusMeters,
          strictbounds: true,
          components: [Component('country', 'in')],
        );

        if (!mounted || requestId != _autocompleteSeq) return;
        setState(() {
          _predictions
            ..clear()
            ..addAll(response?.predictions ?? const <AutocompletePrediction>[]);
        });
      } catch (_) {
        // Ignore transient failures (network/quota). Keep UI responsive.
      } finally {
        if (mounted && requestId == _autocompleteSeq) {
          setState(() {
            _isAutocompleteLoading = false;
          });
        }
      }
    });
  }

  double _suggestZoomForPlaceTypes(List<String> types, String label) {
    // Keep consistent with SearchOverlay.
    final set = types.map((t) => t.trim().toLowerCase()).toSet();
    if (set.contains('country')) return 5.5;
    if (set.contains('administrative_area_level_1')) return 8.5;

    if (set.contains('locality') ||
        set.contains('administrative_area_level_2')) {
      final normalizedName = label.trim().toLowerCase();
      const majorCitiesAtCityZoom = <String>{
        'madurai',
        'coimbatore',
        'chennai',
      };
      return majorCitiesAtCityZoom.contains(normalizedName) ? 13.8 : 15.8;
    }

    if (set.contains('sublocality') ||
        set.contains('sublocality_level_1') ||
        set.contains('neighborhood')) {
      return 15.8;
    }

    if (set.contains('route')) return 15.8;
    if (set.contains('street_address') ||
        set.contains('premise') ||
        set.contains('establishment') ||
        set.contains('point_of_interest')) {
      return 15.8;
    }

    return 15.8;
  }

  Future<void> _handlePredictionTap(AutocompletePrediction prediction) async {
    final placeId = prediction.placeId;
    if (placeId == null || _googlePlace == null) return;

    final mainText =
        prediction.structuredFormatting?.mainText ?? prediction.description;
    final fallbackLabel = prediction.description ?? mainText ?? 'Selected';

    if (!mounted) return;
    setState(() {
      _isAutocompleteLoading = true;
    });

    try {
      final details = await _googlePlace!.details.get(placeId);
      final location = details?.result?.geometry?.location;
      if (location == null) return;

      final label = details?.result?.name ?? fallbackLabel;
      final latLng = LatLng(location.lat ?? 0, location.lng ?? 0);

      final types = details?.result?.types?.whereType<String>().toList() ??
          const <String>[];
      final zoom = _suggestZoomForPlaceTypes(types, label);

      await _moveCameraTo(latLng, zoom: zoom);
      if (!mounted) return;
      setState(() {
        _searchController.text = label;
        _predictions.clear();
      });
      _dismissKeyboard();
    } catch (_) {
      // Ignore selection errors.
    } finally {
      if (mounted) {
        setState(() {
          _isAutocompleteLoading = false;
        });
      }
    }
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
      _points = <LatLng>[..._points, p];
      _geometryRevision++;
      _predictions.clear();
      _isAutocompleteLoading = false;
    });
    HapticFeedback.selectionClick();
    unawaited(_refreshEdgeLabels());
    _dismissKeyboard();
  }

  void _undo() {
    if (_points.isEmpty) return;
    setState(() {
      _points = _points.sublist(0, _points.length - 1);
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _clear() {
    if (_points.isEmpty) return;
    setState(() {
      _points = <LatLng>[];
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _updatePoint(int index, LatLng p) {
    if (index < 0 || index >= _points.length) return;
    setState(() {
      final next = List<LatLng>.from(_points);
      next[index] = p;
      _points = next;
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _updatePointDuringDrag(int index, LatLng p) {
    if (index < 0 || index >= _points.length) return;

    _pendingDragIndex = index;
    _pendingDragPoint = p;

    if (_dragUpdateThrottle?.isActive ?? false) return;
    _dragUpdateThrottle = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      final i = _pendingDragIndex;
      final point = _pendingDragPoint;
      if (i == null || point == null) return;
      if (i < 0 || i >= _points.length) return;

      setState(() {
        final next = List<LatLng>.from(_points);
        next[i] = point;
        _points = next;
        _geometryRevision++;
      });
    });
  }

  bool get _canFinish => _points.length >= 3;

  Future<void> _zoomIn() async {
    _closeSearchSuggestions(dismissKeyboard: true);
    await _controller?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    _closeSearchSuggestions(dismissKeyboard: true);
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }

  void _toggleMapType() {
    _closeSearchSuggestions(dismissKeyboard: true);
    setState(() {
      // Toggle between map view (normal) and satellite view.
      final satelliteType =
          _showSatelliteLabels ? MapType.hybrid : MapType.satellite;
      final isSatellite =
          _mapType == MapType.hybrid || _mapType == MapType.satellite;
      _mapType = isSatellite ? MapType.normal : satelliteType;
    });
  }

  void _setShowSatelliteLabels(bool show) {
    if (_showSatelliteLabels == show) return;
    _closeSearchSuggestions(dismissKeyboard: true);
    setState(() {
      _showSatelliteLabels = show;
      // Match web semantics: labels ON => hybrid, labels OFF => satellite.
      _mapType = show ? MapType.hybrid : MapType.satellite;
    });
  }

  Widget _mapLabelsToggle() {
    const teal = Color(0xFF0FAD97);
    const bg = Colors.white;

    void toggle(bool nextShowLabels) {
      _setShowSatelliteLabels(nextShowLabels);
    }

    final showLabels = _showSatelliteLabels;

    return Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => toggle(!showLabels),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: teal, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: showLabels,
                onChanged: (v) => toggle(v ?? true),
                activeColor: teal,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 2),
              const Text(
                'Labels',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
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

  Widget _topMapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? iconColor,
  }) {
    const radius = 8.0;
    const size = 40.0;
    final enabled = onPressed != null;
    const teal = Color(0xFF0FAD97);

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.white,
          elevation: 4,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: enabled ? teal : teal.withOpacity(0.45),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? (iconColor ?? const Color(0xFF1F2937))
                  : const Color(0xFF94A3B8),
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

    final revision = _geometryRevision;
    final points = List<LatLng>.from(_points);

    // Only show labels when we have at least 2 points.
    if (points.length < 2) {
      if (!mounted) return;
      setState(() {
        _edgeLabelIcons.clear();
      });
      return;
    }

    final lastIndex = points.length - 1;
    final willClose = points.length >= 3;
    final edgeCount = willClose ? points.length : lastIndex;

    final icons = <int, BitmapDescriptor>{};
    for (var i = 0; i < edgeCount; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final meters = _distanceMeters(a, b);
      final label = _formatFeet(meters);
      icons[i] = await _labelIcon(label);
    }

    if (!mounted || revision != _geometryRevision) return;
    setState(() {
      _edgeLabelIcons
        ..clear()
        ..addAll(icons);
    });
  }

  Widget _buildSearchBox(BuildContext context) {
    final bool isEnabled = _googlePlace != null;
    final bool showSuggestions = _predictions.isNotEmpty;
    const double radius = 10;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.search, color: Colors.grey, size: 22),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      enabled: isEnabled,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search for places...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        setState(() {});
                        _onSearchQueryChanged(v);
                      },
                      onTap: () {
                        // Ensure dropdown appears under the bar.
                        if (_searchController.text.trim().isNotEmpty) {
                          _onSearchQueryChanged(_searchController.text);
                        }
                      },
                      onSubmitted: (_) => _dismissKeyboard(),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _predictions.clear();
                          _isAutocompleteLoading = false;
                        });
                      },
                    ),
                  const SizedBox(width: 6),
                ],
              ),
              if (_isAutocompleteLoading)
                const LinearProgressIndicator(minHeight: 2)
              else if (!isEnabled)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: ApiKeyMissingBanner(),
                )
              else if (showSuggestions) ...[
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _predictions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      final prediction = _predictions[index];
                      final mainText =
                          prediction.structuredFormatting?.mainText ??
                              prediction.description ??
                              '';
                      final secondaryText =
                          prediction.structuredFormatting?.secondaryText;

                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.location_on,
                          color: Color(0xFF0FAD97),
                        ),
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.3,
                            ),
                            children: [
                              TextSpan(
                                text: mainText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if ((secondaryText ?? '').trim().isNotEmpty)
                                TextSpan(
                                  text: ' ${secondaryText!.trim()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF475467),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        onTap: () => _handlePredictionTap(prediction),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == PropertyPolygonEditorMode.add
        ? 'Add Property'
        : 'Edit Property';

    final polygon = _points.length >= 3
        ? Polygon(
            polygonId: PolygonId('draft_$_geometryRevision'),
            points: _points,
            strokeWidth: 3,
            strokeColor: const Color(0xFF0FAD97),
            fillColor: const Color(0x330FAD97),
            zIndex: 3,
            consumeTapEvents: false,
          )
        : null;

    final polylinePoints = _points.length >= 3
        ? <LatLng>[..._points, _points.first]
        : <LatLng>[..._points];

    final draftPolyline = _points.length >= 2
        ? Polyline(
            polylineId: PolylineId('draft_line_$_geometryRevision'),
            points: polylinePoints,
            width: 3,
            color: const Color(0xFF0FAD97),
            zIndex: 3,
          )
        : null;

    final vertexMarkers = <Marker>{
      for (var i = 0; i < _points.length; i++)
        Marker(
          markerId: MarkerId('v$i'),
          position: _points[i],
          draggable: true,
          onDrag: (p) => _updatePointDuringDrag(i, p),
          onDragEnd: (p) => _updatePoint(i, p),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
    };

    final edgeMarkers = <Marker>{};
    final showEdgeMarkers = _points.length >= 2;
    if (showEdgeMarkers) {
      final willClose = _points.length >= 3;
      final lastIndex = _points.length - 1;
      final edgeCount = willClose ? _points.length : lastIndex;
      for (var i = 0; i < edgeCount; i++) {
        final a = _points[i];
        final b = _points[(i + 1) % _points.length];
        final mid = _midpoint(a, b);
        final icon = _edgeLabelIcons[i];
        if (icon == null) {
          // Avoid showing default pins (and avoid the old green marker issue).
          // Labels will appear once the bitmap finishes rendering.
          continue;
        }
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
        titleSpacing: 6,
        leadingWidth: 44,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _canFinish
                  ? () async {
                      final navigator = Navigator.of(context);
                      if (widget.onNext != null) {
                        await widget.onNext!(_points);
                        if (!mounted) return;
                        if (widget.popOnNext) {
                          navigator.pop(_points);
                        }
                        return;
                      }
                      navigator.pop(_points);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0FAD97),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            markers: markers,
            polylines: {
              if (draftPolyline != null) draftPolyline,
            },
            polygons: {
              ..._viewportPropertyPolygons,
              if (polygon != null) polygon,
            },
            onTap: _addPoint,
            onLongPress: _addPoint,
            onCameraMoveStarted: () =>
                _closeSearchSuggestions(dismissKeyboard: true),
            onCameraMove: (position) {
              // Keep map type stable in the polygon editor; labels are driven
              // by the "Labels" checkbox and map/satellite by the map button.
            },
            onCameraIdle: _scheduleViewportFetch,
            onMapCreated: (c) {
              _controller = c;
              _scheduleViewportFetch();
              if (_points.isNotEmpty) {
                unawaited(_fitCameraToPoints(_points));
              }
            },
          ),
          if (widget.mode == PropertyPolygonEditorMode.add)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: _buildSearchBox(context),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _mapLabelsToggle(),
                      const Spacer(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _topMapActionButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Clear',
                            onPressed: _points.isEmpty ? null : _clear,
                            iconColor: const Color(0xFFDC2626),
                          ),
                          const SizedBox(height: 10),
                          _topMapActionButton(
                            icon: Icons.undo,
                            tooltip: 'Undo last point',
                            onPressed: _points.isEmpty ? null : _undo,
                          ),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _mapControlButton(
                  icon: _mapType == MapType.hybrid
                      ? Icons.map_outlined
                      : Icons.satellite_alt_outlined,
                  tooltip: _mapType == MapType.hybrid
                      ? 'Switch to map view'
                      : 'Switch to satellite view',
                  onPressed: _toggleMapType,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
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
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 36),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.touch_app_outlined,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _canFinish
                                        ? 'Press Next to continue'
                                        : 'Tap map to add points (${_points.length}/3).',
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    style: const TextStyle(
                                      fontSize: 12,
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
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _mapZoomControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
