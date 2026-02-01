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
import '../models/my_property_list_item.dart';
import '../models/nearby_property_card.dart';
import '../models/property_detail.dart';
import 'layout_detail_screen.dart';
import 'property_detail_screen.dart';
import '../utils/route_observer.dart';

part 'home_map_screen.helpers.dart';
part 'home_map/home_map_filters.dart';
part 'home_map/home_map_filters_types.dart';
part 'home_map/home_map_filters_widgets.dart';
part 'home_map/home_map_viewport.dart';
part 'home_map/home_map_viewport_cache.dart';
part 'home_map/home_map_polygon_styles.dart';
part 'home_map/home_map_property_media.dart';
part 'home_map/home_map_carousel.dart';
part 'home_map/home_map_controls.dart';
part 'home_map/home_map_selection.dart';
part 'home_map/home_map_labels.dart';
part 'home_map/home_map_nearby_layouts.dart';

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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // Camera restore behavior for property selection:
  // If a property tap zooms the map + opens the bottom panel, and the user does
  // not manually move/zoom the map afterwards, closing the panel restores the
  // previous camera position.
  CameraPosition? _cameraBeforePropertyFocus;
  bool _userMovedCameraSincePropertyFocus = false;
  bool _isProgrammaticCameraMove = false;

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
  String? _selectedListingType = 'Sell'; // default => Buy
  _PriceRangeFilter? _selectedPriceRange; // null => Any
  String? _selectedLandType; // null => Any
  String? _selectedCommercialSuitableFor; // null => All Types
  _AreaRangeFilter? _selectedAreaRange; // null => Any

  int? _selectedMinBedrooms; // null => Any
  bool? _selectedCarParking; // null => Any (true => Available)
  int? _selectedMinFloors; // null => Any
  String? _selectedBuildingAge; // null => Any

  int? _selectedApartmentMinBedrooms; // null => Any
  bool? _selectedApartmentCarParking; // null => Any (true => Available)
  String? _selectedApartmentFloor; // null => Any
  String? _selectedApartmentTotalFloors; // null => Any
  String? _selectedApartmentBuildingAge; // null => Any

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
  Set<Polygon> _selectedPropertyHighlightPolygons = <Polygon>{};
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
  // Houses used ONLY for the bottom rotating panel (can be larger than viewport).
  List<MapPropertyFeature> _independentHousesCarousel =
      const <MapPropertyFeature>[];
  int _activeIndependentHouseIndex = 0;
  PageController? _independentHouseCarouselController;
  Timer? _independentHouseCarouselDebounce;
  int _independentHouseCarouselRequestSeq = 0;
  DateTime? _independentHouseCarouselRefreshSuppressedUntil;
  bool _suppressCarouselFocusOnce = false;

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

  int _markerStyleSeq = 0;

  List<NearbyPropertyCard>? _nearbyLayouts;
  bool _isNearbyLayoutsLoading = false;
  String? _nearbyLayoutsError;

  bool _isNearbyLayoutsDialogOpen = false;
  BuildContext? _nearbyLayoutsDialogContext;
  bool _isNearbyLayoutsReopenHintOn = false;
  Timer? _nearbyLayoutsReopenHintTimer;

  static const Duration _nearbyNewThreshold = Duration(days: 7);

  Future<void> _refreshMarkerSelectionStyles() async {
    if (!mounted) return;

    final features = _propertyByFeatureId.values.toList(growable: false);
    if (features.isEmpty) return;

    final requestId = ++_markerStyleSeq;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;

    final markers = await _buildPropertyMarkers(
      response: MapViewportResponse(
        detailLevel: MapDetailLevel.minimal,
        properties: features,
        plots: const <MapPlotFeature>[],
        roads: const <MapRoadFeature>[],
        amenities: const <MapAmenityFeature>[],
      ),
      zoom: _lastCameraPosition.zoom,
      pixelRatio: pixelRatio,
    );

    if (!mounted || requestId != _markerStyleSeq) return;
    _updateState(() {
      _viewportMarkers = markers;
    });
  }

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
    _independentHouseCarouselDebounce?.cancel();
    _connectivitySubscription?.cancel();
    _zoomNotifier.dispose();
    _nearbyLayoutsReopenHintTimer?.cancel();
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

      final selected = _selectedProperty;
      final isSelected = selected != null &&
          selected.propertyType.trim() == feature.propertyType.trim() &&
          selected.featureId.trim() == feature.featureId.trim();

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

      if (!isLayout && focusZoom == null) {
        focusCenter = center;
        focusZoom = _priceBadgeFocusZoomTarget(feature.propertyType);
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
          emphasize: isSelected,
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
              : isLayout
                  ? () => _focusPropertyOnMap(
                        target: focusCenter ?? center,
                        zoom: focusZoom ?? _layoutFocusZoomTarget,
                      )
                  : () => unawaited(
                        _handlePropertyTapped(
                          feature,
                          target: focusCenter ?? center,
                          zoom: focusZoom ?? 20.0,
                        ),
                      ),
          // Disable default Google Maps tooltip/infowindow (web UX doesn't show it).
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    return Set<Marker>.unmodifiable(nextMarkers);
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
            onCameraMoveStarted: _onCameraMoveStarted,
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
              ..._selectedPropertyHighlightPolygons,
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
            zoomControlsEnabled: false,
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
                        onMyPropertySelected: _onMyPropertySelected,
                        onMyPropertyDeleted: _onMyPropertyDeleted,
                        onMyPropertiesOpened: _closeAnyPanel,
                        getMapCenter: () => _lastCameraPosition.target,
                        onSearchTap: _closeAnyPanel,
                        onFilterTap: (panelRect, arrowRect) =>
                            unawaited(_openFilters(panelRect, arrowRect)),
                        hasActiveFilters: _selectedPropertyType != null ||
                            _selectedListingType != null ||
                            _selectedPriceRange != null ||
                            _selectedLandType != null,
                      ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: _mapControlButton(
              icon: _mapType == MapType.hybrid
                  ? Icons.map_outlined
                  : Icons.satellite_alt_outlined,
              tooltip: _mapType == MapType.hybrid
                  ? 'Switch to map view'
                  : 'Switch to satellite view',
              onPressed: _toggleSatelliteMode,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _mapControlButton(
                  icon: Icons.list_alt_outlined,
                  tooltip: 'Layouts near Aruppukkottai',
                  highlight: _isNearbyLayoutsReopenHintOn,
                  onPressed: () {
                    _nearbyLayoutsReopenHintTimer?.cancel();
                    _nearbyLayoutsReopenHintTimer = null;
                    _updateState(() {
                      _isNearbyLayoutsReopenHintOn = false;
                    });

                    final anchor = _lastCameraPosition.target;
                    unawaited(_openNearbyLayoutsPopup(anchor: anchor));
                  },
                ),
                const SizedBox(height: 10),
                _mapZoomControl(),
              ],
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
