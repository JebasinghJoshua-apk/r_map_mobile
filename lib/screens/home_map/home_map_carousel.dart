part of '../home_map_screen.dart';

extension _HomeMapCarousel on _HomeMapScreenState {
  static const double _carouselRadiusKm = 4.0;
  static const int _carouselMaxItems = 10;

  int _carouselPageCount(int itemCount) => itemCount + 2;

  int _itemIndexFromCarouselPage(int pageIndex, int itemCount) {
    if (itemCount <= 0) return 0;
    if (pageIndex <= 0) return itemCount - 1;
    if (pageIndex >= itemCount + 1) return 0;
    return pageIndex - 1;
  }

  bool get _isIndependentHouseCarouselRefreshSuppressed {
    final until = _independentHouseCarouselRefreshSuppressedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _scheduleIndependentHouseCarouselRefresh() {
    if (_isIndependentHouseCarouselRefreshSuppressed) {
      return;
    }

    _independentHouseCarouselDebounce?.cancel();
    _independentHouseCarouselDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_refreshIndependentHouseCarouselCandidates()),
    );
  }

  Future<void> _refreshIndependentHouseCarouselCandidates({
    MapPropertyFeature? anchor,
  }) async {
    if (!mounted) return;
    if (_mapController == null) return;
    if (_selectedProperty?.propertyType.trim() != 'IndependentHouse' &&
        anchor == null) {
      return;
    }

    final token = AuthScope.of(context).session?.token;

    LatLngBounds bounds;
    try {
      bounds = await _mapController!.getVisibleRegion();
    } catch (_) {
      return;
    }

    // Larger-than-viewport fetch ONLY for the bottom panel.
    // Keep payload light by forcing zoom < 11 => Minimal detail on backend.
    const carouselBoundsMultiplier = 3.0;
    const carouselQueryZoom = 10.0;

    final expanded = _expandBounds(bounds, carouselBoundsMultiplier);
    final center = _lastCameraPosition.target;
    final radiusBounds = _boundsAroundCenter(center, _carouselRadiusKm);
    final queryBounds = _mergeBounds(expanded, radiusBounds);
    final requestId = ++_independentHouseCarouselRequestSeq;

    try {
      final response = await _mapApi.getViewport(
        bounds: queryBounds,
        zoom: carouselQueryZoom,
        propertyTypes: const <String>['IndependentHouse'],
        bearerToken: token,
      );

      if (!mounted || requestId != _independentHouseCarouselRequestSeq) {
        return;
      }

      final filteredResponse = _applyClientFilters(response);
      final houses = filteredResponse.properties
          .where((p) => p.propertyType.trim() == 'IndependentHouse')
          .toList(growable: true);

      houses.sort((a, b) {
        final aCenter = a.centerPoint;
        final bCenter = b.centerPoint;
        final aScore = aCenter == null
            ? double.infinity
            : _distanceScoreFromCenter(center, aCenter);
        final bScore = bCenter == null
            ? double.infinity
            : _distanceScoreFromCenter(center, bCenter);
        return aScore.compareTo(bScore);
      });

      // Prefer items within 4km of map center; fallback to nearest overall.
      final withinRadius = houses.where((h) {
        final c = h.centerPoint;
        if (c == null) return false;
        return _distanceKm(center, c) <= _carouselRadiusKm;
      }).toList(growable: false);

      final baseCandidates = withinRadius.isNotEmpty ? withinRadius : houses;
      var candidates =
          baseCandidates.take(_carouselMaxItems).toList(growable: true);

      final selected = anchor ?? _selectedProperty;
      if (selected != null &&
          selected.propertyType.trim() == 'IndependentHouse') {
        final exists = candidates.any(
          (p) =>
              p.featureId.trim() == selected.featureId.trim() ||
              (p.propertyId.trim().isNotEmpty &&
                  p.propertyId.trim() == selected.propertyId.trim()),
        );
        if (!exists) {
          candidates.insert(0, selected);
        }
      }

      if (candidates.length > _carouselMaxItems) {
        candidates = candidates.take(_carouselMaxItems).toList(growable: false);
      }

      final nextIndex = selected == null
          ? 0
          : candidates.indexWhere(
              (p) =>
                  p.featureId.trim() == selected.featureId.trim() ||
                  (p.propertyId.trim().isNotEmpty &&
                      p.propertyId.trim() == selected.propertyId.trim()),
            );

      _updateState(() {
        _independentHousesCarousel =
            List<MapPropertyFeature>.unmodifiable(candidates);
        _activeIndependentHouseIndex = nextIndex >= 0 ? nextIndex : 0;
      });

      if (candidates.isEmpty) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _independentHouseCarouselController;
        if (!mounted || c == null || !c.hasClients) return;
        final targetPage =
            (_activeIndependentHouseIndex.clamp(0, candidates.length - 1)) + 1;
        if (c.page?.round() != targetPage) {
          _suppressCarouselFocusOnce = true;
          c.jumpToPage(targetPage);
        }
      });
    } catch (_) {
      // Best-effort: if this fails, we keep the previous carousel list.
    }
  }

  double _distanceScoreFromCenter(LatLng center, LatLng point) {
    final lat0 = center.latitude;
    final lng0 = center.longitude;
    final dLat = point.latitude - lat0;
    final dLng = point.longitude - lng0;
    // Simple planar approximation with longitude scaled by cos(latitude).
    final scale = math.cos(lat0 * (math.pi / 180.0));
    final x = dLng * scale;
    final y = dLat;
    return x * x + y * y;
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
    // Approx conversion: 1 deg latitude ~ 111 km.
    final degLat = radiusKm / 111.0;
    final cosLat = math.cos(center.latitude * (math.pi / 180.0)).abs();
    final safeCosLat = cosLat < 0.0001 ? 0.0001 : cosLat;
    final degLng = radiusKm / (111.0 * safeCosLat);

    double clampLat(double v) => v.clamp(-90.0, 90.0);
    double clampLng(double v) => v.clamp(-180.0, 180.0);

    final sw = LatLng(
      clampLat(center.latitude - degLat),
      clampLng(center.longitude - degLng),
    );
    final ne = LatLng(
      clampLat(center.latitude + degLat),
      clampLng(center.longitude + degLng),
    );

    return LatLngBounds(southwest: sw, northeast: ne);
  }

  LatLngBounds _mergeBounds(LatLngBounds a, LatLngBounds b) {
    final sw = LatLng(
      math.min(a.southwest.latitude, b.southwest.latitude),
      math.min(a.southwest.longitude, b.southwest.longitude),
    );
    final ne = LatLng(
      math.max(a.northeast.latitude, b.northeast.latitude),
      math.max(a.northeast.longitude, b.northeast.longitude),
    );
    return LatLngBounds(southwest: sw, northeast: ne);
  }

  Future<void> _handleIndependentHouseTapped(
    MapPropertyFeature feature, {
    required LatLng target,
    required double zoom,
  }) async {
    _closePlotPanel();

    // Save the pre-tap camera so closing the panel can restore it.
    await _captureCameraBeforePropertyFocus();

    _updateState(() {
      _selectedProperty = feature;
      _selectedPropertyHighlightPolygons =
          _buildSelectedPropertyHighlightPolygons(feature);
    });

    unawaited(_refreshMarkerSelectionStyles());

    await _refreshIndependentHouseCarouselCandidates(anchor: feature);

    final candidates = _independentHousesCarousel.isNotEmpty
        ? _independentHousesCarousel
        : <MapPropertyFeature>[feature];

    final nextIndex = candidates.indexWhere(
      (p) => p.featureId.trim() == feature.featureId.trim(),
    );

    // Ensure carousel controller exists and is aligned to selected item.
    _independentHouseCarouselController?.dispose();
    _independentHouseCarouselController = PageController(
      initialPage: (nextIndex >= 0 ? nextIndex : 0) + 1,
      viewportFraction: 0.92,
    );

    _ensurePropertyMediaLoaded(feature);
    await _focusPropertyOnMap(target: target, zoom: zoom);
  }

  double _propertyCarouselHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // Keep it compact so the map remains usable and markers above the card
    // remain tappable.
    final target = h * 0.24;
    return target.clamp(190.0, 250.0);
  }

  Widget _buildIndependentHouseCarouselPanel() {
    final items = _independentHousesCarousel;
    if (items.isEmpty) {
      // Fallback for rare cases where selection exists but viewport list isn't ready.
      return PropertyDetailsPanel(
        key: ValueKey(
          'property:${_selectedProperty!.propertyType.trim()}:${_selectedProperty!.featureId.trim()}',
        ),
        feature: _selectedProperty!,
        imageUrls: _selectedPropertyMediaUrls,
        isLoadingImages: _isSelectedPropertyMediaLoading,
        imagesError: _selectedPropertyMediaError,
        isSaved: _isFeatureSaved(_selectedProperty!),
        isSaving: _isFeatureSaving(_selectedProperty!),
        onToggleSaved: () => unawaited(_toggleFeatureSaved(_selectedProperty!)),
        outerPadding: const EdgeInsets.fromLTRB(4, 0, 6, 8),
        onOpenDetails: () => _openPropertyDetails(_selectedProperty!),
        onClose: _closePropertyPanel,
      );
    }

    if (items.length == 1) {
      final feature = items.first;
      final key = _propertyMediaCacheKey(feature);
      final cached = key == null ? null : _propertyMediaCache[key];
      return PropertyDetailsPanel(
        key: ValueKey(
          'property:${feature.propertyType.trim()}:${feature.featureId.trim()}',
        ),
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

    final controller = _independentHouseCarouselController ??
        PageController(
          initialPage:
              (_activeIndependentHouseIndex.clamp(0, items.length - 1)) + 1,
          viewportFraction: 0.92,
        );
    _independentHouseCarouselController ??= controller;

    final pageCount = _carouselPageCount(items.length);

    return SizedBox(
      height: _propertyCarouselHeight(context),
      child: PageView.builder(
        controller: controller,
        itemCount: pageCount,
        padEnds: true,
        onPageChanged: (index) {
          if (!mounted) return;

          // Swiping focuses the map which triggers camera idle -> viewport fetch.
          // Suppress carousel refresh briefly to avoid re-sorting/replacing the
          // list mid-transition (can cause a one-frame mismatch/blink).
          _independentHouseCarouselRefreshSuppressedUntil =
              DateTime.now().add(const Duration(milliseconds: 900));

          final itemIndex = _itemIndexFromCarouselPage(index, items.length);
          final next = items[itemIndex];
          _updateState(() {
            _activeIndependentHouseIndex = itemIndex;
            _selectedProperty = next;
            _selectedPropertyHighlightPolygons =
                _buildSelectedPropertyHighlightPolygons(next);
          });

          unawaited(_refreshMarkerSelectionStyles());

          _ensurePropertyMediaLoaded(next);

          final center = next.centerPoint;
          final suppressFocus = _suppressCarouselFocusOnce;
          if (suppressFocus) {
            _suppressCarouselFocusOnce = false;
          } else if (center != null) {
            unawaited(_focusPropertyOnMap(target: center, zoom: 20.0));
          }

          // Loop correction: when user swipes onto a sentinel page, jump to the
          // corresponding real page without animation.
          if (index == 0 || index == pageCount - 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final c = _independentHouseCarouselController;
              if (!mounted || c == null || !c.hasClients) return;
              if (items.isEmpty) return;

              final target = (index == 0) ? items.length : 1;
              if (c.page?.round() != target) {
                _suppressCarouselFocusOnce = true;
                c.jumpToPage(target);
              }
            });
          }
        },
        itemBuilder: (context, index) {
          final itemIndex = _itemIndexFromCarouselPage(index, items.length);
          final feature = items[itemIndex];
          final key = _propertyMediaCacheKey(feature);
          final cached = key == null ? null : _propertyMediaCache[key];

          // Preload neighbors for smoother swiping.
          if (itemIndex == _activeIndependentHouseIndex) {
            _ensurePropertyMediaLoaded(feature);
            final n = items.length;
            final prev = items[(itemIndex - 1 + n) % n];
            final next = items[(itemIndex + 1) % n];
            _ensurePropertyMediaLoaded(prev);
            _ensurePropertyMediaLoaded(next);
          }

          return PropertyDetailsPanel(
            key: ValueKey(
              'property:${feature.propertyType.trim()}:${feature.featureId.trim()}',
            ),
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
        },
      ),
    );
  }
}
