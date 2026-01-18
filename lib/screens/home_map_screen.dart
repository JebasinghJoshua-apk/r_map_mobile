import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

import '../constants/search_constants.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_plots_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/network_status_banner.dart';
import '../widgets/plot_details_panel.dart';
import '../widgets/property_details_panel.dart';
import '../widgets/search_overlay.dart';
import '../widgets/toast_message.dart';
import '../models/map_viewport_models.dart';
import 'layout_detail_screen.dart';
import 'property_detail_screen.dart';
import '../utils/route_observer.dart';

part 'home_map_screen.helpers.dart';
part 'home_map/home_map_filters.dart';
part 'home_map/home_map_viewport.dart';
part 'home_map/home_map_property_media.dart';
part 'home_map/home_map_carousel.dart';

class _PropertyMediaCacheEntry {
  const _PropertyMediaCacheEntry({
    required this.urls,
    required this.isLoading,
    required this.error,
    required this.requestSeq,
  });

  final List<String>? urls;
  final bool isLoading;
  final String? error;
  final int requestSeq;

  _PropertyMediaCacheEntry copyWith({
    List<String>? urls,
    bool? isLoading,
    String? error,
  }) {
    return _PropertyMediaCacheEntry(
      urls: urls,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      requestSeq: requestSeq,
    );
  }
}

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> with RouteAware {
  GoogleMapController? _mapController;
  GooglePlace? _googlePlace;
  late final MobileBffMapApi _mapApi;
  late final MobileBffPlotsApi _plotsApi;

  final _HomeMapIconFactory _iconFactory = _HomeMapIconFactory();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isOffline = false;

  String? _lightMapStyle;
  MapType _mapType = MapType.normal;
  final ValueNotifier<double> _zoomNotifier =
      ValueNotifier(_initialCameraPosition.zoom);

  bool _isViewportLoading = false;
  Timer? _viewportLoadingTimer;

  final LinkedHashMap<String, _ViewportRenderCacheEntry> _viewportCache =
      LinkedHashMap<String, _ViewportRenderCacheEntry>();

  CameraPosition _lastCameraPosition = _initialCameraPosition;
  double? _effectiveZoom;
  Timer? _viewportDebounceTimer;
  int _viewportRequestSeq = 0;
  String? _lastViewportSignature;
  DateTime? _lastViewportErrorAt;

  String? _selectedPropertyType; // null => All properties
  _PriceRangeFilter? _selectedPriceRange; // null => Any

  String? _lastViewportAuthKey;

  ModalRoute<void>? _routeSubscription;

  Set<Marker> _viewportMarkers = <Marker>{};

  Set<Marker> _plotLabelMarkers = <Marker>{};
  Set<Marker> _roadLabelMarkers = <Marker>{};
  Set<Marker> _amenityLabelMarkers = <Marker>{};

  Set<Polygon> _layoutPolygons = <Polygon>{};
  Set<Polygon> _propertyPolygons = <Polygon>{};
  Set<Polygon> _plotPolygons = <Polygon>{};
  Set<Polygon> _selectedPlotHighlightPolygons = <Polygon>{};
  Set<Polygon> _amenityPolygons = <Polygon>{};
  Set<Polygon> _roadPolygons = <Polygon>{};
  Set<Polyline> _roadPolylines = <Polyline>{};

  MapPlotFeature? _selectedPlot;
  int _plotFocusSeq = 0;

  MapPropertyFeature? _selectedProperty;
  List<String>? _selectedPropertyMediaUrls;
  bool _isSelectedPropertyMediaLoading = false;
  String? _selectedPropertyMediaError;
  int _propertyMediaSeq = 0;

  // Independent House carousel (viewport-only, sorted by distance to map center).
  List<MapPropertyFeature> _independentHousesInView =
      const <MapPropertyFeature>[];
  int _activeIndependentHouseIndex = 0;
  PageController? _independentHouseCarouselController;

  // Media cache keyed by "<propertyType>:<featureId>".
  final Map<String, _PropertyMediaCacheEntry> _propertyMediaCache =
      <String, _PropertyMediaCacheEntry>{};

  // Mirrors web MapViewportLayer: only allow plot status edits for plots under
  // layouts owned by the current user (within the current viewport response).
  Set<String> _ownedLayoutIds = <String>{};

  // Cached map of property features keyed by featureId.
  // Used for opening layout details from plot panels.
  Map<String, MapPropertyFeature> _propertyByFeatureId =
      <String, MapPropertyFeature>{};

  List<String> _layoutContactNumbersForPlot(MapPlotFeature plot) {
    final layoutId = plot.layoutId?.trim();
    if (layoutId == null || layoutId.isEmpty) {
      return const <String>[];
    }

    final feature = _propertyByFeatureId[layoutId];
    final meta = feature?.metadata;
    if (meta == null || meta.isEmpty) {
      return const <String>[];
    }

    final raw = (meta['contactNumbers'] ??
            meta['ContactNumbers'] ??
            meta['phoneNumber'] ??
            meta['PhoneNumber'])
        ?.trim();
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }

    final parts = raw
        .split(RegExp(r'[\n,;/|]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();

    final unique = <String>[];
    for (final value in parts) {
      if (!unique.contains(value)) {
        unique.add(value);
      }
    }
    return unique;
  }

  @override
  void initState() {
    super.initState();
    _mapApi = MobileBffMapApi();
    _plotsApi = MobileBffPlotsApi();
    _initConnectivity();
    _loadLightMapStyle();
    if (googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(googlePlacesApiKey);
    }
  }

  @override
  void didPopNext() {
    // Returning from a pushed screen (e.g. PropertyDetailScreen). Flutter may
    // restore focus to the last-focused text field, which reopens the keyboard.
    // Force-hide it for map UX.
    _dismissKeyboard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _routeSubscription) {
      if (_routeSubscription != null) {
        routeObserver.unsubscribe(this);
      }
      _routeSubscription = route;
      routeObserver.subscribe(this, route);
    }

    final session = AuthScope.of(context).session;
    final token = session?.token.trim();
    final userId = session?.user.id.trim();

    final authKey = (token != null &&
            token.isNotEmpty &&
            userId != null &&
            userId.isNotEmpty)
        ? '$userId:$token'
        : null;

    if (authKey == _lastViewportAuthKey) {
      return;
    }

    _lastViewportAuthKey = authKey;
    _lastViewportSignature = null;
    _viewportCache.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapController == null) return;
      _fetchViewport();
    });
  }

  Future<void> _initConnectivity() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _handleConnectivityChanged(initial);
    } catch (_) {
      // If the platform channel fails, just continue without offline banner.
    }

    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_handleConnectivityChanged);
  }

  void _handleConnectivityChanged(ConnectivityResult result) {
    if (!mounted) return;
    final nextOffline = result == ConnectivityResult.none;
    if (nextOffline == _isOffline) return;
    setState(() => _isOffline = nextOffline);
  }

  Future<void> _loadLightMapStyle() async {
    try {
      final style = await rootBundle.loadString(_lightMapStyleAssetPath);
      if (!mounted) return;
      setState(() {
        _lightMapStyle = style;
      });
    } catch (e) {
      debugPrint('Failed to load map style: $e');
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _routeSubscription = null;
    _mapController?.dispose();
    _viewportDebounceTimer?.cancel();
    _viewportLoadingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _zoomNotifier.dispose();
    super.dispose();
  }

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _moveCameraTo(LatLng target, String label, double zoom) async {
    if (_mapController == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );

    if (!mounted) return;
    final safeLabel = label.trim().isEmpty ? 'Selected place' : label.trim();
    ToastMessage.show(context, safeLabel);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraIdle() {
    if (_mapController == null) return;

    _viewportDebounceTimer?.cancel();
    _viewportDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      await _fetchViewport();
    });
  }

  MapViewportResponse _applyClientFilters(MapViewportResponse response) {
    final type = _selectedPropertyType?.trim();
    final range = _selectedPriceRange;
    if (type == null || type.isEmpty) return response;
    if (!_isPriceFilterEligiblePropertyType(type)) return response;
    if (type == 'Layout') return response;
    if (range == null) return response;

    final min = range.minRupees;
    final max = range.maxRupees;

    final filteredProperties = <MapPropertyFeature>[];
    for (final feature in response.properties) {
      final rawPrice = _getMetadataValue(
        feature.metadata,
        const <String>['price', 'listingPrice', 'salePrice', 'amount'],
      );
      final rupees = rawPrice == null ? null : _parsePriceToRupees(rawPrice);
      if (rupees == null) {
        continue;
      }
      if (min != null && rupees < min) continue;
      if (max != null && rupees > max) continue;
      filteredProperties.add(feature);
    }

    final allowedIds = filteredProperties
        .map((p) => p.propertyId.trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    final filteredPlots = response.plots.where((plot) {
      final id = plot.individualPlotsId?.trim();
      if (id == null || id.isEmpty) return true;
      return allowedIds.contains(id);
    }).toList(growable: false);

    final filteredRoads = response.roads.where((road) {
      final ip = road.individualPlotsId?.trim();
      if (ip != null && ip.isNotEmpty) {
        return allowedIds.contains(ip);
      }
      final land = road.landId?.trim();
      if (land != null && land.isNotEmpty) {
        return allowedIds.contains(land);
      }
      final comm = road.commercialSpaceId?.trim();
      if (comm != null && comm.isNotEmpty) {
        return allowedIds.contains(comm);
      }
      return true;
    }).toList(growable: false);

    return MapViewportResponse(
      detailLevel: response.detailLevel,
      properties: filteredProperties.toList(growable: false),
      plots: filteredPlots,
      roads: filteredRoads,
      amenities: response.amenities,
    );
  }

  _ViewportRenderCacheEntry _renderViewport({
    required MapViewportResponse response,
    required double zoom,
  }) {
    final propertyByFeatureId = <String, MapPropertyFeature>{};
    for (final feature in response.properties) {
      final id = feature.featureId.trim();
      if (id.isNotEmpty) {
        propertyByFeatureId[id] = feature;
      }
    }

    final ownedLayoutIds = <String>{};
    for (final feature in response.properties) {
      final normalizedType = feature.propertyType.trim().toLowerCase();
      if (normalizedType == 'layout' && feature.isOwnedByCurrentUser) {
        final id = feature.featureId.trim();
        if (id.isNotEmpty) {
          ownedLayoutIds.add(id);
        }
      }
    }

    final nextLayoutPolygons = <Polygon>{};
    final nextPropertyPolygons = <Polygon>{};
    var layoutFeatureCount = 0;
    var layoutPolygonCount = 0;
    final styleZoom = _effectiveZoom ?? zoom;
    for (final feature in response.properties) {
      final center = feature.centerPoint;
      if (center == null) continue;

      final normalizedType = feature.propertyType.trim().toLowerCase();
      final isLayout = normalizedType == 'layout';
      if (isLayout) {
        layoutFeatureCount++;
        final fillOpacity =
            zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
        final polygons = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          layoutPolygonCount++;
          nextLayoutPolygons.add(
            Polygon(
              polygonId: PolygonId('layout:${feature.featureId}:$i'),
              points: points,
              strokeWidth: _layoutBoundaryStrokeWidth,
              strokeColor: _layoutBoundaryStroke
                  .withOpacity(_layoutBoundaryStrokeOpacity),
              fillColor: _layoutBoundaryFill.withOpacity(fillOpacity),
              consumeTapEvents: false,
              zIndex: _propertyStyleForType('Layout').zIndex,
            ),
          );
        }
      } else {
        final polygons = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
        if (polygons.isEmpty) continue;

        final style = _propertyStyleForType(feature.propertyType);
        final isDetailedPlotGroup =
            feature.propertyType.trim() == 'IndividualPlots' &&
                response.detailLevel == MapDetailLevel.detailed;

        final strokeOpacity =
            isDetailedPlotGroup ? 0.92 : _propertyStrokeOpacity;
        final fillOpacity = isDetailedPlotGroup
            ? 0.0
            : _adjustFillOpacityForZoom(styleZoom, _propertyBaseFillOpacity);
        final strokeWidth = isDetailedPlotGroup
            ? _propertyBaseStrokeWidth
            : _adjustStrokeWidthForZoom(styleZoom, _propertyBaseStrokeWidth);

        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextPropertyPolygons.add(
            Polygon(
              polygonId: PolygonId(
                'prop:${feature.propertyType}:${feature.featureId}:$i',
              ),
              points: points,
              strokeWidth: strokeWidth,
              strokeColor: style.stroke.withOpacity(strokeOpacity),
              fillColor: style.fill.withOpacity(fillOpacity),
              consumeTapEvents: false,
              zIndex: style.zIndex,
            ),
          );
        }
      }
    }

    final shouldShowPolygons = zoom >= _minPlotPolygonZoom;
    final shouldShowRoads = zoom >= _minRoadOverlayZoom;
    final nextPlotPolygons = <Polygon>{};
    final nextAmenityPolygons = <Polygon>{};
    final nextRoadPolygons = <Polygon>{};
    final nextRoadPolylines = <Polyline>{};

    if (shouldShowPolygons) {
      for (final plot in response.plots) {
        final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
        final kind = _plotElementKind(plot);
        final isSold = plot.layoutId != null && _isSoldPlot(plot);

        Color stroke;
        Color fill;
        int strokeWidth;
        double strokeOpacity;
        double fillOpacity;
        int zIndex;

        if (kind == 'road') {
          stroke = _roadStroke;
          fill = _roadFill;
          strokeWidth = _roadStrokeWidth;
          strokeOpacity = _roadStrokeOpacity;
          fillOpacity = _roadFillOpacity;
          zIndex = 58;
        } else if (kind == 'boundary') {
          stroke = _layoutBoundaryStroke;
          fill = _layoutBoundaryFill;
          strokeWidth = _layoutBoundaryStrokeWidth;
          strokeOpacity = _layoutBoundaryStrokeOpacity;
          fillOpacity =
              zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
          zIndex = 45;
        } else if (isSold) {
          stroke = _soldPlotStroke;
          fill = _soldPlotFill;
          strokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
          strokeOpacity = _soldPlotStrokeOpacity;
          fillOpacity = _soldPlotFillOpacity;
          zIndex = 60;
        } else {
          stroke = _plotStroke;
          fill = _plotFill;
          strokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
          strokeOpacity = _plotStrokeOpacity;
          fillOpacity = _plotFillOpacity;
          zIndex = 60;
        }

        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextPlotPolygons.add(
            Polygon(
              polygonId: PolygonId('plot:${plot.plotId}:$i'),
              points: points,
              strokeWidth: strokeWidth,
              strokeColor: stroke.withOpacity(strokeOpacity),
              fillColor: fill.withOpacity(fillOpacity),
              consumeTapEvents: true,
              zIndex: zIndex,
              onTap: () => _handlePlotTapped(plot),
            ),
          );
        }
      }

      for (final amenity in response.amenities) {
        final polygons = GeoJson.tryParsePolygons(amenity.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextAmenityPolygons.add(
            Polygon(
              polygonId: PolygonId('amenity:${amenity.amenityId}:$i'),
              points: points,
              strokeWidth: _amenityStrokeWidth,
              strokeColor: _amenityStroke.withOpacity(_amenityStrokeOpacity),
              fillColor: _amenityFill.withOpacity(_amenityFillOpacity),
              consumeTapEvents: false,
              zIndex: 64,
            ),
          );
        }
      }
    }

    if (shouldShowRoads) {
      for (final road in response.roads) {
        final lines = GeoJson.tryParseLineStrings(road.roadGeoJson);

        if (lines.isNotEmpty) {
          for (var i = 0; i < lines.length; i++) {
            final points = lines[i];
            if (points.length < 2) continue;

            // Rough width scaling: keep readable at common zooms.
            final width = (road.widthInFeet ?? 12) >= 20
                ? _roadLineStrokeWidth + 2
                : _roadLineStrokeWidth;
            nextRoadPolylines.add(
              Polyline(
                polylineId: PolylineId('road:${road.roadId}:$i'),
                points: points,
                width: width,
                color: _roadLineStroke.withOpacity(_roadLineStrokeOpacity),
                geodesic: true,
              ),
            );
          }
          continue;
        }

        // Fallback: some datasets may encode roads as Polygon/MultiPolygon.
        final roadPolygons = GeoJson.tryParsePolygons(road.roadGeoJson);
        for (var i = 0; i < roadPolygons.length; i++) {
          final points = roadPolygons[i];
          if (points.length < 3) continue;
          nextRoadPolygons.add(
            Polygon(
              polygonId: PolygonId('roadpoly:${road.roadId}:$i'),
              points: points,
              strokeWidth: _roadStrokeWidth,
              strokeColor: _roadStroke.withOpacity(_roadStrokeOpacity),
              fillColor: _roadFill.withOpacity(_roadFillOpacity),
              consumeTapEvents: false,
            ),
          );
        }
      }
    }

    assert(() {
      if (layoutFeatureCount > 0 && layoutPolygonCount == 0) {
        debugPrint(
          'Viewport: found $layoutFeatureCount Layout properties but parsed 0 polygons. boundaryGeoJson may be empty/unsupported.',
        );
      }
      return true;
    }());

    return _ViewportRenderCacheEntry(
      markers: const <Marker>{},
      plotLabelMarkers: const <Marker>{},
      roadLabelMarkers: const <Marker>{},
      amenityLabelMarkers: const <Marker>{},
      layoutPolygons: Set<Polygon>.unmodifiable(nextLayoutPolygons),
      propertyPolygons: Set<Polygon>.unmodifiable(nextPropertyPolygons),
      plotPolygons: Set<Polygon>.unmodifiable(nextPlotPolygons),
      amenityPolygons: Set<Polygon>.unmodifiable(nextAmenityPolygons),
      roadPolygons: Set<Polygon>.unmodifiable(nextRoadPolygons),
      roadPolylines: Set<Polyline>.unmodifiable(nextRoadPolylines),
      ownedLayoutIds: Set<String>.unmodifiable(ownedLayoutIds),
      propertyByFeatureId:
          Map<String, MapPropertyFeature>.unmodifiable(propertyByFeatureId),
    );
  }

  void _handlePlotTapped(MapPlotFeature plot) {
    if (!mounted) return;
    setState(() {
      _selectedPlot = plot;
      _selectedPlotHighlightPolygons =
          _buildSelectedPlotHighlightPolygons(plot);
    });

    // Center the plot after selection so users immediately see what's selected.
    unawaited(_focusPlotOnMap(plot));
  }

  void _closePlotPanel() {
    if (!mounted) return;
    if (_selectedPlot == null) return;
    // Cancel any in-flight focus animation/clamp for the previous selection.
    _plotFocusSeq++;
    setState(() {
      _selectedPlot = null;
      _selectedPlotHighlightPolygons = const <Polygon>{};
    });
  }

  void _closePropertyPanel() {
    if (!mounted) return;
    if (_selectedProperty == null) return;
    setState(() {
      _selectedProperty = null;
      _selectedPropertyMediaUrls = null;
      _isSelectedPropertyMediaLoading = false;
      _selectedPropertyMediaError = null;
      _activeIndependentHouseIndex = 0;
    });

    // Cancel any in-flight media fetch.
    _propertyMediaSeq++;

    _independentHouseCarouselController?.dispose();
    _independentHouseCarouselController = null;
  }

  void _closeAnyPanel() {
    _closePlotPanel();
    _closePropertyPanel();
  }

  Set<Polygon> _buildSelectedPlotHighlightPolygons(MapPlotFeature plot) {
    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (polygons.isEmpty) return const <Polygon>{};

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    final baseStrokeWidth =
        _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
    final strokeWidth = baseStrokeWidth + _selectedPlotStrokeWidthBump;

    final next = <Polygon>{};
    for (var i = 0; i < polygons.length; i++) {
      final points = polygons[i];
      if (points.length < 3) continue;
      next.add(
        Polygon(
          polygonId: PolygonId('plot-selected:${plot.plotId}:$i'),
          points: points,
          strokeWidth: strokeWidth,
          strokeColor:
              _selectedPlotStroke.withOpacity(_selectedPlotStrokeOpacity),
          fillColor: _selectedPlotFill.withOpacity(_selectedPlotFillOpacity),
          consumeTapEvents: false,
          zIndex: _selectedPlotZIndex,
        ),
      );
    }

    return Set<Polygon>.unmodifiable(next);
  }

  Future<void> _focusPlotOnMap(MapPlotFeature plot) async {
    final controller = _mapController;
    if (controller == null) return;

    final focusSeq = ++_plotFocusSeq;

    // Strict zoom clamp: never exceed the max zoom (e.g. 20.5).
    // `newLatLngBounds` can temporarily zoom in beyond the max, so instead we
    // compute a center point and move the camera directly.
    LatLng? center = plot.centerPoint;

    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (center == null && polygons.isNotEmpty) {
      final points = <LatLng>[];
      for (final poly in polygons) {
        points.addAll(poly);
      }
      if (points.isNotEmpty) {
        center = _centerOfBounds(_boundsFromPoints(points));
      }
    }

    if (center == null) return;

    // Zoom behavior:
    // - If current zoom is below the target (20.5), zoom in to 20.5.
    // - If current zoom is already above 20.5, keep it (don't zoom out).
    double currentZoom;
    try {
      currentZoom = await controller.getZoomLevel();
    } catch (_) {
      currentZoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    }

    final nextZoom = math.max(currentZoom, _selectedPlotMaxFocusZoom);
    if (focusSeq != _plotFocusSeq) return;
    await _focusPropertyOnMap(target: center, zoom: nextZoom);
  }

  Future<void> _updatePlotStatus(MapPlotFeature plot, String status) async {
    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Login required');
    }

    await _plotsApi.updatePlotStatus(
      plotId: plot.plotId,
      status: status,
      bearerToken: token,
    );

    // Optimistically update the selected plot badge immediately.
    if (mounted) {
      final nextMeta = Map<String, String?>.from(plot.metadata);
      nextMeta['plotStatus'] = status;

      setState(() {
        if (_selectedPlot?.plotId == plot.plotId) {
          _selectedPlot = MapPlotFeature(
            plotId: plot.plotId,
            layoutId: plot.layoutId,
            individualPlotsId: plot.individualPlotsId,
            plotNumber: plot.plotNumber,
            boundaryGeoJson: plot.boundaryGeoJson,
            centerGeoJson: plot.centerGeoJson,
            metadata: nextMeta,
          );
        }
      });
    }

    // Force refresh: both client and BFF cache viewport responses.
    _viewportCache.clear();
    _lastViewportSignature = null;
    await _fetchViewport();
  }

  String? _plotAreaLabel(MapPlotFeature plot) {
    final meta = plot.metadata;
    for (final key in const <String>[
      'areaSqFt',
      'areaSqft',
      'area_sqft',
      'sqft',
      'plotArea',
      'area',
    ]) {
      final raw = meta[key]?.trim();
      if (raw == null || raw.isEmpty) continue;
      final numericText = raw.replaceAll(',', '');
      final value = double.tryParse(numericText);
      if (value == null) {
        // If the backend already includes unit, show as-is.
        return raw;
      }
      final rounded = value.round();
      return '$rounded sqft';
    }
    return null;
  }

  List<String> _plotTags(MapPlotFeature plot) {
    final meta = plot.metadata;
    final tags = <String>[];

    bool hasTruthy(List<String> keys) {
      for (final key in keys) {
        final v = meta[key]?.trim().toLowerCase();
        if (v == null || v.isEmpty) continue;
        if (v == 'true' || v == '1' || v == 'yes') return true;
      }
      return false;
    }

    if (hasTruthy(const <String>['cornerPlot', 'corner_plot', 'isCorner'])) {
      tags.add('Corner Plot');
    }
    if (hasTruthy(const <String>[
      'mainRoadFacing',
      'main_road_facing',
      'isMainRoadFacing'
    ])) {
      tags.add('Main Road Facing');
    }

    final facing =
        (meta['facing'] ?? meta['plotFacing'] ?? meta['direction'])?.trim();
    if (facing != null && facing.isNotEmpty) {
      tags.add('Facing $facing');
    }

    final otherInfo = (meta['otherInformation'] ??
            meta['other_info'] ??
            meta['other_information'])
        ?.trim();
    if (otherInfo != null && otherInfo.isNotEmpty) {
      for (final part in otherInfo.split(',')) {
        final t = part.trim();
        if (t.isEmpty) continue;
        if (!tags.contains(t)) {
          tags.add(t);
        }
      }
    }

    return tags;
  }

  Future<Set<Marker>> _buildPropertyMarkers({
    required MapViewportResponse response,
    required double zoom,
    required double pixelRatio,
  }) async {
    final nextMarkers = <Marker>{};

    for (final feature in response.properties) {
      final center = feature.centerPoint;
      if (center == null) continue;

      final rawName = feature.name.trim();
      final title = rawName.isEmpty
          ? (feature.propertyType.trim().isEmpty
              ? 'Property'
              : feature.propertyType)
          : rawName;

      final isLayout = feature.propertyType.trim() == 'Layout';

      final rawPrice = _getMetadataValue(
        feature.metadata,
        const <String>['price', 'listingPrice', 'salePrice', 'amount'],
      );
      final isPriceEligible = const <String>[
        'IndependentHouse',
        'CommercialSpace',
        'Land',
        'ApartmentFlat',
        'IndividualPlots',
      ].contains(feature.propertyType.trim());

      final priceBadgeLabel = (isPriceEligible && rawPrice != null)
          ? _formatPriceBadgeLabel(rawPrice)
          : null;

      LatLng? focusCenter;
      double? focusZoom;
      if (priceBadgeLabel != null || isLayout) {
        final polygons = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
        final points = polygons.firstWhere(
          (p) => p.length >= 3,
          orElse: () => const <LatLng>[],
        );
        if (points.isNotEmpty) {
          focusCenter = _centerOfBounds(_boundsFromPoints(points));
        }
        focusCenter ??= center;
        focusZoom = isLayout
            ? _layoutFocusZoomTarget
            : _priceBadgeFocusZoomTarget(feature.propertyType);
      }

      final shouldShowLayoutBadge = isLayout && zoom <= _layoutBadgeMaxZoom;
      final layoutLocation = shouldShowLayoutBadge
          ? _getMetadataValue(
              feature.metadata,
              const <String>[
                'location',
                'locality',
                'city',
                'area',
              ],
            )
          : null;

      BitmapDescriptor? icon;
      Offset? anchor;
      double zIndex = 80;

      if (shouldShowLayoutBadge) {
        icon = await _iconFactory.getLayoutBadgeIcon(
          title: title.isEmpty ? 'Layout' : title,
          subtitle: layoutLocation,
          zoom: zoom,
          pixelRatio: pixelRatio,
        );
        anchor = const Offset(0.5, 1.0);
        zIndex = 999999;
      } else if (isLayout) {
        icon = await _iconFactory.getLayoutMarkerDotIcon(
          zoom: zoom,
          pixelRatio: pixelRatio,
        );
        // Circular marker: anchor at center.
        anchor = const Offset(0.5, 0.5);
        zIndex = 140;
      } else if (priceBadgeLabel != null) {
        final colors = _priceBadgeColorsForPropertyType(feature.propertyType);
        icon = await _iconFactory.getPriceBadgeIcon(
          label: priceBadgeLabel,
          zoom: zoom,
          pixelRatio: pixelRatio,
          background: colors.background,
          stroke: colors.stroke,
          text: colors.text,
        );
        anchor = const Offset(0.5, 1.0);
        zIndex = 200;
      }

      nextMarkers.add(
        Marker(
          markerId: MarkerId('property:${feature.propertyId}'),
          position: center,
          icon: icon ?? BitmapDescriptor.defaultMarker,
          anchor: anchor ?? const Offset(0.5, 1.0),
          zIndex: zIndex,
          onTap: feature.propertyType.trim() == 'IndependentHouse'
              ? () => _handleIndependentHouseTapped(
                    feature,
                    target: focusCenter ?? center,
                    zoom: focusZoom ?? 20.0,
                  )
              : (!isLayout && priceBadgeLabel == null)
                  ? null
                  : () => _focusPropertyOnMap(
                        target: focusCenter ?? center,
                        zoom: focusZoom ??
                            (isLayout ? _layoutFocusZoomTarget : 20.0),
                      ),
          // Disable default Google Maps tooltip/infowindow (web UX doesn't show it).
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    return Set<Marker>.unmodifiable(nextMarkers);
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points) {
      final lat = p.latitude;
      final lng = p.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  LatLng _centerOfBounds(LatLngBounds bounds) {
    return LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }

  Future<void> _focusPropertyOnMap({
    required LatLng target,
    required double zoom,
  }) async {
    final controller = _mapController;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

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

  String _buildViewportSignature(LatLngBounds bounds, double zoom,
      List<String> propertyTypes, bool isAuthenticated,
      {String? clientFilters}) {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final filterSignature = propertyTypes
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return [
      minLat.toStringAsFixed(5),
      maxLat.toStringAsFixed(5),
      minLng.toStringAsFixed(5),
      maxLng.toStringAsFixed(5),
      zoom.toStringAsFixed(2),
      filterSignature.join(','),
      (clientFilters ?? '').trim(),
      isAuthenticated ? 'auth' : 'anon',
    ].join('|');
  }

  void _toggleSatelliteMode() {
    setState(() {
      _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    });
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double multiplier) {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();

    final expandedLatHalf = (latSpan == 0 ? 0.01 : latSpan) * multiplier / 2;
    final expandedLngHalf = (lngSpan == 0 ? 0.01 : lngSpan) * multiplier / 2;

    double clampLat(double v) => v.clamp(-90.0, 90.0).toDouble();
    double clampLng(double v) {
      var x = v;
      while (x > 180) {
        x -= 360;
      }
      while (x < -180) {
        x += 360;
      }
      return x;
    }

    final sw = LatLng(
      clampLat(centerLat - expandedLatHalf),
      clampLng(centerLng - expandedLngHalf),
    );
    final ne = LatLng(
      clampLat(centerLat + expandedLatHalf),
      clampLng(centerLng + expandedLngHalf),
    );

    final south = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final north = sw.latitude > ne.latitude ? sw.latitude : ne.latitude;
    final west = sw.longitude < ne.longitude ? sw.longitude : ne.longitude;
    final east = sw.longitude > ne.longitude ? sw.longitude : ne.longitude;

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlot = _selectedPlot;
    final markers = <Marker>{
      ..._viewportMarkers,
      ..._plotLabelMarkers,
      ..._roadLabelMarkers,
      ..._amenityLabelMarkers,
    };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            onTap: (_) => _closeAnyPanel(),
            onCameraMove: (position) {
              _lastCameraPosition = position;
              if (_effectiveZoom == null ||
                  (position.zoom - _effectiveZoom!).abs() >=
                      _styleZoomMinDelta) {
                _effectiveZoom = position.zoom;
              }
              _zoomNotifier.value = position.zoom;

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
            onCameraIdle: _onCameraIdle,
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
            markers: markers,
            polygons: {
              ..._layoutPolygons,
              ..._propertyPolygons,
              ..._plotPolygons,
              ..._selectedPlotHighlightPolygons,
              ..._amenityPolygons,
              ..._roadPolygons,
            },
            polylines: _roadPolylines,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
          ),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NetworkStatusBanner(isOffline: _isOffline),
                if (_isOffline) const SizedBox(height: 8),
                _googlePlace == null
                    ? const ApiKeyMissingBanner()
                    : SearchOverlay(
                        googlePlace: _googlePlace!,
                        onPlaceSelected: _moveCameraTo,
                        onSearchTap: _closeAnyPanel,
                        onFilterTap: _openFilters,
                        hasActiveFilters: _selectedPropertyType != null ||
                            _selectedPriceRange != null,
                      ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'satellite-toggle',
              onPressed: _toggleSatelliteMode,
              tooltip: _mapType == MapType.hybrid
                  ? 'Switch to map view'
                  : 'Switch to satellite view',
              child: Icon(
                _mapType == MapType.hybrid
                    ? Icons.map_outlined
                    : Icons.satellite_alt_outlined,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: ValueListenableBuilder<double>(
              valueListenable: _zoomNotifier,
              builder: (context, zoom, _) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      'Zoom: ${zoom.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isViewportLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Loading…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (selectedPlot != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlotDetailsPanel(
                plot: selectedPlot,
                isSold:
                    selectedPlot.layoutId != null && _isSoldPlot(selectedPlot),
                areaLabel: _plotAreaLabel(selectedPlot),
                tags: _plotTags(selectedPlot),
                onClose: _closePlotPanel,
                contactNumbers: _layoutContactNumbersForPlot(selectedPlot),
                onLayoutDetails: () {
                  final layoutId = selectedPlot.layoutId;
                  if (layoutId == null || layoutId.trim().isEmpty) {
                    ToastMessage.show(context, 'Layout details not available');
                    return;
                  }
                  _dismissKeyboard();
                  final feature = _propertyByFeatureId[layoutId.trim()];
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LayoutDetailScreen(
                        layoutId: layoutId.trim(),
                        fallbackFeature: feature,
                      ),
                    ),
                  );
                },
                onUpdateStatus: () {
                  final isAuthenticated = AuthScope.of(context).isAuthenticated;
                  final layoutId = selectedPlot.layoutId?.trim();
                  final canEditStatus = isAuthenticated &&
                      layoutId != null &&
                      layoutId.isNotEmpty &&
                      _ownedLayoutIds.contains(layoutId);

                  if (!canEditStatus) {
                    return null;
                  }
                  return (status) => _updatePlotStatus(selectedPlot, status);
                }(),
              ),
            ),
          if (selectedPlot == null && _selectedProperty != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child:
                  _selectedProperty!.propertyType.trim() == 'IndependentHouse'
                      ? _buildIndependentHouseCarouselPanel()
                      : PropertyDetailsPanel(
                          feature: _selectedProperty!,
                          imageUrls: _selectedPropertyMediaUrls,
                          isLoadingImages: _isSelectedPropertyMediaLoading,
                          imagesError: _selectedPropertyMediaError,
                          onOpenDetails: () =>
                              _openPropertyDetails(_selectedProperty!),
                          onClose: _closePropertyPanel,
                        ),
            ),
        ],
      ),
    );
  }
}
