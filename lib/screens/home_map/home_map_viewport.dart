part of '../home_map_screen.dart';

extension _HomeMapViewport on _HomeMapScreenState {
  void _setViewportLoading(bool value) {
    if (!mounted) return;

    // Small delay avoids spinner flicker on fast cache hits.
    if (value) {
      _viewportLoadingTimer?.cancel();
      _viewportLoadingTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        _updateState(() => _isViewportLoading = true);
      });
      return;
    }

    _viewportLoadingTimer?.cancel();
    if (_isViewportLoading) {
      _updateState(() => _isViewportLoading = false);
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
    final isAuthenticated = token != null && token.trim().isNotEmpty;

    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    final selectedType = _selectedPropertyType?.trim();
    final propertyTypes = (selectedType == null || selectedType.isEmpty)
        ? <String>[]
        : <String>[selectedType];

    final expandedBounds = _expandBounds(bounds, _overlayRetentionMultiplier);

    final signature = _buildViewportSignature(
      expandedBounds,
      zoom,
      propertyTypes,
      isAuthenticated,
      clientFilters: _clientFilterSignature(),
    );
    if (signature == _lastViewportSignature) {
      return;
    }
    _lastViewportSignature = signature;

    final cached = _tryGetCachedViewport(signature);
    if (cached != null) {
      final selected = _selectedProperty;
      final nextSelectedHouseHighlight = (selected != null &&
              selected.propertyType.trim() == 'IndependentHouse')
          ? _buildSelectedIndependentHouseHighlightPolygons(
              selected,
              viewportPropertyByFeatureId: cached.propertyByFeatureId,
            )
          : const <Polygon>{};

      _updateState(() {
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
        _ownedLayoutIds = cached.ownedLayoutIds;
        _propertyByFeatureId = cached.propertyByFeatureId;
        _selectedIndependentHouseHighlightPolygons = nextSelectedHouseHighlight;
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

      final filteredResponse = _applyClientFilters(response);

      final rendered = _renderViewport(
        response: filteredResponse,
        zoom: _lastCameraPosition.zoom,
      );

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final propertyMarkers = await _buildPropertyMarkers(
        response: filteredResponse,
        zoom: _lastCameraPosition.zoom,
        pixelRatio: pixelRatio,
      );
      final labels = await _buildLabelMarkers(
        response: filteredResponse,
        zoom: _lastCameraPosition.zoom,
        pixelRatio: pixelRatio,
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

      final selected = _selectedProperty;
      final nextSelectedHouseHighlight = (selected != null &&
              selected.propertyType.trim() == 'IndependentHouse')
          ? _buildSelectedIndependentHouseHighlightPolygons(
              selected,
              viewportPropertyByFeatureId: merged.propertyByFeatureId,
            )
          : const <Polygon>{};

      _updateState(() {
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
        _ownedLayoutIds = merged.ownedLayoutIds;
        _propertyByFeatureId = merged.propertyByFeatureId;
        _selectedIndependentHouseHighlightPolygons = nextSelectedHouseHighlight;
      });

      if (_selectedProperty?.propertyType.trim() == 'IndependentHouse') {
        _scheduleIndependentHouseCarouselRefresh();
      }
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
}
