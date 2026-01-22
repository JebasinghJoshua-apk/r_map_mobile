import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_place/google_place.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/search_constants.dart';
import '../widgets/api_key_missing_banner.dart';

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

  // Keep map type behavior aligned with the main map screen.
  // See: lib/screens/home_map_screen.helpers.dart
  static const double _hybridZoomEnter = 17.5;
  static const double _hybridZoomExit = 17.5;

  late final LatLng _center = widget.initialCenter ?? _fallbackCenter;
  final List<LatLng> _points = <LatLng>[];
  int _geometryRevision = 0;

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

  GoogleMapController? _controller;

  MapType _mapType = MapType.normal;
  String? _lightMapStyle;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMapStyle());

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
      _points.add(p);
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
      _points.removeLast();
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _clear() {
    if (_points.isEmpty) return;
    setState(() {
      _points.clear();
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _updatePoint(int index, LatLng p) {
    if (index < 0 || index >= _points.length) return;
    setState(() {
      _points[index] = p;
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
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

  Widget _mapEditControl() {
    const radius = 8.0;
    const size = 36.0;
    const borderColor = Color(0xFFE2E8F0);

    Widget segment({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      required bool enabled,
      required BorderRadius borderRadius,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 18,
                color:
                    enabled ? const Color(0xFF1F2937) : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      );
    }

    final canUndo = _points.isNotEmpty;
    final canClear = _points.isNotEmpty;

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
              icon: Icons.undo,
              tooltip: 'Undo last point',
              enabled: canUndo,
              onPressed: () {
                _closeSearchSuggestions(dismissKeyboard: true);
                _undo();
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: borderColor),
            segment(
              icon: Icons.delete_outline,
              tooltip: 'Clear',
              enabled: canClear,
              onPressed: () {
                _closeSearchSuggestions(dismissKeyboard: true);
                _clear();
              },
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

  @override
  void dispose() {
    _controller?.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search for places...',
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
        ? 'Add property'
        : 'Edit property';

    final polygon = _points.length >= 3
        ? Polygon(
            polygonId: PolygonId('draft_$_geometryRevision'),
            points: _points,
            strokeWidth: 3,
            strokeColor: const Color(0xFF0FAD97),
            fillColor: const Color(0x330FAD97),
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
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0FAD97),
          ),
        ),
        foregroundColor: const Color(0xFF0FAD97),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed:
                _canFinish ? () => Navigator.of(context).pop(_points) : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0FAD97),
            ),
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
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            markers: markers,
            polylines: {
              if (draftPolyline != null) draftPolyline,
            },
            polygons: {
              if (polygon != null) polygon,
            },
            onTap: _addPoint,
            onLongPress: _addPoint,
            onCameraMoveStarted: () =>
                _closeSearchSuggestions(dismissKeyboard: true),
            onCameraMove: (position) {
              final shouldBeHybrid = _mapType == MapType.hybrid
                  ? position.zoom >= _hybridZoomExit
                  : position.zoom >= _hybridZoomEnter;

              final nextMapType =
                  shouldBeHybrid ? MapType.hybrid : MapType.normal;
              if (nextMapType != _mapType) {
                setState(() {
                  _mapType = nextMapType;
                });
              }
            },
            onMapCreated: (c) => _controller = c,
          ),
          if (widget.mode == PropertyPolygonEditorMode.add)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildSearchBox(context),
              ),
            ),
          Positioned(
            right: 16,
            top: widget.mode == PropertyPolygonEditorMode.add ? 84 : 16,
            child: _mapEditControl(),
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
                const SizedBox(width: 8),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
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
                const SizedBox(width: 8),
                _mapZoomControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
