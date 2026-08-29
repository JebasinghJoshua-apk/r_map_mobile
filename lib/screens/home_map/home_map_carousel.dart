part of '../home_map_screen.dart';

/// Carousel extension for property browsing.
///
/// Key design principles:
/// 1. PageController is the single source of truth for visible page
/// 2. _selectedProperty is updated ONLY from onPageChanged or tap
/// 3. Never fight the PageController - don't try to "sync" it
/// 4. Use stable keys to prevent PageView recreation during rebuilds
/// 5. Shows all property types EXCEPT Layout (which uses separate plot panel)
/// 6. Respects user-applied filters from filter dialog
extension _HomeMapCarousel on _HomeMapScreenState {
  static const double _carouselRadiusKm = 4.0;
  static const int _carouselMaxItems = 10;

  /// Check if carousel refresh is currently suppressed.
  bool get _isCarouselRefreshSuppressed {
    final until = _independentHouseCarouselRefreshSuppressedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Suppress carousel refresh for a duration (prevents re-sorting during swipe).
  void _suppressCarouselRefresh(Duration duration) {
    _independentHouseCarouselRefreshSuppressedUntil =
        DateTime.now().add(duration);
  }

  /// Schedule a debounced carousel refresh.
  void _scheduleIndependentHouseCarouselRefresh() {
    if (_isCarouselRefreshSuppressed) return;

    _independentHouseCarouselDebounce?.cancel();
    _independentHouseCarouselDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_refreshIndependentHouseCarouselCandidates()),
    );
  }

  /// Refresh carousel candidates from API.
  Future<void> _refreshIndependentHouseCarouselCandidates({
    MapPropertyFeature? anchor,
  }) async {
    if (!mounted || _mapController == null) return;

    // Skip if suppressed and no explicit anchor
    if (anchor == null && _isCarouselRefreshSuppressed) {
      return;
    }

    // Skip refresh for Layout (Layout uses plot panel, not carousel)
    final selectedType = _selectedProperty?.propertyType.trim();
    if (selectedType == 'Layout' && anchor == null) {
      return;
    }

    final token = AuthScope.of(context).session?.token;

    LatLngBounds bounds;
    try {
      bounds = await _mapController!.getVisibleRegion();
    } catch (_) {
      return;
    }

    // Build query bounds
    const carouselBoundsMultiplier = 3.0;
    const carouselQueryZoom = 10.0;
    final expanded = _expandBounds(bounds, carouselBoundsMultiplier);
    final center = _lastCameraPosition.target;
    final radiusBounds = _boundsAroundCenter(center, _carouselRadiusKm);
    final queryBounds = _mergeBounds(expanded, radiusBounds);
    final requestId = ++_independentHouseCarouselRequestSeq;

    // Determine property types to query (server-side filtering)
    // Layout excluded - it uses plot panel, not carousel
    const carouselEligibleTypes = <String>[
      'IndependentHouse',
      'Land',
      'CommercialSpace',
      'ApartmentFlat',
    ];
    final userSelectedType = _selectedPropertyType?.trim();
    final queryTypes = (userSelectedType != null &&
            userSelectedType.isNotEmpty &&
            userSelectedType != 'Layout')
        ? <String>[userSelectedType]
        : carouselEligibleTypes;

    try {
      final response = await _mapApi.getViewport(
        bounds: queryBounds,
        zoom: carouselQueryZoom,
        propertyTypes: queryTypes,
        bearerToken: token,
      );

      if (!mounted || requestId != _independentHouseCarouselRequestSeq) return;

      // Apply user filters then exclude Layout (Layout uses plot panel)
      final filteredResponse = _applyClientFilters(response);
      final carouselProperties = filteredResponse.properties
          .where((p) => p.propertyType.trim() != 'Layout')
          .toList(growable: true);

      carouselProperties.sort((a, b) {
        final aScore = _distanceScore(center, a.centerPoint);
        final bScore = _distanceScore(center, b.centerPoint);
        return aScore.compareTo(bScore);
      });

      // Take candidates within radius or closest ones
      final withinRadius = carouselProperties.where((p) {
        final c = p.centerPoint;
        return c != null && _distanceKm(center, c) <= _carouselRadiusKm;
      }).toList(growable: false);

      final baseCandidates =
          withinRadius.isNotEmpty ? withinRadius : carouselProperties;
      var candidates =
          baseCandidates.take(_carouselMaxItems).toList(growable: true);

      // Ensure selected/anchor property is in list (if not Layout)
      final selected = anchor ?? _selectedProperty;
      if (selected != null && selected.propertyType.trim() != 'Layout') {
        final exists = candidates.any((p) => _featureMatches(p, selected));
        if (!exists) {
          candidates.insert(0, selected);
        }
      }

      if (candidates.length > _carouselMaxItems) {
        candidates = candidates.take(_carouselMaxItems).toList(growable: false);
      }

      // Find index of selected property
      final selectedIndex = selected == null
          ? 0
          : candidates.indexWhere((p) => _featureMatches(p, selected));
      final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;

      // Rebuild carousel with new candidates
      _rebuildCarousel(candidates, safeIndex);
    } catch (e) {
      debugPrint('[CAROUSEL] Refresh error: $e');
    }
  }

  /// Check if two features match by featureId or propertyId.
  bool _featureMatches(MapPropertyFeature a, MapPropertyFeature b) {
    if (a.featureId.trim() == b.featureId.trim()) return true;
    if (a.propertyId.trim().isNotEmpty &&
        a.propertyId.trim() == b.propertyId.trim()) return true;
    return false;
  }

  /// Rebuild carousel with new candidates, positioning at given index.
  void _rebuildCarousel(List<MapPropertyFeature> candidates, int initialIndex) {
    if (!mounted) return;

    final maxIdx = math.max(0, candidates.length - 1);
    final safeIndex = initialIndex.clamp(0, maxIdx);

    final oldItems = _independentHousesCarousel;

    // Check if we can skip forcing widget recreation:
    // - Selected property exists in BOTH old and new lists
    // - This is a "soft" refresh (not an explicit tap that needs repositioning)
    final selected = _selectedProperty;
    final canSkipRecreation = selected != null &&
        oldItems.isNotEmpty &&
        oldItems.any((p) => _featureMatches(p, selected)) &&
        candidates.any((p) => _featureMatches(p, selected));

    if (canSkipRecreation) {
      // Just update the list, let the stable widget preserve scroll position
      _updateState(() {
        _independentHousesCarousel =
            List<MapPropertyFeature>.unmodifiable(candidates);
        // Update index to match selected property's new position
        final newIdx =
            candidates.indexWhere((p) => _featureMatches(p, selected));
        if (newIdx >= 0) {
          _activeIndependentHouseIndex = newIdx;
        }
      });
      return;
    }

    // Force widget recreation by incrementing version
    _updateState(() {
      _independentHousesCarousel =
          List<MapPropertyFeature>.unmodifiable(candidates);
      _activeIndependentHouseIndex = safeIndex;
      _carouselVersion++; // Force _StableCarouselPageView recreation
    });
  }

  /// Handle tap on a carousel-eligible property marker.
  /// Works for IndependentHouse, Land, CommercialSpace, ApartmentFlat.
  Future<void> _handleCarouselPropertyTapped(
    MapPropertyFeature feature, {
    required LatLng target,
    required double zoom,
  }) async {
    _closePlotPanel();
    await _captureCameraBeforePropertyFocus();

    // Suppress refresh during animation
    _suppressCarouselRefresh(const Duration(milliseconds: 2500));

    // Set selection immediately
    _updateState(() {
      _selectedProperty = feature;
      _selectedPropertyHighlightPolygons =
          _buildSelectedPropertyHighlightPolygons(feature);
    });

    unawaited(_refreshMarkerSelectionStyles());

    // Refresh candidates with this feature as anchor
    await _refreshIndependentHouseCarouselCandidates(anchor: feature);

    _ensurePropertyMediaLoaded(feature);
    await _focusPropertyOnMap(
      target: target,
      zoom: zoom,
      boundaryGeoJson: feature.boundaryGeoJson,
    );
  }

  /// Height for the carousel panel.
  /// Scales with the device text-scale factor so larger font settings don't
  /// cause content to overflow the fixed-height card.
  /// Also accounts for high display-size settings which reduce logical pixels,
  /// triggering the narrow/vertical card layout that needs more height.
  double _propertyCarouselHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final scaleFactor = textScale.clamp(1.0, 1.6);
    return (h * 0.30 * scaleFactor).clamp(210.0, 380.0);
  }

  /// Build the carousel panel widget.
  Widget _buildIndependentHouseCarouselPanel() {
    final items = _independentHousesCarousel;

    // Fallback: show single property panel if carousel isn't ready
    if (items.isEmpty && _selectedProperty != null) {
      return _buildSinglePropertyPanel(_selectedProperty!);
    }

    if (items.length == 1) {
      return _buildSinglePropertyPanel(items.first);
    }

    // Use stable carousel widget that isolates PageView from parent rebuilds.
    // Key changes when carouselVersion changes (explicit rebuild from tap/refresh).
    // Inside the widget, PageController is only recreated when initialPage changes.
    return _StableCarouselPageView(
      key: ValueKey<int>(_carouselVersion),
      itemCount: items.length,
      initialPage: _activeIndependentHouseIndex,
      height: _propertyCarouselHeight(context),
      onPageChanged: _handleCarouselPageChanged,
      itemBuilder: _buildCarouselItem,
    );
  }

  /// Handle page change from swipe.
  void _handleCarouselPageChanged(int index) {
    if (!mounted) return;

    final items = _independentHousesCarousel;
    if (items.isEmpty || index < 0 || index >= items.length) return;

    // Suppress refresh to prevent re-sorting during swipe
    _suppressCarouselRefresh(const Duration(milliseconds: 1500));

    final next = items[index];

    // Skip if already selected
    final current = _selectedProperty;
    if (current != null && _featureMatches(current, next)) {
      if (_activeIndependentHouseIndex != index) {
        _updateState(() {
          _activeIndependentHouseIndex = index;
        });
      }
      return;
    }

    // Update selection
    _updateState(() {
      _activeIndependentHouseIndex = index;
      _selectedProperty = next;
      _selectedPropertyHighlightPolygons =
          _buildSelectedPropertyHighlightPolygons(next);
    });

    unawaited(_refreshMarkerSelectionStyles());
    _ensurePropertyMediaLoaded(next);

    // Focus map on new property
    final center = next.centerPoint;
    if (center != null) {
      unawaited(_focusPropertyOnMap(target: center, zoom: 20.0));
    }
  }

  /// Build a single carousel item.
  Widget _buildCarouselItem(BuildContext context, int index) {
    final items = _independentHousesCarousel;
    if (items.isEmpty || index >= items.length) {
      return const SizedBox.shrink();
    }

    final feature = items[index];
    final key = _propertyMediaCacheKey(feature);
    final cached = key == null ? null : _propertyMediaCache[key];

    // Preload after the current build because cache-hit synchronization can
    // update the parent selection state.
    if (index == _activeIndependentHouseIndex && items.length > 1) {
      final n = items.length;
      final previous = items[(index - 1 + n) % n];
      final next = items[(index + 1) % n];
      runAfterBuild(() {
        if (!mounted) return;
        _ensurePropertyMediaLoaded(feature);
        _ensurePropertyMediaLoaded(previous);
        _ensurePropertyMediaLoaded(next);
      });
    }

    return PropertyDetailsPanel(
      key: ValueKey('property:${feature.featureId.trim()}'),
      feature: feature,
      imageUrls: cached?.urls,
      isLoadingImages: cached?.isLoading ?? false,
      imagesError: cached?.error,
      isSaved: _isFeatureSaved(feature),
      isSaving: _isFeatureSaving(feature),
      onToggleSaved: () => unawaited(_toggleFeatureSaved(feature)),
      outerPadding: const EdgeInsets.fromLTRB(4, 0, 6, 8),
      onOpenDetails: () => _openPropertyDetails(feature),
      onClose: _closePropertyPanel,
    );
  }

  /// Build single property panel (non-carousel).
  Widget _buildSinglePropertyPanel(MapPropertyFeature feature) {
    final key = _propertyMediaCacheKey(feature);
    final cached = key == null ? null : _propertyMediaCache[key];
    return PropertyDetailsPanel(
      key: ValueKey('property:${feature.featureId.trim()}'),
      feature: feature,
      imageUrls: cached?.urls,
      isLoadingImages: cached?.isLoading ?? false,
      imagesError: cached?.error,
      isSaved: _isFeatureSaved(feature),
      isSaving: _isFeatureSaving(feature),
      onToggleSaved: () => unawaited(_toggleFeatureSaved(feature)),
      outerPadding: const EdgeInsets.fromLTRB(4, 0, 6, 8),
      onOpenDetails: () => _openPropertyDetails(feature),
      onClose: _closePropertyPanel,
    );
  }

  // --- Helper methods ---

  double _distanceScore(LatLng center, LatLng? point) {
    if (point == null) return double.infinity;
    final dLat = point.latitude - center.latitude;
    final dLng = point.longitude - center.longitude;
    final scale = math.cos(center.latitude * (math.pi / 180.0));
    final x = dLng * scale;
    return x * x + dLat * dLat;
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final lat1 = a.latitude * (math.pi / 180.0);
    final lat2 = b.latitude * (math.pi / 180.0);
    final dLat = (b.latitude - a.latitude) * (math.pi / 180.0);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180.0);

    final sinLat = math.sin(dLat / 2.0);
    final sinLng = math.sin(dLng / 2.0);
    final h =
        (sinLat * sinLat) + math.cos(lat1) * math.cos(lat2) * (sinLng * sinLng);
    final c = 2.0 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
    return earthRadiusKm * c;
  }

  LatLngBounds _boundsAroundCenter(LatLng center, double radiusKm) {
    final degLat = radiusKm / 111.0;
    final cosLat = math.cos(center.latitude * (math.pi / 180.0)).abs();
    final safeCosLat = cosLat < 0.0001 ? 0.0001 : cosLat;
    final degLng = radiusKm / (111.0 * safeCosLat);

    return LatLngBounds(
      southwest: LatLng(
        (center.latitude - degLat).clamp(-90.0, 90.0),
        (center.longitude - degLng).clamp(-180.0, 180.0),
      ),
      northeast: LatLng(
        (center.latitude + degLat).clamp(-90.0, 90.0),
        (center.longitude + degLng).clamp(-180.0, 180.0),
      ),
    );
  }

  LatLngBounds _mergeBounds(LatLngBounds a, LatLngBounds b) {
    return LatLngBounds(
      southwest: LatLng(
        math.min(a.southwest.latitude, b.southwest.latitude),
        math.min(a.southwest.longitude, b.southwest.longitude),
      ),
      northeast: LatLng(
        math.max(a.northeast.latitude, b.northeast.latitude),
        math.max(a.northeast.longitude, b.northeast.longitude),
      ),
    );
  }
}

