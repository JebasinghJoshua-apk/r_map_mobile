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
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/network_status_banner.dart';
import '../widgets/search_overlay.dart';
import '../widgets/toast_message.dart';
import '../models/map_viewport_models.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  GoogleMapController? _mapController;
  GooglePlace? _googlePlace;
  late final MobileBffMapApi _mapApi;

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
  static const int _viewportCacheMaxEntries = 24;
  static const Duration _viewportCacheTtl = Duration(seconds: 30);

  CameraPosition _lastCameraPosition = _initialCameraPosition;
  double? _effectiveZoom;
  Timer? _viewportDebounceTimer;
  int _viewportRequestSeq = 0;
  String? _lastViewportSignature;
  DateTime? _lastViewportErrorAt;

  static const double _styleZoomMinDelta = 0.25;
  static const double _overlayRetentionMultiplier = 1.75;

  static const double _hybridZoomEnter = 17.5;
  static const double _hybridZoomExit = 17.5;

  static const String _lightMapStyleAssetPath = 'assets/map_light.json';

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(37.4221, -122.0841),
    zoom: 14,
  );

  Set<Marker> _viewportMarkers = <Marker>{};

  Set<Marker> _plotLabelMarkers = <Marker>{};
  Set<Marker> _roadLabelMarkers = <Marker>{};
  Set<Marker> _amenityLabelMarkers = <Marker>{};

  Set<Polygon> _layoutPolygons = <Polygon>{};
  Set<Polygon> _propertyPolygons = <Polygon>{};
  Set<Polygon> _plotPolygons = <Polygon>{};
  Set<Polygon> _amenityPolygons = <Polygon>{};
  Set<Polygon> _roadPolygons = <Polygon>{};
  Set<Polyline> _roadPolylines = <Polyline>{};

  static const double _minPlotPolygonZoom = 16.2;
  static const double _minRoadOverlayZoom = 16.0;

  // Keep label behavior aligned with the web app.
  // Source: r-map-ui/src/components/Map/MapViewportLayer/constants.ts
  static const double _minPlotLabelZoom = 17.5;
  static const double _minRoadLabelZoom = 17.0;
  static const double _minAmenityLabelZoom = 17.0;

  static const int _maxLabelMarkers = 550;

  static const int _labelIconCacheMaxEntries = 5000;
  final LinkedHashMap<String, BitmapDescriptor> _labelIconCache =
      LinkedHashMap<String, BitmapDescriptor>();

  static const int _badgeIconCacheMaxEntries = 2500;
  final LinkedHashMap<String, BitmapDescriptor> _badgeIconCache =
      LinkedHashMap<String, BitmapDescriptor>();

  // Keep badge marker styling aligned with the web app.
  // Source of truth: r-map-ui/src/components/Map/utils/markerIcons.ts
  static const double _layoutBadgeMaxZoom = 17.0;

  static const Color _priceBadgeDefaultBackground = Color(0xFF0F766E);
  static const Color _priceBadgeDefaultStroke = Color(0xFFFFFFFF);
  static const Color _priceBadgeDefaultText = Color(0xFFF8FAFC);

  static const Color _priceBadgeCommercialBackground = Color(0xFF6B21A8);
  static const Color _priceBadgeCommercialStroke = Color(0xFFE9D5FF);
  static const Color _priceBadgeCommercialText = Color(0xFFFDF4FF);

  static const Color _priceBadgeLandBackground = Color(0xFF3F6212);
  static const Color _priceBadgeLandStroke = Color(0xFFD9F99D);
  static const Color _priceBadgeLandText = Color(0xFFF7FEE7);

  static const Color _priceBadgeApartmentBackground = Color(0xFF155E75);
  static const Color _priceBadgeApartmentStroke = Color(0xFFBAE6FD);
  static const Color _priceBadgeApartmentText = Color(0xFFECFEFF);

  static const Color _priceBadgePlotBackground = Color(0xFF22543D);
  static const Color _priceBadgePlotStroke = Color(0xFFBAE6FD);
  static const Color _priceBadgePlotText = Color(0xFFF8FAFC);

  static const Color _layoutBadgeBackground = Color(0xFF3730A3);
  static const Color _layoutBadgeStroke = Color(0xFFEEF2FF);
  static const Color _layoutBadgeTitle = Color(0xFFF8FAFC);
  static const Color _layoutBadgeSubtitle = Color(0xFFC7D2FE);

  static const Color _badgeShadowColor = Color(0x590F172A);

  // Keep map overlay styling aligned with the web app.
  // Source of truth: r-map-ui/src/constants/drawingStyles.ts
  // and r-map-ui/src/components/Map/utils/overlayStyles.ts
  static const double _layoutFillHideZoom = 17.0;

  static const Color _layoutBoundaryStroke = Color(0xFF1D4ED8);
  static const Color _layoutBoundaryFill = Color(0xFF2563EB);
  static const double _layoutBoundaryStrokeOpacity = 1.0;
  static const double _layoutBoundaryFillOpacity = 0.12;
  static const int _layoutBoundaryStrokeWidth = 2;

  static const Color _plotStroke = Color(0xFF0F766E);
  static const Color _plotFill = Color(0xFF16A34A);
  static const double _plotStrokeOpacity = 1.0;
  static const double _plotFillOpacity = 0.55;
  static const int _plotStrokeWidth = 2;

  static const Color _soldPlotStroke = Color(0xFF4B5563);
  static const Color _soldPlotFill = Color(0xFFDC2626);
  static const double _soldPlotStrokeOpacity = 0.70;
  static const double _soldPlotFillOpacity = 0.55;

  static const Color _amenityStroke = Color(0xFF0F766E);
  static const Color _amenityFill = Color(0xFF65A30D);
  static const double _amenityStrokeOpacity = 0.95;
  static const double _amenityFillOpacity = 0.30;
  static const int _amenityStrokeWidth = 1;

  static const Color _roadStroke = Color(0xFF374151);
  static const Color _roadFill = Color(0xFF2B3139);
  static const double _roadStrokeOpacity = 0.95;
  static const double _roadFillOpacity = 0.80;
  static const int _roadStrokeWidth = 2;

  static const Color _roadLineStroke = Color(0xFF4B5563);
  static const double _roadLineStrokeOpacity = 0.70;
  static const int _roadLineStrokeWidth = 2;

  // Property polygon styles (non-layout). Keep aligned with web.
  // Source of truth: r-map-ui/src/components/Map/utils/overlayStyles.ts
  static const Color _propertyDefaultStroke = Color(0xFF005F5A);
  static const Color _propertyDefaultFill = Color(0xFF60A5FA);

  static const Color _propertyIndividualPlotsStroke = Color(0xFF166534);
  static const Color _propertyIndividualPlotsFill = Color(0xFF48BB78);

  static const Color _propertyLandStroke = Color(0xFF4D7C0F);
  static const Color _propertyLandFill = Color(0xFF84CC16);

  static const Color _propertyCommercialStroke = Color(0xFF7C3AED);
  static const Color _propertyCommercialFill = Color(0xFFA855F7);

  static const Color _propertyIndependentHouseStroke = Color(0xFF115E59);
  static const Color _propertyIndependentHouseFill = Color(0xFF5EEAD4);

  static const Color _propertyApartmentStroke = Color(0xFF0E7490);
  static const Color _propertyApartmentFill = Color(0xFF22D3EE);

  static const double _propertyStrokeOpacity = 0.9;
  static const double _propertyBaseFillOpacity = 0.18;
  static const int _propertyBaseStrokeWidth = 2;

  static double _adjustFillOpacityForZoom(double zoom, double base) {
    if (zoom >= 18) return math.min(base + 0.22, 0.6);
    if (zoom >= 16) return math.min(base + 0.16, 0.5);
    if (zoom >= 14) return math.min(base + 0.10, 0.42);
    if (zoom >= 12) return math.min(base + 0.05, 0.35);
    return base;
  }

  static int _adjustStrokeWidthForZoom(double zoom, int base) {
    double value;
    if (zoom >= 18) {
      value = base + 2.2;
    } else if (zoom >= 16) {
      value = base + 1.6;
    } else if (zoom >= 14) {
      value = base + 0.8;
    } else if (zoom >= 12) {
      value = base + 0.3;
    } else {
      value = base.toDouble();
    }
    final rounded = value.round();
    return rounded < 1 ? 1 : rounded;
  }

  static _PropertyPolygonStyle _propertyStyleForType(String propertyType) {
    switch (propertyType.trim()) {
      case 'IndividualPlots':
        return const _PropertyPolygonStyle(
          stroke: _propertyIndividualPlotsStroke,
          fill: _propertyIndividualPlotsFill,
          zIndex: 50,
        );
      case 'Land':
        return const _PropertyPolygonStyle(
          stroke: _propertyLandStroke,
          fill: _propertyLandFill,
          zIndex: 30,
        );
      case 'CommercialSpace':
        return const _PropertyPolygonStyle(
          stroke: _propertyCommercialStroke,
          fill: _propertyCommercialFill,
          zIndex: 55,
        );
      case 'IndependentHouse':
        return const _PropertyPolygonStyle(
          stroke: _propertyIndependentHouseStroke,
          fill: _propertyIndependentHouseFill,
          zIndex: 35,
        );
      case 'ApartmentFlat':
        return const _PropertyPolygonStyle(
          stroke: _propertyApartmentStroke,
          fill: _propertyApartmentFill,
          zIndex: 35,
        );
      case 'Layout':
        return const _PropertyPolygonStyle(
          stroke: _layoutBoundaryStroke,
          fill: _layoutBoundaryFill,
          zIndex: 40,
        );
      case 'Road':
      case 'LayoutRoad':
        return const _PropertyPolygonStyle(
          stroke: _roadStroke,
          fill: _roadFill,
          zIndex: 38,
        );
      default:
        return const _PropertyPolygonStyle(
          stroke: _propertyDefaultStroke,
          fill: _propertyDefaultFill,
          zIndex: 25,
        );
    }
  }

  static bool _isSoldPlot(MapPlotFeature plot) {
    final meta = plot.metadata;
    final rawStatus = (meta['plotStatus'] ??
            meta['plot_status'] ??
            meta['status'] ??
            meta['availability'])
        ?.trim()
        .toLowerCase();
    if (rawStatus == '2' || rawStatus == 'sold') return true;

    final rawSold = (meta['sold'] ?? meta['isSold'] ?? meta['is_sold'])
        ?.trim()
        .toLowerCase();
    return rawSold == 'true' || rawSold == '1' || rawSold == 'yes';
  }

  static String _plotElementKind(MapPlotFeature plot) {
    final meta = plot.metadata;
    final candidates = <String?>[
      meta['elementType'],
      meta['element_type'],
      meta['type'],
      meta['category'],
      meta['kind'],
    ]
        .map((v) => v?.trim().toLowerCase())
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toList(growable: false);

    final isRoad = candidates.any((v) => v.contains('road')) ||
        (meta['roadName']?.trim().isNotEmpty ?? false);
    if (isRoad) return 'road';
    if (candidates.any((v) => v.contains('boundary'))) return 'boundary';
    return 'plot';
  }

  @override
  void initState() {
    super.initState();
    _mapApi = MobileBffMapApi();
    _initConnectivity();
    _loadLightMapStyle();
    if (googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(googlePlacesApiKey);
    }
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
    _mapController?.dispose();
    _viewportDebounceTimer?.cancel();
    _viewportLoadingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _zoomNotifier.dispose();
    super.dispose();
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

  void _setViewportLoading(bool value) {
    if (!mounted) return;

    // Small delay avoids spinner flicker on fast cache hits.
    if (value) {
      _viewportLoadingTimer?.cancel();
      _viewportLoadingTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() => _isViewportLoading = true);
      });
      return;
    }

    _viewportLoadingTimer?.cancel();
    if (_isViewportLoading) {
      setState(() => _isViewportLoading = false);
    }
  }

  _ViewportRenderCacheEntry? _tryGetCachedViewport(String signature) {
    final entry = _viewportCache.remove(signature);
    if (entry == null) return null;
    final isFresh =
        DateTime.now().difference(entry.createdAt) <= _viewportCacheTtl;
    if (!isFresh) {
      return null;
    }

    // Reinsert to mark as most recently used.
    _viewportCache[signature] = entry;
    return entry;
  }

  void _putCachedViewport(String signature, _ViewportRenderCacheEntry entry) {
    _viewportCache.remove(signature);
    _viewportCache[signature] = entry;

    while (_viewportCache.length > _viewportCacheMaxEntries) {
      _viewportCache.remove(_viewportCache.keys.first);
    }
  }

  Future<void> _fetchViewport() async {
    final controller = _mapController;
    if (controller == null) return;

    final token = AuthScope.of(context).session?.token;

    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    const propertyTypes = <String>[];

    final expandedBounds = _expandBounds(bounds, _overlayRetentionMultiplier);

    final signature =
        _buildViewportSignature(expandedBounds, zoom, propertyTypes);
    if (signature == _lastViewportSignature) {
      return;
    }
    _lastViewportSignature = signature;

    final cached = _tryGetCachedViewport(signature);
    if (cached != null) {
      setState(() {
        _viewportMarkers = cached.markers;
        _plotLabelMarkers = cached.plotLabelMarkers;
        _roadLabelMarkers = cached.roadLabelMarkers;
        _amenityLabelMarkers = cached.amenityLabelMarkers;
        _layoutPolygons = cached.layoutPolygons;
        _propertyPolygons = cached.propertyPolygons;
        _plotPolygons = cached.plotPolygons;
        _amenityPolygons = cached.amenityPolygons;
        _roadPolygons = cached.roadPolygons;
        _roadPolylines = cached.roadPolylines;
      });
      return;
    }

    final requestId = ++_viewportRequestSeq;

    _setViewportLoading(true);

    try {
      final response = await _mapApi.getViewport(
        bounds: expandedBounds,
        zoom: zoom,
        propertyTypes: propertyTypes,
        bearerToken: token,
      );

      if (!mounted || requestId != _viewportRequestSeq) {
        _setViewportLoading(false);
        return;
      }

      final rendered = _renderViewport(
        response: response,
        zoom: _lastCameraPosition.zoom,
      );

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final propertyMarkers = await _buildPropertyMarkers(
        response: response,
        zoom: _lastCameraPosition.zoom,
        pixelRatio: pixelRatio,
      );
      final labels = await _buildLabelMarkers(
        response: response,
        zoom: _lastCameraPosition.zoom,
      );

      if (!mounted || requestId != _viewportRequestSeq) {
        _setViewportLoading(false);
        return;
      }

      final merged = rendered.copyWith(
        markers: propertyMarkers,
        plotLabelMarkers: labels.plotLabelMarkers,
        roadLabelMarkers: labels.roadLabelMarkers,
        amenityLabelMarkers: labels.amenityLabelMarkers,
      );
      _putCachedViewport(signature, merged);

      setState(() {
        _viewportMarkers = merged.markers;
        _plotLabelMarkers = merged.plotLabelMarkers;
        _roadLabelMarkers = merged.roadLabelMarkers;
        _amenityLabelMarkers = merged.amenityLabelMarkers;
        _layoutPolygons = merged.layoutPolygons;
        _propertyPolygons = merged.propertyPolygons;
        _plotPolygons = merged.plotPolygons;
        _amenityPolygons = merged.amenityPolygons;
        _roadPolygons = merged.roadPolygons;
        _roadPolylines = merged.roadPolylines;
      });
      _setViewportLoading(false);
    } catch (e) {
      if (!mounted || requestId != _viewportRequestSeq) {
        _setViewportLoading(false);
        return;
      }

      _setViewportLoading(false);
      final now = DateTime.now();
      final lastError = _lastViewportErrorAt;
      if (lastError == null || now.difference(lastError).inSeconds >= 8) {
        _lastViewportErrorAt = now;
        ToastMessage.show(context, e.toString());
      }
    }
  }

  _ViewportRenderCacheEntry _renderViewport({
    required MapViewportResponse response,
    required double zoom,
  }) {
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

        if (kind == 'road') {
          stroke = _roadStroke;
          fill = _roadFill;
          strokeWidth = _roadStrokeWidth;
          strokeOpacity = _roadStrokeOpacity;
          fillOpacity = _roadFillOpacity;
        } else if (kind == 'boundary') {
          stroke = _layoutBoundaryStroke;
          fill = _layoutBoundaryFill;
          strokeWidth = _layoutBoundaryStrokeWidth;
          strokeOpacity = _layoutBoundaryStrokeOpacity;
          fillOpacity =
              zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
        } else if (isSold) {
          stroke = _soldPlotStroke;
          fill = _soldPlotFill;
          strokeWidth = _plotStrokeWidth;
          strokeOpacity = _soldPlotStrokeOpacity;
          fillOpacity = _soldPlotFillOpacity;
        } else {
          stroke = _plotStroke;
          fill = _plotFill;
          strokeWidth = _plotStrokeWidth;
          strokeOpacity = _plotStrokeOpacity;
          fillOpacity = _plotFillOpacity;
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
              consumeTapEvents: false,
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
    );
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
        icon = await _getLayoutBadgeIcon(
          title: title.isEmpty ? 'Layout' : title,
          subtitle: layoutLocation,
          zoom: zoom,
          pixelRatio: pixelRatio,
        );
        anchor = const Offset(0.5, 1.0);
        zIndex = 999999;
      } else if (priceBadgeLabel != null) {
        final colors = _priceBadgeColorsForPropertyType(feature.propertyType);
        icon = await _getPriceBadgeIcon(
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
          onTap: (!isLayout && priceBadgeLabel == null)
              ? null
              : () => _focusPropertyOnMap(
                    target: focusCenter ?? center,
                    zoom:
                        focusZoom ?? (isLayout ? _layoutFocusZoomTarget : 20.0),
                  ),
          infoWindow: InfoWindow(
            title: title,
            snippet: feature.listingType,
          ),
        ),
      );
    }

    return Set<Marker>.unmodifiable(nextMarkers);
  }

  double _priceBadgeFocusZoomTarget(String propertyType) {
    // Keep aligned with web: r-map-ui/src/components/Map/MapViewportLayer/constants.ts
    switch (propertyType.trim()) {
      case 'Land':
        return 18.5;
      case 'IndependentHouse':
      case 'ApartmentFlat':
      case 'CommercialSpace':
      case 'IndividualPlots':
        return 20.0;
      default:
        return 20.0;
    }
  }

  // Keep aligned with web: LAYOUT_AUTO_FOCUS_ZOOM_TARGET in
  // r-map-ui/src/components/Map/MapViewportLayer/constants.ts
  static const double _layoutFocusZoomTarget = 18.5;

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

  _PriceBadgeColors _priceBadgeColorsForPropertyType(String propertyType) {
    switch (propertyType.trim()) {
      case 'CommercialSpace':
        return const _PriceBadgeColors(
          background: _priceBadgeCommercialBackground,
          stroke: _priceBadgeCommercialStroke,
          text: _priceBadgeCommercialText,
        );
      case 'Land':
        return const _PriceBadgeColors(
          background: _priceBadgeLandBackground,
          stroke: _priceBadgeLandStroke,
          text: _priceBadgeLandText,
        );
      case 'ApartmentFlat':
        return const _PriceBadgeColors(
          background: _priceBadgeApartmentBackground,
          stroke: _priceBadgeApartmentStroke,
          text: _priceBadgeApartmentText,
        );
      case 'IndividualPlots':
        return const _PriceBadgeColors(
          background: _priceBadgePlotBackground,
          stroke: _priceBadgePlotStroke,
          text: _priceBadgePlotText,
        );
      default:
        return const _PriceBadgeColors(
          background: _priceBadgeDefaultBackground,
          stroke: _priceBadgeDefaultStroke,
          text: _priceBadgeDefaultText,
        );
    }
  }

  String? _getMetadataValue(Map<String, String?> metadata, List<String> keys) {
    for (final key in keys) {
      final v = metadata[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static const double _rupeeCrore = 10000000;
  static const double _rupeeLakh = 100000;
  static const double _rupeeThousand = 1000;

  String? _formatPriceBadgeLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'([\d.,]+)(?:\s*([a-zA-Z]+))?').firstMatch(trimmed);
    if (match == null) return null;

    final numericText = match.group(1)?.replaceAll(',', '');
    final numericValue =
        numericText == null ? null : double.tryParse(numericText);
    if (numericValue == null || !numericValue.isFinite) return null;

    final suffix = (match.group(2) ?? '').toLowerCase();
    final lower = trimmed.toLowerCase();

    double multiplier = 1;
    const suffixMultipliers = <String, double>{
      'c': _rupeeCrore,
      'cr': _rupeeCrore,
      'crore': _rupeeCrore,
      'crores': _rupeeCrore,
      'l': _rupeeLakh,
      'lac': _rupeeLakh,
      'lacs': _rupeeLakh,
      'lakh': _rupeeLakh,
      'lakhs': _rupeeLakh,
      'k': _rupeeThousand,
      'thousand': _rupeeThousand,
    };

    if (suffix.isNotEmpty && suffixMultipliers.containsKey(suffix)) {
      multiplier = suffixMultipliers[suffix]!;
    } else {
      if (lower.contains('crore') || RegExp(r'\bcr\b').hasMatch(lower)) {
        multiplier = _rupeeCrore;
      } else if (lower.contains('lakh') ||
          lower.contains('lac') ||
          RegExp(r'\bl\b').hasMatch(lower)) {
        multiplier = _rupeeLakh;
      } else if (lower.contains('thousand') ||
          RegExp(r'\bk\b').hasMatch(lower)) {
        multiplier = _rupeeThousand;
      }
    }

    final amount = numericValue * multiplier;
    if (!amount.isFinite || amount <= 0) return null;

    String compact(double value) {
      if (value >= 10) return value.round().toString();
      final rounded = (value * 10).round() / 10;
      return (rounded % 1 == 0)
          ? rounded.toStringAsFixed(0)
          : rounded.toStringAsFixed(1);
    }

    if (amount >= _rupeeCrore) {
      return '₹${compact(amount / _rupeeCrore)}C';
    }
    if (amount >= _rupeeLakh) {
      return '₹${compact(amount / _rupeeLakh)}L';
    }
    if (amount >= _rupeeThousand) {
      return '₹${compact(amount / _rupeeThousand)}K';
    }
    return '₹${amount.round()}';
  }

  Future<BitmapDescriptor> _getPriceBadgeIcon({
    required String label,
    required double zoom,
    required double pixelRatio,
    required Color background,
    required Color stroke,
    required Color text,
  }) async {
    final fontSize = zoom >= 18.2
        ? 14.0
        : zoom >= 17.0
            ? 12.0
            : 10.0;
    final charWidth = fontSize * 0.52;
    final paddingX = math.max(8.0, fontSize * 0.6);
    final minWidth = (fontSize * 2.6).ceilToDouble();
    final badgeWidth =
        math.max(minWidth, label.length * charWidth + paddingX * 2);
    final paddingY = math.max(4.0, fontSize * 0.35);
    final badgeHeight = (fontSize + paddingY * 2);
    const pointerHeight = 6.0;
    final totalHeight = badgeHeight + pointerHeight;
    const radius = 6.0;
    final triangleHalfWidth = math.max(6.0, fontSize * 0.55);
    final borderWidth = math.max(0.9, fontSize * 0.1);

    final cacheKey = [
      'price',
      label,
      zoom.toStringAsFixed(2),
      pixelRatio.toStringAsFixed(2),
      background.value.toRadixString(16),
      stroke.value.toRadixString(16),
      text.value.toRadixString(16),
    ].join('|');

    final cached = _badgeIconCache.remove(cacheKey);
    if (cached != null) {
      _badgeIconCache[cacheKey] = cached;
      return cached;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    final bubblePath = ui.Path()
      ..moveTo(radius, 0)
      ..lineTo(badgeWidth - radius, 0)
      ..quadraticBezierTo(badgeWidth, 0, badgeWidth, radius)
      ..lineTo(badgeWidth, badgeHeight - radius)
      ..quadraticBezierTo(
          badgeWidth, badgeHeight, badgeWidth - radius, badgeHeight)
      ..lineTo(badgeWidth / 2 + triangleHalfWidth, badgeHeight)
      ..lineTo(badgeWidth / 2, totalHeight)
      ..lineTo(badgeWidth / 2 - triangleHalfWidth, badgeHeight)
      ..lineTo(radius, badgeHeight)
      ..quadraticBezierTo(0, badgeHeight, 0, badgeHeight - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();

    canvas.drawShadow(bubblePath, _badgeShadowColor, 4.0, true);

    final fillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = background;
    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = stroke;

    canvas.drawPath(bubblePath, fillPaint);
    canvas.drawPath(bubblePath, strokePaint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: text,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    )..layout(maxWidth: badgeWidth);

    final textX = (badgeWidth - textPainter.width) / 2;
    final textY = (badgeHeight - textPainter.height) / 2;
    textPainter.paint(canvas, ui.Offset(textX, textY));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (badgeWidth * pixelRatio).ceil(),
      (totalHeight * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: pixelRatio,
    );

    if (_badgeIconCache.length >= _badgeIconCacheMaxEntries) {
      _badgeIconCache.remove(_badgeIconCache.keys.first);
    }
    _badgeIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _getLayoutBadgeIcon({
    required String title,
    required String? subtitle,
    required double zoom,
    required double pixelRatio,
  }) async {
    final safeTitle = title.trim().isEmpty ? 'Layout' : title.trim();
    final safeSubtitle = (subtitle ?? '').trim();
    final hasSubtitle = safeSubtitle.isNotEmpty;

    final titleFontSize = zoom >= 18.5
        ? 15.0
        : zoom >= 17.5
            ? 14.0
            : 12.0;
    final subtitleFontSize = hasSubtitle
        ? math.max(11.0, (titleFontSize * 0.78).roundToDouble())
        : 0.0;
    final titleCharWidth = titleFontSize * 0.55;
    final subtitleCharWidth = subtitleFontSize * 0.52;
    final paddingX = math.max(12.0, titleFontSize * 0.7);
    final paddingY = math.max(8.0, titleFontSize * 0.45);
    final lineGap = hasSubtitle ? math.max(4.0, titleFontSize * 0.2) : 0.0;

    final textWidth = math.max(
      safeTitle.length * titleCharWidth,
      hasSubtitle ? safeSubtitle.length * subtitleCharWidth : 0.0,
    );
    final minWidth = (titleFontSize * 4.5).roundToDouble();
    final badgeWidth = math.max(minWidth, textWidth + paddingX * 2);
    final textHeight =
        titleFontSize + (hasSubtitle ? lineGap + subtitleFontSize : 0.0);
    final badgeHeight = paddingY * 2 + textHeight;
    const pointerHeight = 8.0;
    final totalHeight = badgeHeight + pointerHeight;
    const radius = 8.0;
    final triangleHalfWidth = math.max(8.0, badgeWidth * 0.12);
    const borderWidth = 1.2;

    final cacheKey = [
      'layout',
      safeTitle,
      safeSubtitle,
      zoom.toStringAsFixed(2),
      pixelRatio.toStringAsFixed(2),
    ].join('|');

    final cached = _badgeIconCache.remove(cacheKey);
    if (cached != null) {
      _badgeIconCache[cacheKey] = cached;
      return cached;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    final bubblePath = ui.Path()
      ..moveTo(radius, 0)
      ..lineTo(badgeWidth - radius, 0)
      ..quadraticBezierTo(badgeWidth, 0, badgeWidth, radius)
      ..lineTo(badgeWidth, badgeHeight - radius)
      ..quadraticBezierTo(
          badgeWidth, badgeHeight, badgeWidth - radius, badgeHeight)
      ..lineTo(badgeWidth / 2 + triangleHalfWidth, badgeHeight)
      ..lineTo(badgeWidth / 2, totalHeight)
      ..lineTo(badgeWidth / 2 - triangleHalfWidth, badgeHeight)
      ..lineTo(radius, badgeHeight)
      ..quadraticBezierTo(0, badgeHeight, 0, badgeHeight - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();

    canvas.drawShadow(bubblePath, _badgeShadowColor, 4.5, true);

    final fillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = _layoutBadgeBackground;
    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = _layoutBadgeStroke;

    canvas.drawPath(bubblePath, fillPaint);
    canvas.drawPath(bubblePath, strokePaint);

    final titlePainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: safeTitle,
        style: TextStyle(
          color: _layoutBadgeTitle,
          fontSize: titleFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    )..layout(maxWidth: badgeWidth);

    final titleX = (badgeWidth - titlePainter.width) / 2;
    final titleY = paddingY;
    titlePainter.paint(canvas, ui.Offset(titleX, titleY));

    if (hasSubtitle) {
      final subtitlePainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: TextSpan(
          text: safeSubtitle,
          style: TextStyle(
            color: _layoutBadgeSubtitle,
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      )..layout(maxWidth: badgeWidth);

      final subtitleX = (badgeWidth - subtitlePainter.width) / 2;
      final subtitleY = titleY + titleFontSize + lineGap;
      subtitlePainter.paint(canvas, ui.Offset(subtitleX, subtitleY));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (badgeWidth * pixelRatio).ceil(),
      (totalHeight * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: pixelRatio,
    );

    if (_badgeIconCache.length >= _badgeIconCacheMaxEntries) {
      _badgeIconCache.remove(_badgeIconCache.keys.first);
    }
    _badgeIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<_LabelMarkerResult> _buildLabelMarkers({
    required MapViewportResponse response,
    required double zoom,
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

    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final nextPlotLabels = <Marker>{};
    final nextRoadLabels = <Marker>{};
    final nextAmenityLabels = <Marker>{};
    var totalLabels = 0;

    if (shouldShowPlotLabels) {
      final plotFontSize = _plotLabelFontSize(zoom);
      for (final plot in response.plots) {
        if (totalLabels >= _maxLabelMarkers) break;
        final label = plot.plotNumber.trim();
        if (label.isEmpty) continue;
        final pos = plot.centerPoint;
        if (pos == null) continue;

        final icon = await _getTextLabelIcon(
          text: label,
          pixelRatio: pixelRatio,
          fontSize: plotFontSize,
          textColor: Colors.white,
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xD0000000),
              blurRadius: 3,
              offset: Offset(0, 0),
            ),
          ],
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
            consumeTapEvents: false,
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
          // Some backends may return road geometry as Polygon/MultiPolygon.
          final polygons = GeoJson.tryParsePolygons(road.roadGeoJson);
          if (polygons.isNotEmpty) {
            placement = _computeLineLabelPlacement(polygons.first);
          }
        }

        if (placement == null) continue;

        final icon = await _getTextLabelIcon(
          text: name,
          pixelRatio: pixelRatio,
          fontSize: roadFontSize,
          textColor: Colors.white,
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xD0000000),
              blurRadius: 3,
              offset: Offset(0, 0),
            ),
          ],
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

        final icon = await _getTextLabelIcon(
          text: label,
          pixelRatio: pixelRatio,
          fontSize: amenityFontSize,
          textColor: Colors.white,
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xD0000000),
              blurRadius: 3,
              offset: Offset(0, 0),
            ),
          ],
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

  Future<BitmapDescriptor> _getTextLabelIcon({
    required String text,
    required double pixelRatio,
    required double fontSize,
    required Color textColor,
    Color? backgroundColor,
    required EdgeInsets padding,
    required double borderRadius,
    List<Shadow>? shadows,
  }) async {
    final cacheKey = [
      text,
      fontSize.toStringAsFixed(1),
      textColor.value.toRadixString(16),
      backgroundColor?.value.toRadixString(16) ?? 'none',
      padding.horizontal.toStringAsFixed(1),
      padding.vertical.toStringAsFixed(1),
      borderRadius.toStringAsFixed(1),
      _shadowsSignature(shadows),
      pixelRatio.toStringAsFixed(2),
    ].join('|');

    final cached = _labelIconCache.remove(cacheKey);
    if (cached != null) {
      // LRU: move to the end.
      _labelIconCache[cacheKey] = cached;
      return cached;
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: shadows,
        ),
      ),
    )..layout();

    final width =
        (textPainter.width + padding.left + padding.right).ceil().toDouble();
    final height =
        (textPainter.height + padding.top + padding.bottom).ceil().toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    if (backgroundColor != null) {
      final rect = ui.Rect.fromLTWH(0, 0, width, height);
      final rrect = ui.RRect.fromRectAndRadius(
        rect,
        ui.Radius.circular(borderRadius),
      );
      final bgPaint = ui.Paint()..color = backgroundColor;
      canvas.drawRRect(rrect, bgPaint);
    }

    textPainter.paint(
      canvas,
      ui.Offset(padding.left, padding.top),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
        (width * pixelRatio).ceil(), (height * pixelRatio).ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: pixelRatio,
    );

    // Prevent unbounded growth.
    if (_labelIconCache.length >= _labelIconCacheMaxEntries) {
      _labelIconCache.remove(_labelIconCache.keys.first);
    }
    _labelIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  String _shadowsSignature(List<Shadow>? shadows) {
    if (shadows == null || shadows.isEmpty) return 'none';
    return shadows
        .map(
          (s) => [
            s.color.value.toRadixString(16),
            s.blurRadius.toStringAsFixed(2),
            s.offset.dx.toStringAsFixed(2),
            s.offset.dy.toStringAsFixed(2),
          ].join(','),
        )
        .join(';');
  }

  String _buildViewportSignature(
    LatLngBounds bounds,
    double zoom,
    List<String> propertyTypes,
  ) {
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
        ],
      ),
    );
  }
}

class _ViewportRenderCacheEntry {
  _ViewportRenderCacheEntry({
    required this.markers,
    required this.plotLabelMarkers,
    required this.roadLabelMarkers,
    required this.amenityLabelMarkers,
    required this.layoutPolygons,
    required this.propertyPolygons,
    required this.plotPolygons,
    required this.amenityPolygons,
    required this.roadPolygons,
    required this.roadPolylines,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final Set<Marker> markers;
  final Set<Marker> plotLabelMarkers;
  final Set<Marker> roadLabelMarkers;
  final Set<Marker> amenityLabelMarkers;
  final Set<Polygon> layoutPolygons;
  final Set<Polygon> propertyPolygons;
  final Set<Polygon> plotPolygons;
  final Set<Polygon> amenityPolygons;
  final Set<Polygon> roadPolygons;
  final Set<Polyline> roadPolylines;
  final DateTime createdAt;

  _ViewportRenderCacheEntry copyWith({
    Set<Marker>? markers,
    Set<Marker>? plotLabelMarkers,
    Set<Marker>? roadLabelMarkers,
    Set<Marker>? amenityLabelMarkers,
  }) {
    return _ViewportRenderCacheEntry(
      markers: markers ?? this.markers,
      plotLabelMarkers: plotLabelMarkers ?? this.plotLabelMarkers,
      roadLabelMarkers: roadLabelMarkers ?? this.roadLabelMarkers,
      amenityLabelMarkers: amenityLabelMarkers ?? this.amenityLabelMarkers,
      layoutPolygons: layoutPolygons,
      propertyPolygons: propertyPolygons,
      plotPolygons: plotPolygons,
      amenityPolygons: amenityPolygons,
      roadPolygons: roadPolygons,
      roadPolylines: roadPolylines,
      createdAt: createdAt,
    );
  }
}

class _PriceBadgeColors {
  const _PriceBadgeColors({
    required this.background,
    required this.stroke,
    required this.text,
  });

  final Color background;
  final Color stroke;
  final Color text;
}

class _PropertyPolygonStyle {
  const _PropertyPolygonStyle({
    required this.stroke,
    required this.fill,
    required this.zIndex,
  });

  final Color stroke;
  final Color fill;
  final int zIndex;
}

class _LabelMarkerResult {
  const _LabelMarkerResult({
    required this.plotLabelMarkers,
    required this.roadLabelMarkers,
    required this.amenityLabelMarkers,
  });

  final Set<Marker> plotLabelMarkers;
  final Set<Marker> roadLabelMarkers;
  final Set<Marker> amenityLabelMarkers;
}

class _LineLabelPlacement {
  const _LineLabelPlacement({
    required this.position,
    required this.rotationDegrees,
  });

  final LatLng position;
  final double rotationDegrees;
}
