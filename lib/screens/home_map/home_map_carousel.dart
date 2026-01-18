part of '../home_map_screen.dart';

extension _HomeMapCarousel on _HomeMapScreenState {
  void _scheduleIndependentHouseCarouselRefresh() {
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
    final requestId = ++_independentHouseCarouselRequestSeq;

    try {
      final response = await _mapApi.getViewport(
        bounds: expanded,
        zoom: carouselQueryZoom,
        propertyTypes: const <String>['IndependentHouse'],
        bearerToken: token,
      );

      if (!mounted || requestId != _independentHouseCarouselRequestSeq) {
        return;
      }

      final center = _lastCameraPosition.target;
      final houses = response.properties
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

      final selected = anchor ?? _selectedProperty;
      if (selected != null &&
          selected.propertyType.trim() == 'IndependentHouse') {
        final exists = houses.any(
          (p) => p.featureId.trim() == selected.featureId.trim(),
        );
        if (!exists) {
          houses.insert(0, selected);
        }
      }

      final nextIndex = selected == null
          ? 0
          : houses.indexWhere(
              (p) => p.featureId.trim() == selected.featureId.trim(),
            );

      _updateState(() {
        _independentHousesCarousel =
            List<MapPropertyFeature>.unmodifiable(houses);
        _activeIndependentHouseIndex = nextIndex >= 0 ? nextIndex : 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _independentHouseCarouselController;
        if (!mounted || c == null || !c.hasClients) return;
        final targetPage =
            _activeIndependentHouseIndex.clamp(0, houses.length - 1);
        if (c.page?.round() != targetPage) {
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

  Future<void> _handleIndependentHouseTapped(
    MapPropertyFeature feature, {
    required LatLng target,
    required double zoom,
  }) async {
    _closePlotPanel();

    _updateState(() {
      _selectedProperty = feature;
    });

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
      initialPage: (nextIndex >= 0 ? nextIndex : 0),
      viewportFraction: 0.88,
    );

    _ensurePropertyMediaLoaded(feature);
    await _focusPropertyOnMap(target: target, zoom: zoom);
  }

  double _propertyCarouselHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // Keep it compact so the map remains usable.
    final target = h * 0.28;
    return target.clamp(210.0, 280.0);
  }

  Widget _buildIndependentHouseCarouselPanel() {
    final items = _independentHousesCarousel;
    if (items.isEmpty) {
      // Fallback for rare cases where selection exists but viewport list isn't ready.
      return PropertyDetailsPanel(
        feature: _selectedProperty!,
        imageUrls: _selectedPropertyMediaUrls,
        isLoadingImages: _isSelectedPropertyMediaLoading,
        imagesError: _selectedPropertyMediaError,
        onOpenDetails: () => _openPropertyDetails(_selectedProperty!),
        onClose: _closePropertyPanel,
      );
    }

    if (items.length == 1) {
      final feature = items.first;
      final key = _propertyMediaCacheKey(feature);
      final cached = key == null ? null : _propertyMediaCache[key];
      return PropertyDetailsPanel(
        feature: feature,
        imageUrls: cached?.urls,
        isLoadingImages: cached?.isLoading ?? false,
        imagesError: cached?.error,
        onOpenDetails: () => _openPropertyDetails(feature),
        onClose: _closePropertyPanel,
      );
    }

    final controller = _independentHouseCarouselController ??
        PageController(
          initialPage: _activeIndependentHouseIndex.clamp(0, items.length - 1),
          viewportFraction: 0.88,
        );
    _independentHouseCarouselController ??= controller;

    return SizedBox(
      height: _propertyCarouselHeight(context),
      child: PageView.builder(
        controller: controller,
        itemCount: items.length,
        padEnds: true,
        onPageChanged: (index) {
          if (!mounted) return;
          final next = items[index];
          _updateState(() {
            _activeIndependentHouseIndex = index;
            _selectedProperty = next;
          });

          _ensurePropertyMediaLoaded(next);

          final center = next.centerPoint;
          if (center != null) {
            unawaited(_focusPropertyOnMap(target: center, zoom: 20.0));
          }
        },
        itemBuilder: (context, index) {
          final feature = items[index];
          final key = _propertyMediaCacheKey(feature);
          final cached = key == null ? null : _propertyMediaCache[key];

          // Preload neighbors for smoother swiping.
          if (index == _activeIndependentHouseIndex) {
            _ensurePropertyMediaLoaded(feature);
            if (index - 1 >= 0) _ensurePropertyMediaLoaded(items[index - 1]);
            if (index + 1 < items.length) {
              _ensurePropertyMediaLoaded(items[index + 1]);
            }
          }

          return PropertyDetailsPanel(
            feature: feature,
            imageUrls: cached?.urls,
            isLoadingImages: cached?.isLoading ?? false,
            imagesError: cached?.error,
            onOpenDetails: () => _openPropertyDetails(feature),
            onClose: _closePropertyPanel,
          );
        },
      ),
    );
  }
}
