import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../constants/api_constants.dart';
import '../constants/search_constants.dart';
import '../services/firebase_perf_service.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_plots_api.dart';
import '../services/performance_logger.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/network_status_banner.dart';
import '../widgets/plot_details_panel.dart';
import '../widgets/property_details_panel.dart';
import '../widgets/search_overlay.dart';
import '../widgets/toast_message.dart';
import '../services/mobile_bff_saved_properties_api.dart';
import '../services/ip_geolocation_service.dart';
import '../services/nearby_coachmark_service.dart';
import '../widgets/nearby_coachmark_widgets.dart';
import '../models/map_viewport_models.dart';
import '../models/my_property_list_item.dart';
import '../models/nearby_property_card.dart';
import '../models/property_detail.dart';
import '../models/saved_property.dart';
import 'layout_detail_screen.dart';
import 'property_detail_screen.dart';
import '../utils/route_observer.dart';
import '../utils/anchored_popover_geometry.dart';
import '../utils/pending_layout_focus.dart';
import '../utils/pending_map_focus.dart';
import '../utils/pending_plot_selection.dart';
import '../utils/pending_property_selection.dart';

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
  late final MobileBffSavedPropertiesApi _savedPropertiesApi;

  // IP-based geolocation state
  bool _hasMovedToIpLocation = false;
  LatLng? _pendingIpLocation;

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

  /// True when user manually toggles map type; prevents zoom-based auto-switching.
  bool _userSelectedMapType = false;
  final ValueNotifier<double> _zoomNotifier =
      ValueNotifier(_initialCameraPosition.zoom);

  bool _isViewportLoading = false;
  Timer? _viewportLoadingTimer;
  bool _hasViewportResult = false;
  bool _isViewportFetching = false;
  DateTime? _viewportFetchingStartedAt;
  Timer? _viewportFetchingHideTimer;

  bool _isEmptyStateDismissed = false;
  Timer? _emptyStateDismissTimer;
  bool _triggeredByPlaceSearch = false;

  bool _isSearchOverlayOpen = true;

  /// When false, a blurred overlay blocks map pan/zoom until the user selects a place.
  bool _hasSelectedPlace = false;

  final LinkedHashMap<String, _ViewportRenderCacheEntry> _viewportCache =
      LinkedHashMap<String, _ViewportRenderCacheEntry>();

  CameraPosition _lastCameraPosition = _initialCameraPosition;
  double? _effectiveZoom;
  Timer? _viewportDebounceTimer;
  int _viewportRequestSeq = 0;
  String? _lastViewportSignature;
  DateTime? _lastViewportErrorAt;

  String? _selectedPropertyType; // null => All properties
  static const String _defaultListingType = 'Sell';
  String? _selectedListingType = _defaultListingType;
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

  bool get _hasAppliedNonDefaultFilters {
    final listingIsActive = _selectedListingType != null &&
        _selectedListingType!.trim().isNotEmpty &&
        _selectedListingType != _defaultListingType;

    return _selectedPropertyType != null ||
        listingIsActive ||
        _selectedPriceRange != null ||
        _selectedLandType != null ||
        _selectedCommercialSuitableFor != null ||
        _selectedAreaRange != null ||
        _selectedMinBedrooms != null ||
        _selectedCarParking != null ||
        _selectedMinFloors != null ||
        _selectedBuildingAge != null ||
        _selectedApartmentMinBedrooms != null ||
        _selectedApartmentCarParking != null ||
        _selectedApartmentFloor != null ||
        _selectedApartmentTotalFloors != null ||
        _selectedApartmentBuildingAge != null;
  }

  String? _lastViewportAuthKey;

  Set<String> _savedPropertyIds = <String>{};
  final Set<String> _savingPropertyIds = <String>{};

  ModalRoute<void>? _routeSubscription;

  final GlobalKey<SearchOverlayState> _searchOverlayKey =
      GlobalKey<SearchOverlayState>();

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

  // Layout preview polygon (shown immediately when opening from nearby dialog
  // while full viewport data loads).
  Set<Polygon> _layoutPreviewPolygons = <Polygon>{};

  MapPlotFeature? _selectedPlot;
  int _plotFocusSeq = 0;

  /// Plot ID focused via deep link (highlight without panel until tapped).
  String? _focusedPlotIdFromDeepLink;

  /// Pending plot data for auto-selection from deep link.
  /// When set, the next viewport fetch will auto-select this plot.
  PlotFocusData? _pendingPlotAutoSelect;

  /// Timestamp when _pendingPlotAutoSelect was set.  Used to expire the
  /// pending after a reasonable window so we don't retry forever.
  DateTime? _pendingPlotAutoSelectAt;

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
  String? _nearbyLayoutsError;

  bool _isNearbyLayoutsDialogOpen = false;
  bool _isNearbyLayoutsReopenHintOn = false;
  Timer? _nearbyLayoutsReopenHintTimer;

  // Feature coachmark / pulse state
  bool _showFilterCoachmark = false;
  bool _showFilterPulse = false;
  bool _filterCoachmarkPending = false;

  bool _showNearbyCoachmark = false;
  bool _showNearbyPulse = false;
  bool _nearbyCoachmarkPending = false;
  bool _nearbyPulsePending = false;

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
    _savedPropertiesApi = MobileBffSavedPropertiesApi();
    _initConnectivity();
    _loadLightMapStyle();
    if (googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(googlePlacesApiKey);
    }
    // Fetch IP-based location in parallel (no blocking)
    _fetchIpLocation();
    // Initialise feature coachmarks (filter + nearby) pulse state.
    _initFeatureCoachmarks();
    // Signal that the navigator is ready for deep-link navigation.
    deepLinkService.markHomeReady();

    // Check for pending deep link selections after a short delay.
    // This handles cold-start deep links where didPopNext() isn't triggered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _checkPendingDeepLinkSelections();
      });
    });
  }

  /// Check for any pending deep link selections (property or plot).
  /// Called after init to handle cold-start deep links.
  void _checkPendingDeepLinkSelections() {
    // Handle property selection from deep link.
    final pendingSelection = PendingPropertySelection.take();
    if (pendingSelection != null) {
      unawaited(_selectPropertyFromDeepLink(pendingSelection));
    }

    // Handle plot focus from deep link.
    final pendingPlotFocus = PendingPlotSelection.take();
    if (pendingPlotFocus != null) {
      unawaited(_focusPlotFromDeepLink(pendingPlotFocus));
    }
  }

  Future<void> _fetchIpLocation() async {
    final result = await IpGeolocationService.getLocation();
    if (result == null || !mounted || _hasMovedToIpLocation) return;

    final ipLatLng = LatLng(result.latitude, result.longitude);

    // If map controller is ready, animate now
    final controller = _mapController;
    if (controller != null) {
      _hasMovedToIpLocation = true;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(ipLatLng, _initialCameraPosition.zoom),
      );
    } else {
      // Controller not ready yet - store for when it's created
      _pendingIpLocation = ipLatLng;
    }
  }

  @override
  void didPopNext() {
    // Returning from a pushed screen (e.g. PropertyDetailScreen). Flutter may
    // restore focus to the last-focused text field, which reopens the keyboard.
    // Force-hide it for map UX.
    _dismissKeyboard();

    // Favorites may have been toggled in a pushed screen.
    unawaited(_refreshSavedPropertyIds());

    final pendingFocus = PendingMapFocus.take();
    if (pendingFocus != null) {
      unawaited(_focusNewlyCreatedPropertyOnMap(pendingFocus));
    }

    // Handle property selection from deep link.
    final pendingSelection = PendingPropertySelection.take();
    if (pendingSelection != null) {
      unawaited(_selectPropertyFromDeepLink(pendingSelection));
    }

    // Handle plot focus from deep link.
    final pendingPlotFocus = PendingPlotSelection.take();
    if (pendingPlotFocus != null) {
      unawaited(_focusPlotFromDeepLink(pendingPlotFocus));
    }

    // Handle layout focus from deep link.
    final pendingLayoutFocus = PendingLayoutFocus.take();
    if (pendingLayoutFocus != null) {
      unawaited(_focusLayoutFromDeepLink(pendingLayoutFocus));
    }
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

    // Refresh favorites (saved properties) when auth changes.
    if (authKey == null) {
      _savedPropertyIds = <String>{};
      _savingPropertyIds.clear();
    } else {
      unawaited(_refreshSavedPropertyIds());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapController == null) return;
      _fetchViewport();
    });
  }

  Future<void> _refreshSavedPropertyIds() async {
    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      if (mounted) {
        setState(() => _savedPropertyIds = <String>{});
      }
      return;
    }

    try {
      final ids = await _savedPropertiesApi.getSavedPropertyIds(
        bearerToken: token,
      );
      if (!mounted) return;
      setState(() {
        _savedPropertyIds =
            ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      });
    } on SavedPropertiesApiException catch (ex) {
      // Best-effort: don't block map UX.
      debugPrint('Failed to load saved properties ids: ${ex.message}');
    } catch (ex) {
      debugPrint('Failed to load saved properties ids: $ex');
    }
  }

  bool _isFeatureSaved(MapPropertyFeature feature) {
    final id = feature.propertyId.trim();
    if (id.isEmpty) return false;
    return _savedPropertyIds.contains(id);
  }

  bool _isFeatureSaving(MapPropertyFeature feature) {
    final id = feature.propertyId.trim();
    if (id.isEmpty) return false;
    return _savingPropertyIds.contains(id);
  }

  Future<void> _toggleFeatureSaved(MapPropertyFeature feature) async {
    final propertyId = feature.propertyId.trim();
    if (propertyId.isEmpty) {
      ToastMessage.show(context, 'This listing cannot be saved');
      return;
    }

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      await AuthDialog.showLogin(context);
      return;
    }

    if (_savingPropertyIds.contains(propertyId)) return;

    final wasSaved = _savedPropertyIds.contains(propertyId);
    setState(() {
      _savingPropertyIds.add(propertyId);
      // Optimistic update.
      final next = Set<String>.from(_savedPropertyIds);
      if (wasSaved) {
        next.remove(propertyId);
      } else {
        next.add(propertyId);
      }
      _savedPropertyIds = next;
    });

    try {
      if (wasSaved) {
        await _savedPropertiesApi.unsaveProperty(
          propertyId: propertyId,
          bearerToken: token,
        );
      } else {
        await _savedPropertiesApi.saveProperty(
          propertyId: propertyId,
          bearerToken: token,
        );
      }
    } on SavedPropertiesApiException catch (ex) {
      if (!mounted) return;
      // Revert optimistic update.
      setState(() {
        final next = Set<String>.from(_savedPropertyIds);
        if (wasSaved) {
          next.add(propertyId);
        } else {
          next.remove(propertyId);
        }
        _savedPropertyIds = next;
      });
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final next = Set<String>.from(_savedPropertyIds);
        if (wasSaved) {
          next.add(propertyId);
        } else {
          next.remove(propertyId);
        }
        _savedPropertyIds = next;
      });
      ToastMessage.show(context, 'Failed to update shortlist');
    } finally {
      if (mounted) {
        setState(() => _savingPropertyIds.remove(propertyId));
      }
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

  Future<void> _initFeatureCoachmarks() async {
    await Future.wait([
      FeatureCoachmarkService.filter.initialize(),
      FeatureCoachmarkService.nearby.initialize(),
    ]);
    if (!mounted) return;
    _updateState(() {
      // Coachmarks are deferred: they appear after the nearby panel closes
      // (or immediately when no records are found).
      // Sequence: filter coachmark first, then nearby coachmark.
      _filterCoachmarkPending =
          FeatureCoachmarkService.filter.shouldShowCoachmark;
      _showFilterPulse = FeatureCoachmarkService.filter.shouldShowPulse;

      _nearbyCoachmarkPending =
          FeatureCoachmarkService.nearby.shouldShowCoachmark;
      // Nearby pulse is also deferred until after the nearby panel flow.
      _nearbyPulsePending = FeatureCoachmarkService.nearby.shouldShowPulse;
    });
  }

  /// Activate the pending coachmarks in sequence.
  /// Called after the nearby panel closes or when empty (no panel shown).
  ///
  /// If filter coachmark is pending it shows first; after it is dismissed
  /// the nearby coachmark will appear (see [_dismissFilterCoachmark]).
  void _activatePendingCoachmarks() {
    if (_filterCoachmarkPending) {
      _updateState(() {
        _filterCoachmarkPending = false;
        _showFilterCoachmark = true;
      });
      return; // nearby will be activated when filter is dismissed.
    }
    if (_nearbyCoachmarkPending) {
      _updateState(() {
        _nearbyCoachmarkPending = false;
        _showNearbyCoachmark = true;
      });
    }
  }

  // ── Filter coachmark ────────────────────────────────────────────────────

  void _dismissFilterCoachmark() {
    _updateState(() {
      _showFilterCoachmark = false;
    });
    unawaited(FeatureCoachmarkService.filter.onCoachmarkDismissed());
    // Show the nearby coachmark next (if pending).
    if (_nearbyCoachmarkPending) {
      _updateState(() {
        _nearbyCoachmarkPending = false;
        _showNearbyCoachmark = true;
      });
    } else if (_nearbyPulsePending) {
      _updateState(() {
        _nearbyPulsePending = false;
        _showNearbyPulse = true;
      });
    }
  }

  void _onFilterButtonTapped(Rect panelRect, Rect arrowRect) {
    // Permanently disable filter coachmark + pulse on first click.
    if (_showFilterCoachmark || _showFilterPulse) {
      _updateState(() {
        _showFilterCoachmark = false;
        _showFilterPulse = false;
      });
      unawaited(FeatureCoachmarkService.filter.onClicked());
      // Also activate nearby coachmark if it was queued behind filter.
      if (_nearbyCoachmarkPending) {
        _updateState(() {
          _nearbyCoachmarkPending = false;
          _showNearbyCoachmark = true;
        });
      } else if (_nearbyPulsePending) {
        _updateState(() {
          _nearbyPulsePending = false;
          _showNearbyPulse = true;
        });
      }
    }
    unawaited(_openFilters(panelRect, arrowRect));
  }

  // ── Nearby coachmark ────────────────────────────────────────────────────

  void _dismissNearbyCoachmark() {
    _updateState(() {
      _showNearbyCoachmark = false;
    });
    unawaited(FeatureCoachmarkService.nearby.onCoachmarkDismissed());
  }

  Future<void> _onNearbyButtonTapped() async {
    // Permanently disable coachmark + pulse on first real click.
    if (_showNearbyCoachmark || _showNearbyPulse) {
      _updateState(() {
        _showNearbyCoachmark = false;
        _showNearbyPulse = false;
      });
      unawaited(FeatureCoachmarkService.nearby.onClicked());
    }

    _nearbyLayoutsReopenHintTimer?.cancel();
    _nearbyLayoutsReopenHintTimer = null;
    _updateState(() {
      _isNearbyLayoutsReopenHintOn = false;
    });

    final anchor = _lastCameraPosition.target;
    unawaited(
      _openNearbyLayoutsPopup(
        anchor: anchor,
        showWhenEmpty: true,
        isManualOpen: true,
      ),
    );
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _routeSubscription = null;
    _mapController?.dispose();
    _viewportDebounceTimer?.cancel();
    _viewportLoadingTimer?.cancel();
    _viewportFetchingHideTimer?.cancel();
    _emptyStateDismissTimer?.cancel();
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
    // Phase 1: Collect pending marker data without rendering icons
    final pendingMarkers = <_PendingPropertyMarker>[];

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

      // Determine icon type
      _PropertyIconType iconType;
      if (shouldShowLayoutBadge) {
        iconType = _PropertyIconType.layoutBadge;
      } else if (isLayout) {
        iconType = _PropertyIconType.layoutDot;
      } else if (priceBadgeLabel != null) {
        iconType = _PropertyIconType.priceBadge;
      } else {
        iconType = _PropertyIconType.defaultMarker;
      }

      pendingMarkers.add(_PendingPropertyMarker(
        feature: feature,
        center: center,
        title: title,
        isLayout: isLayout,
        isSelected: isSelected,
        priceBadgeLabel: priceBadgeLabel,
        focusCenter: focusCenter,
        focusZoom: focusZoom,
        shouldShowLayoutBadge: shouldShowLayoutBadge,
        layoutLocation: layoutLocation,
        iconType: iconType,
      ));
    }

    // Phase 2: Render all icons in parallel
    final iconFutures = pendingMarkers.map((p) async {
      switch (p.iconType) {
        case _PropertyIconType.layoutBadge:
          return await _iconFactory.getLayoutBadgeIcon(
            title: p.title.isEmpty ? 'Layout' : p.title,
            subtitle: p.layoutLocation,
            zoom: zoom,
            pixelRatio: pixelRatio,
          );
        case _PropertyIconType.layoutDot:
          return await _iconFactory.getLayoutMarkerDotIcon(
            zoom: zoom,
            pixelRatio: pixelRatio,
          );
        case _PropertyIconType.priceBadge:
          final colors =
              _priceBadgeColorsForPropertyType(p.feature.propertyType);
          return await _iconFactory.getPriceBadgeIcon(
            label: p.priceBadgeLabel!,
            zoom: zoom,
            pixelRatio: pixelRatio,
            background: colors.background,
            stroke: colors.stroke,
            text: colors.text,
            emphasize: p.isSelected,
          );
        case _PropertyIconType.defaultMarker:
          return BitmapDescriptor.defaultMarker;
      }
    });

    final icons = await Future.wait(iconFutures);

    // Phase 3: Create markers with rendered icons
    final nextMarkers = <Marker>{};
    for (var i = 0; i < pendingMarkers.length; i++) {
      final p = pendingMarkers[i];
      final icon = icons[i];

      Offset anchor;
      double zIndex;
      switch (p.iconType) {
        case _PropertyIconType.layoutBadge:
          anchor = const Offset(0.5, 1.0);
          zIndex = 999999;
        case _PropertyIconType.layoutDot:
          anchor = const Offset(0.5, 0.5);
          zIndex = 140;
        case _PropertyIconType.priceBadge:
          anchor = const Offset(0.5, 1.0);
          zIndex = 200;
        case _PropertyIconType.defaultMarker:
          anchor = const Offset(0.5, 1.0);
          zIndex = 80;
      }

      nextMarkers.add(
        Marker(
          markerId: MarkerId(
              'property:${p.feature.propertyType}:${p.feature.featureId}'),
          position: p.center,
          icon: icon,
          anchor: anchor,
          zIndex: zIndex,
          onTap: p.feature.propertyType.trim() == 'IndependentHouse'
              ? () => _handleIndependentHouseTapped(
                    p.feature,
                    target: p.focusCenter ?? p.center,
                    zoom: p.focusZoom ?? 20.0,
                  )
              : p.isLayout
                  ? (p.shouldShowLayoutBadge
                      ? () => _focusPropertyOnMap(
                            target: p.focusCenter ?? p.center,
                            zoom: p.focusZoom ?? _layoutFocusZoomTarget,
                          )
                      : () {
                          final layoutId = p.feature.featureId.trim();
                          if (layoutId.isEmpty) {
                            ToastMessage.show(
                              context,
                              'Layout details not available',
                            );
                            return;
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _dismissKeyboard();
                            _closeAnyPanel();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => LayoutDetailScreen(
                                  layoutId: layoutId,
                                  fallbackFeature: p.feature,
                                ),
                              ),
                            );
                          });
                        })
                  : () => unawaited(
                        _handlePropertyTapped(
                          p.feature,
                          target: p.focusCenter ?? p.center,
                          zoom: p.focusZoom ?? 20.0,
                        ),
                      ),
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
    final isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final selectedPlot = _selectedPlot;
    final bottomSystemInset = MediaQuery.of(context).viewPadding.bottom;
    final bottomPanelInset = bottomSystemInset > 0 ? bottomSystemInset : 0.0;
    final isBottomPanelOpen = selectedPlot != null || _selectedProperty != null;

    final isViewportEmpty = _viewportMarkers.isEmpty &&
        _layoutPolygons.isEmpty &&
        _propertyPolygons.isEmpty &&
        _plotPolygons.isEmpty &&
        _amenityPolygons.isEmpty &&
        _roadPolygons.isEmpty &&
        _roadPolylines.isEmpty;

    final showEmptyState = isRouteCurrent &&
        !isBottomPanelOpen &&
        _hasViewportResult &&
        isViewportEmpty &&
        !_isSearchOverlayOpen &&
        !_isEmptyStateDismissed &&
        _triggeredByPlaceSearch;
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

              // Skip auto-switch if user manually selected map type this session.
              if (_userSelectedMapType) return;

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
            mapToolbarEnabled: false,
            markers: markers,
            polygons: {
              ..._layoutPolygons,
              ..._propertyPolygons,
              ..._selectedPropertyHighlightPolygons,
              ..._plotPolygons,
              ..._selectedPlotHighlightPolygons,
              ..._amenityPolygons,
              ..._roadPolygons,
              ..._layoutPreviewPolygons,
            },
            polylines: _roadPolylines,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            // Disable pan/zoom gestures until a place is selected.
            scrollGesturesEnabled: _hasSelectedPlace,
            zoomGesturesEnabled: _hasSelectedPlace,
          ),
          // Blurred overlay until a place is selected (matches web style).
          if (!_hasSelectedPlace)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                  child: Container(
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
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
                        key: _searchOverlayKey,
                        googlePlace: _googlePlace!,
                        onPlaceSelected: _moveCameraTo,
                        onShortlistedPlaceSelected: _moveCameraToFromShortlist,
                        onShortlistedPropertySelected:
                            _onShortlistedPropertySelected,
                        onMyPropertySelected: _onMyPropertySelected,
                        onMyPropertyDeleted: _onMyPropertyDeleted,
                        onMyPropertiesOpened: _closeAnyPanel,
                        getMapCenter: () => _lastCameraPosition.target,
                        getMapZoom: () => _lastCameraPosition.zoom,
                        onSearchTap: _closeAnyPanel,
                        onOpenChanged: (isOpen) {
                          if (_isSearchOverlayOpen == isOpen) return;
                          _safeSetState(() {
                            _isSearchOverlayOpen = isOpen;
                          });
                        },
                        onFilterTap: _onFilterButtonTapped,
                        hasActiveFilters: _hasAppliedNonDefaultFilters,
                        showFilterPulse: _showFilterPulse,
                        favoritesCount: _savedPropertyIds.length,
                      ),
              ],
            ),
          ),
          // Filter coachmark overlay (below the search bar, right-aligned to filter icon).
          if (_showFilterCoachmark)
            Positioned(
              top: 100,
              right: 71, // 16 (margin) + 48 (profile button) + 7 (gap)
              child: FilterCoachmarkTooltip(
                onDismiss: _dismissFilterCoachmark,
              ),
            ),
          if (!isBottomPanelOpen && _hasSelectedPlace)
            Positioned(
              left: 16,
              bottom: 10 + bottomPanelInset,
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
          if (!isBottomPanelOpen && _hasSelectedPlace)
            Positioned(
              right: 16,
              bottom: 10 + bottomPanelInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_showNearbyCoachmark)
                        NearbyCoachmarkTooltip(
                          onDismiss: _dismissNearbyCoachmark,
                        ),
                      NearbyPulseWrapper(
                        active: _showNearbyPulse,
                        child: _mapControlButton(
                          icon: Icons.list_alt_outlined,
                          tooltip: 'Nearby layouts',
                          highlight: _isNearbyLayoutsReopenHintOn,
                          onPressed: _onNearbyButtonTapped,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _mapZoomControl(),
                ],
              ),
            ),
          if (_isViewportLoading && !showEmptyState && _hasSelectedPlace)
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
          if (showEmptyState)
            Builder(
              builder: (context) {
                _emptyStateDismissTimer ??= Timer(
                  const Duration(seconds: 6),
                  () {
                    if (mounted) {
                      setState(() => _isEmptyStateDismissed = true);
                    }
                  },
                );
                return Positioned.fill(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.94),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F0F172A),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              top: -12,
                              right: -14,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _emptyStateDismissTimer?.cancel();
                                  _emptyStateDismissTimer = null;
                                  setState(() => _isEmptyStateDismissed = true);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'No listings here yet 👀',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Listings in this area are coming soon.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Be the first to add a property.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0FAD97),
                                  ),
                                ),
                                if (_isViewportFetching) ...[
                                  SizedBox(height: 10),
                                  Text(
                                    'Checking this area…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (selectedPlot != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPanelInset),
                child: PlotDetailsPanel(
                  plot: selectedPlot,
                  isSold: selectedPlot.layoutId != null &&
                      _isSoldPlot(selectedPlot),
                  areaLabel: _plotAreaLabel(selectedPlot),
                  tags: _plotTags(selectedPlot),
                  onClose: _closePlotPanel,
                  contactNumbers: _layoutContactNumbersForPlot(selectedPlot),
                  onLayoutDetails: () {
                    final layoutId = selectedPlot.layoutId;
                    if (layoutId == null || layoutId.trim().isEmpty) {
                      ToastMessage.show(
                        context,
                        'Layout details not available',
                      );
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
                    final isAuthenticated =
                        AuthScope.of(context).isAuthenticated;
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
            ),
          if (selectedPlot == null && _selectedProperty != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPanelInset),
                child:
                    _selectedProperty!.propertyType.trim() == 'IndependentHouse'
                        ? _buildIndependentHouseCarouselPanel()
                        : PropertyDetailsPanel(
                            feature: _selectedProperty!,
                            imageUrls: _selectedPropertyMediaUrls,
                            isLoadingImages: _isSelectedPropertyMediaLoading,
                            imagesError: _selectedPropertyMediaError,
                            isSaved: _isFeatureSaved(_selectedProperty!),
                            isSaving: _isFeatureSaving(_selectedProperty!),
                            onToggleSaved: () => unawaited(
                              _toggleFeatureSaved(_selectedProperty!),
                            ),
                            onOpenDetails: () =>
                                _openPropertyDetails(_selectedProperty!),
                            onClose: _closePropertyPanel,
                          ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Icon types for property markers.
enum _PropertyIconType {
  layoutBadge,
  layoutDot,
  priceBadge,
  defaultMarker,
}

/// Helper class for pending property marker data.
class _PendingPropertyMarker {
  const _PendingPropertyMarker({
    required this.feature,
    required this.center,
    required this.title,
    required this.isLayout,
    required this.isSelected,
    required this.priceBadgeLabel,
    required this.focusCenter,
    required this.focusZoom,
    required this.shouldShowLayoutBadge,
    required this.layoutLocation,
    required this.iconType,
  });

  final MapPropertyFeature feature;
  final LatLng center;
  final String title;
  final bool isLayout;
  final bool isSelected;
  final String? priceBadgeLabel;
  final LatLng? focusCenter;
  final double? focusZoom;
  final bool shouldShowLayoutBadge;
  final String? layoutLocation;
  final _PropertyIconType iconType;
}
