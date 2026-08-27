import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:location/location.dart' as loc;

import '../constants/api_constants.dart';
import '../constants/search_constants.dart';
import '../models/map_viewport_models.dart';
import '../services/mobile_bff_layouts_api.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/layout_qr_code_sheet.dart';
import '../widgets/toast_message.dart';

/// Screen for admin users to create a new layout by drawing boundary and filling details.
class LayoutDetailsFormScreen extends StatefulWidget {
  static const int minimumRequiredPoints = 4;

  const LayoutDetailsFormScreen({
    super.key,
    this.initialCenter,
    this.initialZoom,
    this.isFarmLand = false,
  });

  final LatLng? initialCenter;
  final double? initialZoom;
  final bool isFarmLand;

  @override
  State<LayoutDetailsFormScreen> createState() =>
      _LayoutDetailsFormScreenState();
}

class _LayoutDetailsFormScreenState extends State<LayoutDetailsFormScreen> {
  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629); // India
  static const Color _viewportGrayStroke = Color(0xFF4B5563);
  static const Color _viewportGrayFill = Color(0x654B5563);

  late final LatLng _center;
  late final double _zoom;
  List<LatLng> _boundaryPoints = <LatLng>[];
  int _geometryRevision = 0;

  final Map<String, BitmapDescriptor> _labelIconCache =
      <String, BitmapDescriptor>{};
  final Map<int, BitmapDescriptor> _edgeLabelIcons = <int, BitmapDescriptor>{};

  final MobileBffLayoutsApi _layoutsApi = MobileBffLayoutsApi();
  final MobileBffMapApi _mapApi = MobileBffMapApi();
  Timer? _viewportDebounce;
  int _viewportSeq = 0;
  Set<Polygon> _viewportPropertyPolygons = const <Polygon>{};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  GooglePlace? _googlePlace;
  Timer? _searchDebounce;
  int _autocompleteSeq = 0;
  bool _isAutocompleteLoading = false;
  final List<AutocompletePrediction> _predictions = <AutocompletePrediction>[];

  GoogleMapController? _controller;

  MapType _mapType = MapType.hybrid;
  bool _showSatelliteLabels = true;
  String? _lightMapStyle;
  bool _isLocating = false;

  // Form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _surveyNumberController = TextEditingController();
  final TextEditingController _approvalNumberController =
      TextEditingController();
  final TextEditingController _locationDetailsController =
      TextEditingController();
  final TextEditingController _additionalDetailsController =
      TextEditingController();
    final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactNumbersController =
      TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _plotsCountController = TextEditingController();

  bool _isSaving = false;
  bool _showForm = false;

  String get _entityLabel => widget.isFarmLand ? 'Farm Land' : 'Layout';
  String get _plotLabel => widget.isFarmLand ? 'Land' : 'Plot';

  @override
  void initState() {
    super.initState();
    unawaited(_loadMapStyle());

    _center = widget.initialCenter ?? _fallbackCenter;
    _zoom = widget.initialZoom ?? 16;

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
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _viewportDebounce?.cancel();
    _nameController.dispose();
    _areaController.dispose();
    _priceController.dispose();
    _surveyNumberController.dispose();
    _approvalNumberController.dispose();
    _locationDetailsController.dispose();
    _additionalDetailsController.dispose();
    _contactNameController.dispose();
    _contactNumbersController.dispose();
    _descriptionController.dispose();
    _plotsCountController.dispose();
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

    // Get bearer token from AuthScope
    String? bearerToken;
    try {
      final authState = AuthScope.of(context);
      bearerToken = authState.session?.token;
    } catch (_) {
      // No auth scope available
    }

    MapViewportResponse response;
    try {
      response = await _mapApi.getViewport(
        bounds: bounds,
        zoom: zoom,
        bearerToken: bearerToken,
      );
    } catch (_) {
      return;
    }

    if (!mounted || requestId != _viewportSeq) return;

    final polygons = <Polygon>{};
    for (final feature in response.properties) {
      final rings = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
      if (rings.isEmpty) continue;

      for (var i = 0; i < rings.length; i++) {
        final ring = rings[i];
        if (ring.length < 4) continue;
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

  Future<void> _loadMapStyle() async {
    final style =
        await rootBundle.loadString('assets/map_light.json').catchError((_) {
      return '';
    });
    if (mounted) {
      setState(() {
        _lightMapStyle = style;
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _boundaryPoints = [..._boundaryPoints, point];
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _undoLastPoint() {
    if (_boundaryPoints.isEmpty) return;
    setState(() {
      _boundaryPoints = _boundaryPoints.sublist(0, _boundaryPoints.length - 1);
      _geometryRevision++;
    });
    unawaited(_refreshEdgeLabels());
  }

  void _clearAllPoints() {
    if (_boundaryPoints.isEmpty) return;
    setState(() {
      _boundaryPoints = <LatLng>[];
      _geometryRevision++;
      _edgeLabelIcons.clear();
    });
  }

  void _toggleMapType() {
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

  Future<void> _goToMyLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location = loc.Location();

      // Check if location service is enabled
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          if (mounted) {
            ToastMessage.show(context, 'Location services are disabled');
          }
          return;
        }
      }

      // Check permission
      loc.PermissionStatus permission = await location.hasPermission();
      if (permission == loc.PermissionStatus.denied) {
        permission = await location.requestPermission();
        if (permission != loc.PermissionStatus.granted) {
          if (mounted) {
            ToastMessage.show(context, 'Location permission denied');
          }
          return;
        }
      }

      if (permission == loc.PermissionStatus.deniedForever) {
        if (mounted) {
          ToastMessage.show(context, 'Location permission permanently denied');
        }
        return;
      }

      // Get current position
      final locationData = await location
          .getLocation()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Location timed out'),
          );

      if (locationData.latitude != null && locationData.longitude != null) {
        final myLocation =
            LatLng(locationData.latitude!, locationData.longitude!);

        // Animate camera to current location
        await _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(
            myLocation,
            18.0,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ToastMessage.show(context, 'Failed to get location');
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions.clear();
        _isAutocompleteLoading = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchAutocomplete(query);
    });
  }

  Future<void> _fetchAutocomplete(String query) async {
    final place = _googlePlace;
    if (place == null) return;

    final requestSeq = ++_autocompleteSeq;
    setState(() {
      _isAutocompleteLoading = true;
    });

    try {
      final result = await place.autocomplete.get(
        query,
        components: [Component('country', 'in')],
      );
      if (!mounted || requestSeq != _autocompleteSeq) return;

      setState(() {
        _predictions.clear();
        _predictions.addAll(result?.predictions ?? []);
        _isAutocompleteLoading = false;
      });
    } catch (_) {
      if (!mounted || requestSeq != _autocompleteSeq) return;
      setState(() {
        _isAutocompleteLoading = false;
      });
    }
  }

  Future<void> _onPredictionSelected(AutocompletePrediction prediction) async {
    _searchFocusNode.unfocus();
    final place = _googlePlace;
    if (place == null) return;

    final placeId = prediction.placeId;
    if (placeId == null) return;

    try {
      final details = await place.details.get(placeId);
      final loc = details?.result?.geometry?.location;
      if (loc != null && _controller != null) {
        await _controller!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(loc.lat!, loc.lng!), 18),
        );
      }
    } catch (_) {
      // ignore
    }

    setState(() {
      _searchController.clear();
      _predictions.clear();
    });
  }

  void _proceedToForm() {
    if (_boundaryPoints.length < LayoutDetailsFormScreen.minimumRequiredPoints) {
      ToastMessage.show(
        context,
        'Draw at least ${LayoutDetailsFormScreen.minimumRequiredPoints} points to define boundary',
      );
      return;
    }
    setState(() {
      _showForm = true;
    });
  }

  void _backToMap() {
    setState(() {
      _showForm = false;
    });
  }

  Future<void> _saveLayout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ToastMessage.show(context, 'Please enter a ${_entityLabel.toLowerCase()} name');
      return;
    }

    if (_boundaryPoints.length < LayoutDetailsFormScreen.minimumRequiredPoints) {
      ToastMessage.show(
        context,
        '$_entityLabel boundary must have at least ${LayoutDetailsFormScreen.minimumRequiredPoints} points',
      );
      return;
    }

    final token = AuthScope.of(context).session?.token;
    if (token == null || token.isEmpty) {
      ToastMessage.show(context, 'Please login to create a ${_entityLabel.toLowerCase()}');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Convert LatLng list to [[lat, lng], ...] array
      final boundaryLatLng = _boundaryPoints
          .map((p) => [p.latitude, p.longitude])
          .toList(growable: false);

      final plotsCountText = _plotsCountController.text.trim();
      final plotsCount =
          plotsCountText.isNotEmpty ? int.tryParse(plotsCountText) : null;

      final response = await _layoutsApi.createLayoutDraft(
        name: name,
        boundaryLatLng: boundaryLatLng,
        isFarmLand: widget.isFarmLand,
        area: _areaController.text.trim(),
        price: _priceController.text.trim(),
        surveyNumber:
            widget.isFarmLand ? null : _surveyNumberController.text.trim(),
        approvalNumber: _approvalNumberController.text.trim(),
        locationDetails: _locationDetailsController.text.trim(),
        additionalDetails: _additionalDetailsController.text,
        contactName: _contactNameController.text.trim(),
        contactNumbers: _contactNumbersController.text.trim(),
        description: _descriptionController.text.trim(),
        plotsCount: plotsCount,
        bearerToken: token,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ToastMessage.show(context, '$_entityLabel created successfully!');

      // Show QR code sheet
      await _showQrCodeSheet(response);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on LayoutsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, 'Failed to create ${_entityLabel.toLowerCase()}');
    }
  }

  Future<void> _showQrCodeSheet(LayoutDraftResponse layout) async {
    final shareUrl = _buildShareUrl(layout.id, layout.shortCode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LayoutQrCodeSheet(
        layoutId: layout.id,
        layoutName: layout.name,
        shareUrl: shareUrl,
      ),
    );
  }

  String _buildShareUrl(String layoutId, [String? shortCode]) {
    final base = ApiConstants.webBaseUrl.replaceAll(RegExp(r'/$'), '');
    // Use short URL if available for cleaner QR codes
    if (shortCode != null && shortCode.isNotEmpty) {
      return '$base/s/$shortCode';
    }
    return '$base/property/Layout/$layoutId';
  }

  Set<Polygon> _buildPolygons() {
    final polygons = <Polygon>{..._viewportPropertyPolygons};

    if (_boundaryPoints.length >= LayoutDetailsFormScreen.minimumRequiredPoints) {
      polygons.add(
        Polygon(
          polygonId: PolygonId('layout_boundary_$_geometryRevision'),
          points: _boundaryPoints,
          strokeWidth: 3,
          strokeColor: const Color(0xFF0FAD97),
          fillColor: const Color(0x330FAD97),
          consumeTapEvents: false,
          zIndex: 10,
        ),
      );
    }

    return polygons;
  }

  Set<Marker> _buildMarkers() {
    // Vertex markers
    final vertexMarkers = <Marker>{};
    for (var i = 0; i < _boundaryPoints.length; i++) {
      vertexMarkers.add(
        Marker(
          markerId: MarkerId('v$i'),
          position: _boundaryPoints[i],
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          draggable: true,
          onDrag: (newPos) {
            setState(() {
              _boundaryPoints = List<LatLng>.from(_boundaryPoints)
                ..[i] = newPos;
            });
          },
          onDragEnd: (newPos) {
            setState(() {
              _boundaryPoints = List<LatLng>.from(_boundaryPoints)
                ..[i] = newPos;
              _geometryRevision++;
            });
            unawaited(_refreshEdgeLabels());
          },
        ),
      );
    }

    // Edge label markers (measurements)
    final edgeMarkers = <Marker>{};
    final showEdgeMarkers = _boundaryPoints.length >= 2;
    if (showEdgeMarkers) {
      final willClose = _boundaryPoints.length >= LayoutDetailsFormScreen.minimumRequiredPoints;
      final lastIndex = _boundaryPoints.length - 1;
      final edgeCount = willClose ? _boundaryPoints.length : lastIndex;
      for (var i = 0; i < edgeCount; i++) {
        final a = _boundaryPoints[i];
        final b = _boundaryPoints[(i + 1) % _boundaryPoints.length];
        final mid = _midpoint(a, b);
        final icon = _edgeLabelIcons[i];
        if (icon == null) continue;
        edgeMarkers.add(
          Marker(
            markerId: MarkerId('e$i'),
            position: mid,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            zIndex: 2,
            consumeTapEvents: false,
          ),
        );
      }
    }

    return {...vertexMarkers, ...edgeMarkers};
  }

  Set<Polyline> _buildPolylines() {
    if (_boundaryPoints.length < 2) return const <Polyline>{};

    final polylinePoints = _boundaryPoints.length >= LayoutDetailsFormScreen.minimumRequiredPoints
        ? <LatLng>[..._boundaryPoints, _boundaryPoints.first]
        : <LatLng>[..._boundaryPoints];

    return <Polyline>{
      Polyline(
        polylineId: PolylineId('boundary_outline_$_geometryRevision'),
        points: polylinePoints,
        color: const Color(0xFF0FAD97),
        width: 3,
        zIndex: 3,
      ),
    };
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
    const paddingX = 2.0;
    const paddingY = 2.0;
    const fontSize = 11.0;

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
    final points = List<LatLng>.from(_boundaryPoints);

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
  Widget build(BuildContext context) {
    final keyAvailable = googlePlacesApiKey.trim().isNotEmpty &&
        googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY';

    // Account for Samsung/Android nav bar (edge-to-edge mode)
    final bottomSystemInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomPadding = bottomSystemInset > 0 ? bottomSystemInset : 0.0;

    if (_showForm) {
      return _buildFormView();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 6,
        leadingWidth: 44,
        title: const Text(
          'Draw Boundary',
          style: TextStyle(
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
              onPressed: _boundaryPoints.length >= LayoutDetailsFormScreen.minimumRequiredPoints
                  ? _proceedToForm
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
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: _zoom,
            ),
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
            onMapCreated: (controller) {
              _controller = controller;
              _scheduleViewportFetch();
            },
            onTap: _onMapTap,
            onCameraIdle: _scheduleViewportFetch,
            polygons: _buildPolygons(),
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            rotateGesturesEnabled: false,
          ),

          // API key warning
          if (!keyAvailable)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ApiKeyMissingBanner(),
            ),

          // Search bar
          if (keyAvailable)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search location...',
                        prefixIcon: _isAutocompleteLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _predictions.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
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
                            onPressed: _boundaryPoints.isEmpty
                                ? null
                                : _clearAllPoints,
                            iconColor: const Color(0xFFDC2626),
                          ),
                          const SizedBox(height: 10),
                          _topMapActionButton(
                            icon: Icons.undo,
                            tooltip: 'Undo last point',
                            onPressed:
                                _boundaryPoints.isEmpty ? null : _undoLastPoint,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_predictions.isNotEmpty)
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _predictions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final pred = _predictions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(
                              pred.structuredFormatting?.mainText ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              pred.structuredFormatting?.secondaryText ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onPredictionSelected(pred),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // Bottom controls: My Location + Map Type | Instructions | Zoom
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + bottomPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _mapControlButton(
                      icon: Icons.my_location,
                      tooltip: 'My Location',
                      onPressed: _goToMyLocation,
                      isLoading: _isLocating,
                    ),
                    const SizedBox(height: 10),
                    _mapControlButton(
                      icon: _mapType == MapType.hybrid
                          ? Icons.map_outlined
                          : Icons.satellite_alt_outlined,
                      tooltip: _mapType == MapType.hybrid
                          ? 'Switch to map view'
                          : 'Switch to satellite view',
                      onPressed: _toggleMapType,
                    ),
                  ],
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
                                    _boundaryPoints.length >= LayoutDetailsFormScreen.minimumRequiredPoints
                                        ? 'Press Next to continue'
                                        : 'Tap map to add points (${_boundaryPoints.length}/${LayoutDetailsFormScreen.minimumRequiredPoints}).',
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

  Future<void> _zoomIn() async {
    await _controller?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await _controller?.animateCamera(CameraUpdate.zoomOut());
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isLoading = false,
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
            onTap: isLoading ? null : onPressed,
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF1F2937)),
                      ),
                    ),
                  )
                : Icon(
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
              onPressed: _zoomIn,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: borderColor),
            segment(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onPressed: _zoomOut,
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

  Widget _buildFormView() {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_entityLabel Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _backToMap,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Boundary preview card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF059669),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Boundary Drawn',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          '${_boundaryPoints.length} points',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _backToMap,
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Name field (required)
            _buildTextField(
              controller: _nameController,
              label: '$_entityLabel Name *',
              hint: 'Enter ${_entityLabel.toLowerCase()} name',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Price
            _buildTextField(
              controller: _priceController,
              label: 'Price',
              hint: 'e.g., Rs 2000 per sqft',
            ),
            const SizedBox(height: 16),

            // Area and Plot Count row
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _areaController,
                    label: 'Area',
                    hint: 'e.g., 10 Acres',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _plotsCountController,
                    label: '$_plotLabel Count',
                    hint: 'e.g., 120',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!widget.isFarmLand) ...[
              // Survey Number
              _buildTextField(
                controller: _surveyNumberController,
                label: 'Survey Number',
                hint: 'Enter survey number',
                maxLines: 2,
              ),
              const SizedBox(height: 16),
            ],

            // Approval Number
            _buildTextField(
              controller: _approvalNumberController,
              label: 'Approval Number',
              hint: 'Enter approval number',
            ),
            const SizedBox(height: 16),

            // Location Details
            _buildTextField(
              controller: _locationDetailsController,
              label: 'Location Details',
              hint: 'Enter location/address',
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _contactNameController,
                    label: 'Contact Name',
                    hint: 'e.g., Jebasingh',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _contactNumbersController,
                    label: 'Contact Numbers',
                    hint: 'e.g., 9876543210',
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Additional Details
            _buildTextField(
              controller: _additionalDetailsController,
              label: 'Additional Details',
              hint: 'Any additional information',
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Description
            _buildTextField(
              controller: _descriptionController,
              label: 'Description',
              hint: 'Marketing description (optional)',
              maxLines: 4,
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton(
              onPressed: _isSaving ? null : _saveLayout,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0FAD97),
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save & Generate QR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF0FAD97), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