/// A stable carousel widget that isolates PageView state from parent rebuilds.
/// This widget owns its own PageController and only recreates it when [initialPage] changes.
class _StableCarouselPageView extends StatefulWidget {
  const _StableCarouselPageView({
    super.key,
    required this.itemCount,
    required this.initialPage,
    required this.itemBuilder,
    required this.onPageChanged,
    required this.height,
  });

  final int itemCount;
  final int initialPage;
  final Widget Function(BuildContext, int) itemBuilder;
  final void Function(int) onPageChanged;
  final double height;

  @override
  State<_StableCarouselPageView> createState() =>
      _StableCarouselPageViewState();
}

class _StableCarouselPageViewState extends State<_StableCarouselPageView> {
  late PageController _controller;

  // For infinite scrolling, we use a large virtual item count
  // and map indices back to real items using modulo.
  static const int _infiniteMultiplier = 1000;
  int get _virtualItemCount => widget.itemCount * _infiniteMultiplier;
  int get _virtualInitialPage =>
      ((_infiniteMultiplier ~/ 2) * widget.itemCount) + widget.initialPage;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _virtualInitialPage,
      viewportFraction: 0.92,
    );
  }

  @override
  void didUpdateWidget(_StableCarouselPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only recreate controller if initial page changed significantly
    // (i.e., a new carousel was built, not just a parent rebuild)
    if (widget.initialPage != oldWidget.initialPage ||
        widget.itemCount != oldWidget.itemCount) {
      _controller.dispose();
      _controller = PageController(
        initialPage: _virtualInitialPage,
        viewportFraction: 0.92,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePageChanged(int virtualIndex) {
    // Map virtual index back to real index
    final realIndex = virtualIndex % widget.itemCount;
    widget.onPageChanged(realIndex);
  }

  Widget _buildItem(BuildContext context, int virtualIndex) {
    // Map virtual index back to real index
    final realIndex = virtualIndex % widget.itemCount;
    return widget.itemBuilder(context, realIndex);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _controller,
        itemCount: _virtualItemCount,
        padEnds: true,
        onPageChanged: _handlePageChanged,
        itemBuilder: _buildItem,
      ),
    );
  }
}
