part of '../home_map_screen.dart';

extension _HomeMapSelection on _HomeMapScreenState {
  Future<void> _onMyPropertyDeleted(MyPropertyListItem item) async {
    final id = item.id.trim();
    if (id.isNotEmpty) {
      final selected = _selectedProperty;
      if (selected != null) {
        final selectedId = selected.propertyId.trim();
        final selectedFeatureId = selected.featureId.trim();
        if (selectedId == id || selectedFeatureId == id) {
          _closePropertyPanel();
        }
      }
    }

    _viewportCache.clear();
    _lastViewportSignature = null;
    await _fetchViewport();
  }

  Future<void> _moveCameraTo(LatLng target, String label, double zoom) async {
    if (_mapController == null) return;
    await _animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );

    if (!mounted) return;
    final safeLabel = label.trim().isEmpty ? 'Selected place' : label.trim();
    ToastMessage.show(context, safeLabel);

    // Auto popup nearby layouts after selecting a place (match web behavior).
    unawaited(_openNearbyLayoutsPopup(anchor: target));
  }

  Future<void> _onMyPropertySelected(MyPropertyListItem item) async {
    final center = item.centerPoint;
    if (center == null) {
      if (!mounted) return;
      ToastMessage.show(context, 'Location not available for this property');
      return;
    }

    final token = AuthScope.of(context).session?.token;
    final id = item.id.trim();
    MapPropertyFeature? matchedFeature;
    if (id.isNotEmpty) {
      for (final feature in _propertyByFeatureId.values) {
        final featureId = feature.featureId.trim();
        final propertyId = feature.propertyId.trim();
        if (featureId == id || propertyId == id) {
          matchedFeature = feature;
          break;
        }
      }
    }

    if (matchedFeature == null && id.isNotEmpty) {
      final rawType = item.propertyType.trim();
      final normalizedType = rawType.replaceAll(RegExp(r'\s+'), '');
      final typeFilter = normalizedType.isNotEmpty ? normalizedType : rawType;

      Future<void> tryViewportLookup({
        required double delta,
        List<String>? propertyTypes,
      }) async {
        final nearBounds = LatLngBounds(
          southwest: LatLng(center.latitude - delta, center.longitude - delta),
          northeast: LatLng(center.latitude + delta, center.longitude + delta),
        );

        final response = await _mapApi.getViewport(
          bounds: nearBounds,
          zoom: 18.0,
          propertyTypes: propertyTypes,
          bearerToken: token,
        );

        for (final feature in response.properties) {
          final featureId = feature.featureId.trim();
          final propertyId = feature.propertyId.trim();
          if (featureId == id || propertyId == id) {
            matchedFeature = feature;
            break;
          }
        }
      }

      try {
        await tryViewportLookup(
          delta: 0.0025,
          propertyTypes: typeFilter.isNotEmpty ? <String>[typeFilter] : null,
        );
      } catch (_) {
        // Best-effort only; fallback continues below.
      }

      if (matchedFeature == null) {
        try {
          await tryViewportLookup(
            delta: 0.01,
            propertyTypes: null,
          );
        } catch (_) {
          // Best-effort only; fallback continues below.
        }
      }
    }

    PropertyDetail? detail;
    if (token != null && token.trim().isNotEmpty) {
      final featureSnapshot = matchedFeature;
      final needsDetail = featureSnapshot == null ||
          (featureSnapshot.boundaryGeoJson == null ||
              featureSnapshot.boundaryGeoJson!.trim().isEmpty) ||
          (featureSnapshot.centerGeoJson == null ||
              featureSnapshot.centerGeoJson!.trim().isEmpty);
      if (needsDetail && id.isNotEmpty) {
        try {
          detail = await _mapApi.getPropertyDetail(
            propertyId: id,
            bearerToken: token,
          );
        } catch (_) {
          // Best-effort; fallback to viewport data if available.
        }
      }
    }

    MapPropertyFeature? effectiveFeature;
    final featureSnapshot = matchedFeature;
    if (featureSnapshot != null) {
      if (detail != null &&
          (featureSnapshot.boundaryGeoJson == null ||
              featureSnapshot.boundaryGeoJson!.trim().isEmpty ||
              featureSnapshot.centerGeoJson == null ||
              featureSnapshot.centerGeoJson!.trim().isEmpty)) {
        effectiveFeature = MapPropertyFeature(
          propertyId: featureSnapshot.propertyId,
          featureId: featureSnapshot.featureId,
          propertyType: featureSnapshot.propertyType,
          name: featureSnapshot.name,
          isOwnedByCurrentUser: featureSnapshot.isOwnedByCurrentUser,
          listingType: featureSnapshot.listingType,
          boundaryGeoJson:
              (detail.propertyBoundaryGeoJson?.trim().isNotEmpty ?? false)
                  ? detail.propertyBoundaryGeoJson
                  : featureSnapshot.boundaryGeoJson,
          centerGeoJson: (detail.centerPointGeoJson?.trim().isNotEmpty ?? false)
              ? detail.centerPointGeoJson
              : featureSnapshot.centerGeoJson,
          metadata: featureSnapshot.metadata,
        );
      } else {
        effectiveFeature = featureSnapshot;
      }
    } else if (detail != null) {
      effectiveFeature = MapPropertyFeature(
        propertyId: item.id,
        featureId: item.id,
        propertyType: item.propertyType,
        name: item.name,
        isOwnedByCurrentUser: true,
        listingType: null,
        boundaryGeoJson: detail.propertyBoundaryGeoJson,
        centerGeoJson: detail.centerPointGeoJson,
        metadata: <String, String?>{
          'location': item.locationLabel,
        },
      );
    }

    _closeAnyPanel();

    if (effectiveFeature != null) {
      final type = effectiveFeature.propertyType.trim();
      final isLayout = type == 'Layout';

      final rawPrice = _getMetadataValue(
        effectiveFeature.metadata,
        const <String>['price', 'listingPrice', 'salePrice', 'amount'],
      );
      final isPriceEligible = const <String>[
        'IndependentHouse',
        'CommercialSpace',
        'Land',
        'ApartmentFlat',
        'IndividualPlots',
      ].contains(type);

      final priceBadgeLabel = (isPriceEligible && rawPrice != null)
          ? _formatPriceBadgeLabel(rawPrice)
          : null;

      LatLng? focusCenter;
      double? focusZoom;
      if (priceBadgeLabel != null || isLayout) {
        final polygons =
            GeoJson.tryParsePolygons(effectiveFeature.boundaryGeoJson);
        final points = polygons.firstWhere(
          (p) => p.length >= 3,
          orElse: () => const <LatLng>[],
        );
        if (points.isNotEmpty) {
          focusCenter = _centerOfBounds(_boundsFromPoints(points));
        }
        focusCenter ??= effectiveFeature.centerPoint ?? center;
        focusZoom = isLayout
            ? _layoutFocusZoomTarget
            : _priceBadgeFocusZoomTarget(type);
      }

      if (!isLayout && focusZoom == null) {
        focusCenter = effectiveFeature.centerPoint ?? center;
        focusZoom = _priceBadgeFocusZoomTarget(type);
      }

      final target = focusCenter ?? effectiveFeature.centerPoint ?? center;
      final zoom = focusZoom ?? _priceBadgeFocusZoomTarget(type);

      if (type == 'IndependentHouse') {
        await _handleIndependentHouseTapped(
          effectiveFeature,
          target: target,
          zoom: zoom,
        );
      } else if (isLayout) {
        await _focusPropertyOnMap(
          target: target,
          zoom: zoom,
        );
      } else {
        await _handlePropertyTapped(
          effectiveFeature,
          target: target,
          zoom: zoom,
        );
      }
    } else {
      await _focusPropertyOnMap(target: center, zoom: 18.0);
    }

    if (!mounted) return;
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraIdle() {
    if (_mapController == null) return;

    // Camera movement finished; treat subsequent gestures as user-driven.
    _isProgrammaticCameraMove = false;

    _viewportDebounceTimer?.cancel();
    _viewportDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      await _fetchViewport();
    });

    if (_selectedProperty?.propertyType.trim() == 'IndependentHouse') {
      _scheduleIndependentHouseCarouselRefresh();
    }
  }

  void _onCameraMoveStarted() {
    // `onCameraMoveStarted` fires for both programmatic and user-gesture moves.
    // We only care about detecting manual camera changes after a property tap.
    if (_isProgrammaticCameraMove) return;
    if (_selectedProperty == null) return;
    if (_cameraBeforePropertyFocus == null) return;
    _userMovedCameraSincePropertyFocus = true;
  }

  Future<void> _captureCameraBeforePropertyFocus() async {
    final controller = _mapController;
    final base = _lastCameraPosition;

    double zoom;
    try {
      zoom = controller == null ? base.zoom : await controller.getZoomLevel();
    } catch (_) {
      zoom = base.zoom;
    }

    _cameraBeforePropertyFocus = CameraPosition(
      target: base.target,
      zoom: zoom,
      bearing: base.bearing,
      tilt: base.tilt,
    );
    _userMovedCameraSincePropertyFocus = false;
  }

  Future<void> _animateCamera(CameraUpdate update) async {
    final controller = _mapController;
    if (controller == null) return;
    _isProgrammaticCameraMove = true;
    await controller.animateCamera(update);
  }

  Future<void> _moveCamera(CameraUpdate update) async {
    final controller = _mapController;
    if (controller == null) return;
    _isProgrammaticCameraMove = true;
    await controller.moveCamera(update);
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

    final shouldRestoreCamera = _cameraBeforePropertyFocus != null &&
        !_userMovedCameraSincePropertyFocus;
    final restoreCameraPosition =
        shouldRestoreCamera ? _cameraBeforePropertyFocus : null;

    setState(() {
      _selectedProperty = null;
      _selectedPropertyMediaUrls = null;
      _isSelectedPropertyMediaLoading = false;
      _selectedPropertyMediaError = null;
      _independentHousesCarousel = const <MapPropertyFeature>[];
      _activeIndependentHouseIndex = 0;
      _selectedPropertyHighlightPolygons = const <Polygon>{};

      // Reset restore tracking.
      _cameraBeforePropertyFocus = null;
      _userMovedCameraSincePropertyFocus = false;
    });

    // Cancel any in-flight media fetch.
    _propertyMediaSeq++;

    _independentHouseCarouselDebounce?.cancel();
    _independentHouseCarouselRequestSeq++;

    _independentHouseCarouselController?.dispose();
    _independentHouseCarouselController = null;

    // Update marker badge colors back to default.
    unawaited(_refreshMarkerSelectionStyles());

    if (restoreCameraPosition != null && _mapController != null) {
      // Defer until after rebuild so the map is ready to animate.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mapController == null) return;
        unawaited(
          _moveCamera(
            CameraUpdate.newCameraPosition(restoreCameraPosition),
          ),
        );
      });
    }
  }

  void _closeAnyPanel() {
    _closePlotPanel();
    _closePropertyPanel();
  }

  Future<void> _handlePropertyTapped(
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

      // Only IndependentHouse uses the special carousel panel.
      if (feature.propertyType.trim() != 'IndependentHouse') {
        _independentHousesCarousel = const <MapPropertyFeature>[];
        _activeIndependentHouseIndex = 0;
        _independentHouseCarouselDebounce?.cancel();
        _independentHouseCarouselRequestSeq++;
        _independentHouseCarouselController?.dispose();
        _independentHouseCarouselController = null;
      }
    });

    unawaited(_refreshMarkerSelectionStyles());
    _ensurePropertyMediaLoaded(feature);
    await _focusPropertyOnMap(target: target, zoom: zoom);
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

  Set<Polygon> _buildSelectedPropertyHighlightPolygons(
    MapPropertyFeature feature, {
    Map<String, MapPropertyFeature>? viewportPropertyByFeatureId,
  }) {
    final type = feature.propertyType.trim();
    if (type.isEmpty || type == 'Layout') {
      return const <Polygon>{};
    }

    final featureId = feature.featureId.trim();
    final lookup = viewportPropertyByFeatureId ?? _propertyByFeatureId;
    final source =
        featureId.isNotEmpty ? (lookup[featureId] ?? feature) : feature;

    final polygons = GeoJson.tryParsePolygons(source.boundaryGeoJson);
    if (polygons.isEmpty) return const <Polygon>{};

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    final style = _propertyStyleForType(type);
    final baseStrokeWidth =
        _adjustStrokeWidthForZoom(zoom, _propertyBaseStrokeWidth);
    final strokeWidth = baseStrokeWidth + _selectedPropertyStrokeWidthBump;
    final outlineStrokeWidth =
        strokeWidth + _selectedPropertyOutlineStrokeWidthExtra;
    final fillOpacity = _adjustFillOpacityForZoom(
      zoom,
      (_propertyBaseFillOpacity + _selectedPropertyFillOpacityBump),
    );

    final id = source.featureId.trim();
    final next = <Polygon>{};
    for (var i = 0; i < polygons.length; i++) {
      final points = polygons[i];
      if (points.length < 3) continue;

      // Glow/outline beneath the main highlight.
      next.add(
        Polygon(
          polygonId: PolygonId('prop-selected-glow:$type:$id:$i'),
          points: points,
          strokeWidth: outlineStrokeWidth,
          strokeColor: _selectedPropertyOutlineStroke
              .withOpacity(_selectedPropertyOutlineOpacity),
          fillColor: Colors.transparent,
          consumeTapEvents: false,
          zIndex: _selectedPropertyOutlineZIndex,
        ),
      );

      next.add(
        Polygon(
          polygonId: PolygonId('prop-selected:$type:$id:$i'),
          points: points,
          strokeWidth: strokeWidth,
          strokeColor: style.stroke.withOpacity(_selectedPropertyStrokeOpacity),
          fillColor: style.fill.withOpacity(fillOpacity),
          consumeTapEvents: false,
          zIndex: _selectedPropertyZIndex,
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

    await _animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }
}
