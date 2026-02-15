part of '../home_map_screen.dart';

extension _HomeMapViewport on _HomeMapScreenState {
  static const Duration _viewportFetchingMinVisible =
      Duration(milliseconds: 200);

  void _setViewportFetching(bool value) {
    if (!mounted) return;

    if (value) {
      _viewportFetchingHideTimer?.cancel();
      _viewportFetchingHideTimer = null;
      _viewportFetchingStartedAt = DateTime.now();
      if (_isViewportFetching) return;
      _updateState(() => _isViewportFetching = true);
      return;
    }

    final startedAt = _viewportFetchingStartedAt;
    final elapsed = startedAt == null
        ? _viewportFetchingMinVisible
        : DateTime.now().difference(startedAt);

    if (elapsed >= _viewportFetchingMinVisible) {
      _viewportFetchingHideTimer?.cancel();
      _viewportFetchingHideTimer = null;
      _viewportFetchingStartedAt = null;
      if (_isViewportFetching) {
        _updateState(() => _isViewportFetching = false);
      }
      return;
    }

    _viewportFetchingHideTimer?.cancel();
    _viewportFetchingHideTimer =
        Timer(_viewportFetchingMinVisible - elapsed, () {
      if (!mounted) return;
      _viewportFetchingHideTimer = null;
      _viewportFetchingStartedAt = null;
      if (_isViewportFetching) {
        _updateState(() => _isViewportFetching = false);
      }
    });
  }

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
      final nextSelectedHighlight = selected == null
          ? const <Polygon>{}
          : _buildSelectedPropertyHighlightPolygons(
              selected,
              viewportPropertyByFeatureId: cached.propertyByFeatureId,
            );

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
        _selectedPropertyHighlightPolygons = nextSelectedHighlight;
        _hasViewportResult = true;
        // Clear layout preview polygon (shown while viewport data was loading).
        _layoutPreviewPolygons = <Polygon>{};
      });

      // Also try auto-selecting a plot from a deep link when serving from cache.
      _tryAutoSelectPlotFromDeepLink(cached.plots);
      return;
    }

    final requestId = ++_viewportRequestSeq;

    _setViewportFetching(true);
    _setViewportLoading(true);

    try {
      final response = await _mapApi.getViewport(
        bounds: expandedBounds,
        zoom: zoom,
        propertyTypes: propertyTypes,
        bearerToken: token,
      );

      if (!mounted || requestId != _viewportRequestSeq) {
        return;
      }

      final perf = PerformanceLogger.instance;
      final renderTrace = await FirebasePerfService.startTrace(
        'viewport_render_pipeline',
        attributes: {
          'source': 'network',
        },
      );

      if (!mounted || requestId != _viewportRequestSeq) {
        await renderTrace?.stop();
        return;
      }

      _ViewportRenderCacheEntry rendered;
      Set<Marker> propertyMarkers;
      _LabelMarkerResult labels;
      MapViewportResponse filteredResponse;

      try {
        filteredResponse = _applyClientFilters(response);

        perf.startTimer('renderPolygons');
        rendered = _renderViewport(
          response: filteredResponse,
          zoom: zoom,
        );
        perf.stopTimer('renderPolygons');

        final pixelRatio = MediaQuery.of(context).devicePixelRatio;
        perf.startTimer('buildPropertyMarkers');
        propertyMarkers = await _buildPropertyMarkers(
          response: filteredResponse,
          zoom: zoom,
          pixelRatio: pixelRatio,
        );
        perf.stopTimer('buildPropertyMarkers');

        perf.startTimer('buildLabelMarkers');
        labels = await _buildLabelMarkers(
          response: filteredResponse,
          zoom: zoom,
          pixelRatio: pixelRatio,
        );
        perf.stopTimer('buildLabelMarkers');

        await perf.finishRequest();
        renderTrace?.putMetric(
            'properties_count', filteredResponse.properties.length);
        renderTrace?.putMetric('plots_count', filteredResponse.plots.length);
        renderTrace?.putMetric('markers_count', propertyMarkers.length);
        renderTrace?.putMetric(
            'plot_labels_count', labels.plotLabelMarkers.length);
      } finally {
        await renderTrace?.stop();
      }

      if (!mounted || requestId != _viewportRequestSeq) {
        return;
      }

      final merged = rendered.copyWith(
        markers: propertyMarkers,
        plotLabelMarkers: labels.plotLabelMarkers,
        roadLabelMarkers: labels.roadLabelMarkers,
        amenityLabelMarkers: labels.amenityLabelMarkers,
      );
      // Store raw plots so cached viewport paths can auto-select deep-linked
      // plots without a network round-trip.
      final mergedWithPlots = _ViewportRenderCacheEntry(
        markers: merged.markers,
        plotLabelMarkers: merged.plotLabelMarkers,
        roadLabelMarkers: merged.roadLabelMarkers,
        amenityLabelMarkers: merged.amenityLabelMarkers,
        layoutPolygons: merged.layoutPolygons,
        propertyPolygons: merged.propertyPolygons,
        plotPolygons: merged.plotPolygons,
        amenityPolygons: merged.amenityPolygons,
        roadPolygons: merged.roadPolygons,
        roadPolylines: merged.roadPolylines,
        ownedLayoutIds: merged.ownedLayoutIds,
        propertyByFeatureId: merged.propertyByFeatureId,
        plots: filteredResponse.plots,
        createdAt: merged.createdAt,
      );
      _putCachedViewport(signature, mergedWithPlots);

      final selected = _selectedProperty;
      final nextSelectedHighlight = selected == null
          ? const <Polygon>{}
          : _buildSelectedPropertyHighlightPolygons(
              selected,
              viewportPropertyByFeatureId: merged.propertyByFeatureId,
            );

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
        _selectedPropertyHighlightPolygons = nextSelectedHighlight;
        _hasViewportResult = true;
        // Clear layout preview polygon (shown while viewport data was loading).
        _layoutPreviewPolygons = <Polygon>{};
      });

      if (_selectedProperty?.propertyType.trim() == 'IndependentHouse') {
        _scheduleIndependentHouseCarouselRefresh();
      }

      // Auto-select plot from deep link if pending.
      _tryAutoSelectPlotFromDeepLink(filteredResponse.plots);

      _setViewportFetching(false);
      _setViewportLoading(false);
    } catch (e) {
      if (!mounted || requestId != _viewportRequestSeq) {
        return;
      }

      _setViewportFetching(false);
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
