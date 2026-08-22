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
import 'package:location/location.dart' as loc;
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../constants/api_constants.dart';
import '../constants/search_constants.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_settings_service.dart';
import '../services/firebase_perf_service.dart';
import '../services/in_app_update_service.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_plots_api.dart';
import '../services/performance_logger.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../utils/user_role.dart';
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
import 'property_polygon_editor_screen.dart';
import 'property_details_form_screen.dart';
import 'layout_details_form_screen.dart';
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
part 'home_map/home_map_dimensions.dart';
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
  bool _isLocating = false;
  bool _myLocationEnabled = false;
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

  /// Camera position when the user last selected a place from search/shortlist.
  /// Used to re-focus on back press if the user has panned away.
  CameraPosition? _lastSelectedPlacePosition;

  /// True when the user has manually panned/zoomed away from the last selected place.
  bool _userPannedFromPlace = false;

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
  Set<Marker> _selectedPropertyChildPlotLabelMarkers = <Marker>{};
  Set<Marker> _selectedPropertyChildRoadLabelMarkers = <Marker>{};
  Set<Marker> _selectedPropertyChildAmenityLabelMarkers = <Marker>{};
  Set<Marker> _dimensionMarkers = <Marker>{};

  /// Current viewport plots for dimension label rendering at very high zoom.
  List<MapPlotFeature> _currentViewportPlots = const [];

  Set<Polygon> _layoutPolygons = <Polygon>{};
  Set<Polygon> _propertyPolygons = <Polygon>{};
  Set<Polygon> _plotPolygons = <Polygon>{};
  Set<Polygon> _selectedPlotHighlightPolygons = <Polygon>{};
  Set<Polygon> _selectedPropertyHighlightPolygons = <Polygon>{};
  Set<Polygon> _selectedPropertyChildPlotPolygons = <Polygon>{};
  Set<Polygon> _amenityPolygons = <Polygon>{};
  Set<Polygon> _selectedPropertyChildAmenityPolygons = <Polygon>{};
  Set<Polygon> _roadPolygons = <Polygon>{};
  Set<Polygon> _selectedPropertyChildRoadPolygons = <Polygon>{};
  Set<Polyline> _roadPolylines = <Polyline>{};
  Set<Polyline> _selectedPropertyChildRoadPolylines = <Polyline>{};

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
  Timer? _independentHouseCarouselDebounce;
  int _independentHouseCarouselRequestSeq = 0;
  DateTime? _independentHouseCarouselRefreshSuppressedUntil;
  int _carouselVersion = 0; // Increments only on explicit rebuild

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
  bool _isNearbyLoading = false;
  bool _isNearbyLayoutsReopenHintOn = false;
  Timer? _nearbyLayoutsReopenHintTimer;

  // Feature coachmark / pulse state
  bool _showFilterCoachmark = false;
  bool _filterCoachmarkPending = false;

  bool _showNearbyCoachmark = false;
  bool _showNearbyPulse = false;
  bool _nearbyCoachmarkPending = false;
  bool _nearbyPulsePending = false;

  static const Duration _nearbyNewThreshold = Duration(days: 7);

  Future<void> _refreshMarkerSelectionStyles() async {
    if (!mounted) return;

    final features = _propertyByFeatureId.values.toList(growable: true);

    // Ensure the selected property is included in the features list even if
    // it's not in the current viewport. This happens when swiping the carousel
    // to a property that's outside the visible map area.
    final selected = _selectedProperty;
    if (selected != null) {
      final existsInFeatures = features.any(
        (f) => f.featureId.trim() == selected.featureId.trim(),
      );
      if (!existsInFeatures) {
        features.add(selected);
      }
    }

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
    final rawMeta = plot.metadata['contactNumbers']?.trim();
    if (rawMeta != null && rawMeta.isNotEmpty) {
      return rawMeta
          .split(RegExp(r'[\n,;/.|]+'))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
    }

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
        .split(RegExp(r'[\n,;/.|]+'))
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
    // Signal that the home screen is ready for push-notification navigation.
    markHomeScreenReady();

    // Check for in-app updates from Play Store (non-blocking).
    InAppUpdateService.instance.checkForUpdate();

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
      unawaited(_focusLayoutFromDeepLink(
        pendingLayoutFocus.layoutId,
        boundaryGeoJson: pendingLayoutFocus.boundaryGeoJson,
      ));
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
    if (_showFilterCoachmark) {
      _updateState(() {
        _showFilterCoachmark = false;
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

  /// Show property type picker → login if needed → open polygon editor.
  Future<void> _onAddPropertyTapped() async {
    final baseOptions = <String>[
      'Independent House',
      'Plot',
      'Apartment',
      'Land',
      'Commercial Space',
    ];
    final userRole =
        AuthScope.of(context).session?.user.roleValue ?? UserRole.user;
    final isAdmin = userRole == UserRole.admin;
    final options = isAdmin ? [...baseOptions, 'Layout', 'Farm Land'] : baseOptions;

    // Fetch contact phone from backend (cached, no delay on subsequent calls).
    final appSettings = await AppSettingsService().getSettings();
    final contactPhone = appSettings.contactPhone;

    final selectedType = await showDialog<String>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final maxWidth = size.width - 64;
        final dialogWidth = maxWidth < 332 ? maxWidth : 332.0;
        final dialogMaxHeight = (size.height - 96).clamp(240.0, 520.0);

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: dialogMaxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Add Property',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final opt = options[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        overlayColor: WidgetStateProperty.resolveWith(
                          (states) {
                            if (states.contains(WidgetState.pressed)) {
                              return const Color(0xFF0FAD97).withOpacity(0.10);
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return const Color(0xFF0FAD97).withOpacity(0.06);
                            }
                            return null;
                          },
                        ),
                        onTap: () => Navigator.of(context).pop(opt),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    opt,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (contactPhone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Center(
                      child: Text.rich(
                        TextSpan(
                          text: 'To add a layout, please contact ',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: GestureDetector(
                                onTap: () => launchUrl(
                                  Uri(scheme: 'tel', path: contactPhone),
                                ),
                                child: Text(
                                  contactPhone,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF0D8B7A),
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Color(0xFF0D8B7A),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedType == null || selectedType.trim().isEmpty) return;

    // Login gate — prompt if not signed in.
    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      await AuthDialog.showLogin(context);
      if (!mounted) return;
      // Re-check after login dialog
      final newToken = AuthScope.of(context).session?.token;
      if (newToken == null || newToken.trim().isEmpty) return;
    }

    final center = _lastCameraPosition.target;
    final zoom = _lastCameraPosition.zoom;
    final bearerToken = AuthScope.of(context).session?.token ?? '';

    // Layout uses a dedicated screen with boundary drawing + QR generation
    if (selectedType == 'Layout' || selectedType == 'Farm Land') {
      final isFarmLand = selectedType == 'Farm Land';
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => LayoutDetailsFormScreen(
            initialCenter: center,
            initialZoom: zoom,
            isFarmLand: isFarmLand,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context, rootNavigator: true).push<List<LatLng>>(
      MaterialPageRoute(
        builder: (_) => PropertyPolygonEditorScreen(
          mode: PropertyPolygonEditorMode.add,
          initialCenter: center,
          initialZoom: zoom,
          bearerToken: bearerToken,
          popOnNext: false,
          onNext: (points) async {
            await Navigator.of(context, rootNavigator: true)
                .push<String>(
              MaterialPageRoute(
                builder: (_) => PropertyDetailsFormScreen(
                  boundaryPoints: points,
                  initialPropertyType: selectedType,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onNearbyButtonTapped() async {
    // Guard against multiple rapid taps while loading / dialog is open.
    if (_isNearbyLoading || _isNearbyLayoutsDialogOpen) return;

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

    _updateState(() => _isNearbyLoading = true);
    try {
      final anchor = _lastCameraPosition.target;
      await _openNearbyLayoutsPopup(
        anchor: anchor,
        showWhenEmpty: true,
        isManualOpen: true,
      );
    } finally {
      _updateState(() => _isNearbyLoading = false);
    }
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
    // Farmland plots show the saved value with "Cent" unit instead of sqft.
    final isFarmLand =
        (meta['isFarmLand'] ?? meta['is_farm_land'] ?? meta['farmLand'])
                ?.trim()
                .toLowerCase() ==
            'true';
    final unit = isFarmLand ? 'Cent' : 'sqft';
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
      // Show decimal only when needed (e.g. 1270.69 → "1270.69", 1300.0 → "1300")
      final display = value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
      return '$display $unit';
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
    final selected = _selectedProperty;

    for (final feature in response.properties) {
      final center = feature.centerPoint;
      if (center == null) continue;

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
            ? _layoutFocusZoomFromMetadata(feature.metadata)
            : _priceBadgeFocusZoomTarget(feature.propertyType);
      }

      if (!isLayout && focusZoom == null) {
        focusCenter = center;
        focusZoom = _priceBadgeFocusZoomTarget(feature.propertyType);
      }

      final shouldShowLayoutBadge = isLayout && zoom <= _layoutBadgeMaxZoom;

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
        iconType: iconType,
      ));
    }

    // Phase 1b: Cluster overlapping layout badges at low zoom.
    _clusterLayoutBadges(pendingMarkers, zoom);

    // Phase 2: Render all icons in parallel
    final iconFutures = pendingMarkers.map((p) async {
      final isFarmLand = p.feature.metadata['isFarmLand'] == 'true';
      switch (p.iconType) {
        case _PropertyIconType.layoutBadge:
          return await _iconFactory.getLayoutBadgeIcon(
            title: p.title.isEmpty ? 'Layout' : p.title,
            zoom: zoom,
            pixelRatio: pixelRatio,
            isFarmLand: isFarmLand,
          );
        case _PropertyIconType.layoutCluster:
          return await _iconFactory.getLayoutClusterIcon(
            count: p.clusterCount,
            zoom: zoom,
            pixelRatio: pixelRatio,
            titleOverride: p.clusterTitle,
            isFarmLand: isFarmLand,
          );
        case _PropertyIconType.layoutDot:
          return await _iconFactory.getLayoutMarkerDotIcon(
            zoom: zoom,
            pixelRatio: pixelRatio,
            isFarmLand: isFarmLand,
            phaseLabel: _extractPhaseLabel(p.title),
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
        case _PropertyIconType.layoutCluster:
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
          onTap: p.isLayout
              ? (p.iconType == _PropertyIconType.layoutCluster
                  ? () => _focusPropertyOnMap(
                        target: p.center,
                        zoom: (zoom + 2).clamp(zoom + 1, _layoutBadgeMaxZoom + 0.5),
                      )
                  : p.shouldShowLayoutBadge
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
              // IndependentHouse, Land, CommercialSpace, ApartmentFlat - all use carousel
              : () => unawaited(
                    _handleCarouselPropertyTapped(
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

  /// Strips trailing Roman numeral or numeric suffixes to extract a base name.
  /// e.g. "Thirumal Nagar I" → "Thirumal Nagar",
  ///      "Thirumal Nagar III" → "Thirumal Nagar",
  ///      "Sai Garden 2" → "Sai Garden".
  static String _layoutBaseName(String name) {
    // Remove trailing Roman numerals (I, II, III, IV, V, VI, VII, VIII, IX, X, etc.)
    // or plain digits, optionally preceded by a dash or dot.
    final stripped = name
        .replaceFirst(
          RegExp(
            r'[\s\-\.]+(?:X{0,3}(?:IX|IV|V?I{0,3})|\d+)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return stripped.isEmpty ? name.trim() : stripped;
  }

  /// Groups nearby layout badge markers into clusters using a grid-based
  /// spatial hash. Within each grid cell, layouts that share the same base
  /// name (ignoring trailing Roman numeral / numeric suffixes) are merged
  /// into a single badge like "Thirumal Nagar(3)". Remaining layouts that
  /// don't share a name are merged with the generic count label.
  void _clusterLayoutBadges(List<_PendingPropertyMarker> markers, double zoom) {
    if (zoom > _layoutClusterMaxZoom) return; // mid-zoom: show individual badges

    final cellSize = _layoutClusterCellSize(zoom);
    // Map from grid-cell key → sub-map of baseName → list of marker indices.
    final cells = <String, Map<String, List<int>>>{};

    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      if (m.iconType != _PropertyIconType.layoutBadge) continue;

      final cellX = (m.center.longitude / cellSize).floor();
      final cellY = (m.center.latitude / cellSize).floor();
      final cellKey = '$cellX,$cellY';
      final baseName = _layoutBaseName(m.title);

      cells.putIfAbsent(cellKey, () => <String, List<int>>{});
      cells[cellKey]!.putIfAbsent(baseName, () => <int>[]);
      cells[cellKey]![baseName]!.add(i);
    }

    final toRemove = <int>{};

    for (final cell in cells.values) {
      for (final entry in cell.entries) {
        final indices = entry.value;
        if (indices.length <= 1) continue;

        // Use the first marker as the representative.
        final rep = markers[indices.first];
        rep.clusterCount = indices.length;
        rep.iconType = _PropertyIconType.layoutCluster;
        rep.clusterTitle = '${entry.key}(${indices.length})';

        // Mark the rest for removal.
        for (var j = 1; j < indices.length; j++) {
          toRemove.add(indices[j]);
        }
      }
    }

    if (toRemove.isEmpty) return;
    // Remove absorbed markers in reverse to preserve indices.
    final sorted = toRemove.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      markers.removeAt(idx);
    }
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
    final selectedPropertyType = _selectedProperty?.propertyType.trim();
    final bottomSystemInset = MediaQuery.of(context).viewPadding.bottom;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final bottomPanelInset =
        isIOS ? 16.0 : (bottomSystemInset > 0 ? bottomSystemInset : 0.0);
    final showPropertyPanel = _selectedProperty != null;
    final isBottomPanelOpen = selectedPlot != null || showPropertyPanel;

    final isViewportEmpty = _viewportMarkers.isEmpty &&
        _layoutPolygons.isEmpty &&
        _propertyPolygons.isEmpty &&
        _plotPolygons.isEmpty &&
      _selectedPropertyChildPlotPolygons.isEmpty &&
        _amenityPolygons.isEmpty &&
      _selectedPropertyChildAmenityPolygons.isEmpty &&
        _roadPolygons.isEmpty &&
      _selectedPropertyChildRoadPolygons.isEmpty &&
      _roadPolylines.isEmpty &&
      _selectedPropertyChildRoadPolylines.isEmpty;

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
      ..._selectedPropertyChildPlotLabelMarkers,
      ..._selectedPropertyChildRoadLabelMarkers,
      ..._selectedPropertyChildAmenityLabelMarkers,
      ..._dimensionMarkers,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
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
                ..._selectedPropertyChildPlotPolygons,
                ..._selectedPlotHighlightPolygons,
                ..._amenityPolygons,
                ..._selectedPropertyChildAmenityPolygons,
                ..._roadPolygons,
                ..._selectedPropertyChildRoadPolygons,
                ..._layoutPreviewPolygons,
              },
              polylines: {
                ..._roadPolylines,
                ..._selectedPropertyChildRoadPolylines,
              },
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              myLocationEnabled: _myLocationEnabled,
              myLocationButtonEnabled: false,
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
            // Viewport loading indicator (panning/zooming data fetch).
            if (_isViewportFetching && !showEmptyState && _hasSelectedPlace)
              Positioned.fill(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF6B7280)),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Loading',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).viewPadding.top,
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
                          onShortlistedPlaceSelected:
                              _moveCameraToFromShortlist,
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
                child: Column(
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
                      onPressed: _toggleSatelliteMode,
                    ),
                  ],
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
                    NearbyPulseWrapper(
                      active: _showNearbyPulse,
                      child: _mapControlButton(
                        icon: Icons.list_alt_outlined,
                        tooltip: 'Nearby layouts',
                        highlight: _isNearbyLayoutsReopenHintOn,
                        onPressed: _onNearbyButtonTapped,
                        isLoading: _isNearbyLoading,
                        backgroundColor: Colors.white,
                        iconColor: const Color(0xFF0D9488),
                        glowColor: const Color(0xFF14B8A6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _mapZoomControl(),
                  ],
                ),
              ),
            // "Add Property" button – centred at bottom, visible to all users.
            if (!isBottomPanelOpen && _hasSelectedPlace)
              Positioned(
                bottom: 10 + bottomPanelInset,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _onAddPropertyTapped,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D8B7A),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Add Property',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
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
            // Nearby coachmark — separate Positioned so it doesn't
            // shift the button and can receive taps outside the column.
            if (!isBottomPanelOpen && _hasSelectedPlace && _showNearbyCoachmark)
              Positioned(
                // Vertically centre on the nearby-list button:
                // zoom (73) + gap (10) + half-button (18) = 101
                bottom: 10 + bottomPanelInset + 101 - 36,
                right: 16 + 40, // 16 (column right) + 36 (button) + 4 (gap)
                child: NearbyCoachmarkTooltip(
                  onDismiss: _dismissNearbyCoachmark,
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
                          padding: EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
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
                                    setState(
                                        () => _isEmptyStateDismissed = true);
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
                  child: () {
                    final isIndividualPlot =
                        (selectedPlot.individualPlotsId?.trim().isNotEmpty ??
                                false) &&
                            (selectedPlot.layoutId == null ||
                                selectedPlot.layoutId!.trim().isEmpty);
                    return PlotDetailsPanel(
                      plot: selectedPlot,
                      isSold: _isSoldPlot(selectedPlot),
                      areaLabel: _plotAreaLabel(selectedPlot),
                      tags: _plotTags(selectedPlot),
                      onClose: _closePlotPanel,
                      contactNumbers:
                          _layoutContactNumbersForPlot(selectedPlot),
                      detailsLabel:
                          isIndividualPlot ? 'Property Details →' : null,
                      onLayoutDetails: () {
                        if (isIndividualPlot) {
                          final ipId = selectedPlot.individualPlotsId!.trim();
                          final feature = _propertyByFeatureId[ipId] ??
                              (_selectedProperty?.featureId.trim() == ipId
                                  ? _selectedProperty
                                  : null);
                          if (feature == null) {
                            ToastMessage.show(
                              context,
                              'Property details not available',
                            );
                            return;
                          }
                          _dismissKeyboard();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PropertyDetailScreen(
                                feature: feature,
                              ),
                            ),
                          );
                          return;
                        }
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
                        return (status) =>
                            _updatePlotStatus(selectedPlot, status);
                      }(),
                    );
                  }(),
                ),
              ),
            if (selectedPlot == null && showPropertyPanel)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPanelInset),
                  // All non-Layout property types use carousel panel
                  child: _selectedProperty!.propertyType.trim() == 'Layout'
                      ? PropertyDetailsPanel(
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
                        )
                      : _buildIndependentHouseCarouselPanel(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Icon types for property markers.
enum _PropertyIconType {
  layoutBadge,
  layoutCluster,
  layoutDot,
  priceBadge,
  defaultMarker,
}

/// Helper class for pending property marker data.
class _PendingPropertyMarker {
  _PendingPropertyMarker({
    required this.feature,
    required this.center,
    required this.title,
    required this.isLayout,
    required this.isSelected,
    required this.priceBadgeLabel,
    required this.focusCenter,
    required this.focusZoom,
    required this.shouldShowLayoutBadge,
    required this.iconType,
    this.clusterCount = 1,
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
  _PropertyIconType iconType;
  int clusterCount;
  String? clusterTitle;
}
