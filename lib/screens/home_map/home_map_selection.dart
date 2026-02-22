part of '../home_map_screen.dart';

extension _HomeMapSelection on _HomeMapScreenState {
  Future<void> _onShortlistedPropertySelected(SavedProperty saved) async {
    _safeSetState(() {
      _hasSelectedPlace = true;
    });

    final p = saved.property;
    final center = p.centerPoint;
    if (center == null) {
      if (!mounted) return;
      ToastMessage.show(context, 'Location not available for this property');
      return;
    }

    final token = AuthScope.of(context).session?.token;
    final id =
        saved.propertyId.trim().isEmpty ? p.id.trim() : saved.propertyId.trim();

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

    final rawType = (p.propertyTypeName ?? '').trim();
    final normalizedType = rawType.replaceAll(RegExp(r'\s+'), '');
    final typeFilter = normalizedType.isNotEmpty ? normalizedType : rawType;

    if (matchedFeature == null && id.isNotEmpty) {
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

    final name = p.name.trim().isEmpty
        ? (p.propertyTypeName?.trim().isEmpty ?? true
            ? 'Property'
            : p.propertyTypeName!.trim())
        : p.name.trim();

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
        propertyId: id,
        featureId: id,
        propertyType: rawType,
        name: name,
        isOwnedByCurrentUser: false,
        listingType: null,
        boundaryGeoJson: detail.propertyBoundaryGeoJson,
        centerGeoJson: detail.centerPointGeoJson,
        metadata: <String, String?>{
          'location': p.locationLabel,
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

      if (isLayout) {
        await _focusPropertyOnMap(
          target: target,
          zoom: zoom,
          boundaryGeoJson: effectiveFeature.boundaryGeoJson,
        );
      } else {
        // IndependentHouse, Land, CommercialSpace, ApartmentFlat - all use carousel
        await _handleCarouselPropertyTapped(
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

    _safeSetState(() {
      _hasSelectedPlace = true;
    });

    // Reset viewport result flag so the "No listings here yet" empty-state
    // does not flash while we wait for the viewport response at the new
    // location.
    _hasViewportResult = false;
    _isEmptyStateDismissed = false;
    _emptyStateDismissTimer?.cancel();
    _emptyStateDismissTimer = null;
    _triggeredByPlaceSearch = true;

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

  Future<void> _moveCameraToFromShortlist(
    LatLng target,
    String label,
    double zoom,
  ) async {
    if (_mapController == null) return;

    _safeSetState(() {
      _hasSelectedPlace = true;
    });

    // Reset so the empty-state popup does not flash before the viewport
    // response arrives at the new location.
    _hasViewportResult = false;
    _isEmptyStateDismissed = false;
    _emptyStateDismissTimer?.cancel();
    _emptyStateDismissTimer = null;
    _triggeredByPlaceSearch = true;

    await _animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );

    if (!mounted) return;
    final safeLabel = label.trim().isEmpty ? 'Selected place' : label.trim();
    ToastMessage.show(context, safeLabel);
  }

  Future<void> _onMyPropertySelected(MyPropertyListItem item) async {
    _safeSetState(() {
      _hasSelectedPlace = true;
    });

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

      if (isLayout) {
        await _focusPropertyOnMap(
          target: target,
          zoom: zoom,
          boundaryGeoJson: effectiveFeature.boundaryGeoJson,
        );
      } else {
        // IndependentHouse, Land, CommercialSpace, ApartmentFlat - all use carousel
        await _handleCarouselPropertyTapped(
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
    // Check if IP location was fetched before controller was ready
    _tryMoveToIpLocation();
  }

  void _tryMoveToIpLocation() {
    final pending = _pendingIpLocation;
    final controller = _mapController;
    if (pending != null && controller != null && !_hasMovedToIpLocation) {
      _hasMovedToIpLocation = true;
      _pendingIpLocation = null;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(pending, _initialCameraPosition.zoom),
      );
    }
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

    // User manually panned/zoomed — hide the "No listings" empty state.
    _triggeredByPlaceSearch = false;

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
    _safeSetState(() {
      _selectedPlot = plot;
      _selectedPlotHighlightPolygons =
          _buildSelectedPlotHighlightPolygons(plot);
      // Clear deep-link focus once user taps (transitions to full selection).
      _focusedPlotIdFromDeepLink = null;
    });

    // Center the plot after selection so users immediately see what's selected.
    unawaited(_focusPlotOnMap(plot));
  }

  void _closePlotPanel() {
    if (!mounted) return;
    if (_selectedPlot == null) return;
    // Cancel any in-flight focus animation/clamp for the previous selection.
    _plotFocusSeq++;
    _safeSetState(() {
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

    _safeSetState(() {
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

  Set<Polygon> _buildSelectedPlotHighlightPolygons(MapPlotFeature plot) {
    final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
    if (polygons.isEmpty) return const <Polygon>{};

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    final kind = _plotElementKind(plot);
    final isSold = plot.layoutId != null && _isSoldPlot(plot);
    final isBooked = !isSold && plot.layoutId != null && _isBookedPlot(plot);

    Color stroke;
    Color fill;
    int baseStrokeWidth;
    double fillOpacity;

    if (kind == 'road') {
      stroke = _roadStroke;
      fill = _roadFill;
      baseStrokeWidth = _roadStrokeWidth;
      fillOpacity = _roadFillOpacity;
    } else if (kind == 'boundary') {
      stroke = _layoutBoundaryStroke;
      fill = _layoutBoundaryFill;
      baseStrokeWidth = _layoutBoundaryStrokeWidth;
      fillOpacity =
          zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
    } else if (isSold) {
      stroke = _soldPlotStroke;
      fill = _soldPlotFill;
      baseStrokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
      fillOpacity = _soldPlotFillOpacity;
    } else if (isBooked) {
      stroke = _bookedPlotStroke;
      fill = _bookedPlotFill;
      baseStrokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
      fillOpacity = _bookedPlotFillOpacity;
    } else {
      stroke = _plotStroke;
      fill = _plotFill;
      baseStrokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
      fillOpacity = _plotFillOpacity;
    }

    final strokeWidth = baseStrokeWidth + _selectedPlotStrokeWidthBump;
    final outlineStrokeWidth =
        strokeWidth + _selectedPlotOutlineStrokeWidthExtra;

    final next = <Polygon>{};
    for (var i = 0; i < polygons.length; i++) {
      final points = polygons[i];
      if (points.length < 3) continue;
      next.add(
        Polygon(
          polygonId: PolygonId('plot-selected-outline:${plot.plotId}:$i'),
          points: points,
          strokeWidth: outlineStrokeWidth,
          strokeColor: _selectedPlotOutlineStroke
              .withOpacity(_selectedPlotOutlineOpacity),
          fillColor: Colors.transparent,
          consumeTapEvents: false,
          zIndex: _selectedPlotOutlineZIndex,
        ),
      );

      next.add(
        Polygon(
          polygonId: PolygonId('plot-selected:${plot.plotId}:$i'),
          points: points,
          strokeWidth: strokeWidth,
          strokeColor: stroke.withOpacity(1.0),
          fillColor: fill.withOpacity(fillOpacity),
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
    if (polygons.isEmpty) {
      return const <Polygon>{};
    }

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
    String? boundaryGeoJson,
  }) async {
    final controller = _mapController;
    if (controller == null) return;

    if (boundaryGeoJson != null && boundaryGeoJson.isNotEmpty) {
      final allPoints = <LatLng>[];
      final polygons = GeoJson.tryParsePolygons(boundaryGeoJson);
      for (final poly in polygons) {
        allPoints.addAll(poly);
      }

      if (allPoints.length >= 3) {
        final bounds = _boundsFromPoints(allPoints);
        final latSpan = bounds.northeast.latitude - bounds.southwest.latitude;
        final lngSpan = bounds.northeast.longitude - bounds.southwest.longitude;

        // Only use bounds-based camera for polygons large enough to
        // potentially overflow the screen at the requested zoom.
        // ~0.0005° ≈ 55 m — well below the visible area at any default
        // property zoom (18.5–20), so anything above this threshold
        // genuinely risks overflowing.  Small polygons skip straight to
        // the normal center+zoom animation (no double-animation).
        if (latSpan > 0.0005 || lngSpan > 0.0005) {
          // Expand bounds to account for the property details panel at
          // the bottom (~35 % of screen) and search bar at top (~12 %).
          final adjustedBounds = LatLngBounds(
            southwest: LatLng(
              bounds.southwest.latitude - latSpan * 0.55,
              bounds.southwest.longitude,
            ),
            northeast: LatLng(
              bounds.northeast.latitude + latSpan * 0.15,
              bounds.northeast.longitude,
            ),
          );

          await _animateCamera(
            CameraUpdate.newLatLngBounds(adjustedBounds, 30),
          );
          return;
        }
      }
    }

    await _animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  Future<void> _focusNewlyCreatedPropertyOnMap(
    PendingMapFocusRequest request,
  ) async {
    final controller = _mapController;
    if (controller == null) return;

    final points = request.boundaryPoints;
    if (points.length < 3) return;

    final bounds = _boundsFromPoints(points);
    final center = _centerOfBounds(bounds);

    try {
      await _animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      // If bounds animation fails (rare), at least center the camera.
      await _focusPropertyOnMap(target: center, zoom: 18.0);
      return;
    }

    // Clamp zoom after bounds fit (Google Maps may overshoot max zoom briefly).
    double zoom;
    try {
      zoom = await controller.getZoomLevel();
    } catch (_) {
      zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    }

    const maxZoom = _selectedPlotMaxFocusZoom;
    if (zoom > maxZoom) {
      await _focusPropertyOnMap(target: center, zoom: maxZoom);
    }
  }

  /// Select a property that was opened from a deep link.
  ///
  /// This shows the bottom panel with property info. Since deep link properties
  /// may not have boundary/center coordinates, we only select without focusing.
  Future<void> _selectPropertyFromDeepLink(MapPropertyFeature feature) async {
    if (!mounted) return;

    _safeSetState(() {
      _hasSelectedPlace = true;
    });

    _closePlotPanel();

    // Contract the search overlay to show the property panel clearly.
    _searchOverlayKey.currentState?.contract();

    _updateState(() {
      _selectedProperty = feature;
      _selectedPropertyHighlightPolygons =
          _buildSelectedPropertyHighlightPolygons(feature);

      // Only IndependentHouse uses the carousel panel.
      if (feature.propertyType.trim() != 'IndependentHouse') {
        _independentHousesCarousel = const <MapPropertyFeature>[];
        _activeIndependentHouseIndex = 0;
        _independentHouseCarouselDebounce?.cancel();
        _independentHouseCarouselRequestSeq++;
      }
    });

    unawaited(_refreshMarkerSelectionStyles());
    _ensurePropertyMediaLoaded(feature);

    // If the feature has center coordinates, focus on them with the same zoom
    // level used when tapping a marker.
    final centerGeoJson = feature.centerGeoJson;
    if (centerGeoJson != null && centerGeoJson.isNotEmpty) {
      final center = GeoJson.tryParsePoint(centerGeoJson);
      if (center != null) {
        final zoom = _priceBadgeFocusZoomTarget(feature.propertyType);
        await _focusPropertyOnMap(
          target: center,
          zoom: zoom,
          boundaryGeoJson: feature.boundaryGeoJson,
        );
      }
    }
  }

  /// Focus a plot from a deep link.
  ///
  /// This moves camera to the plot center and sets up auto-selection
  /// so the plot panel opens when the viewport data loads.
  Future<void> _focusPlotFromDeepLink(PlotFocusData data) async {
    if (!mounted) return;

    _safeSetState(() {
      _hasSelectedPlace = true;
      _focusedPlotIdFromDeepLink = data.plotId;
      // Store pending data for auto-selection when viewport loads.
      _pendingPlotAutoSelect = data;
      _pendingPlotAutoSelectAt = DateTime.now();
    });

    // Contract search overlay to see the map.
    _searchOverlayKey.currentState?.contract();

    // Get coordinates - fetch if missing.
    double? lat = data.centerLatitude;
    double? lng = data.centerLongitude;

    if (lat == null || lng == null) {
      // Coordinates not available yet - fetch from API.
      final summary = await _fetchPlotShareSummary(
        data.layoutFeatureId,
        data.plotId,
      );
      if (summary != null) {
        lat = summary['centerLatitude'] as double?;
        lng = summary['centerLongitude'] as double?;
      }
    }

    // Move camera to plot center if available.
    if (lat != null && lng != null) {
      await _animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), _selectedPlotMaxFocusZoom),
      );
    }

    // Force viewport refresh to load plot data at the new camera position.
    unawaited(_fetchViewport());
  }

  /// Fetch plot share summary from the API.
  Future<Map<String, dynamic>?> _fetchPlotShareSummary(
    String layoutFeatureId,
    String plotId,
  ) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/share/plot/$layoutFeatureId/$plotId';

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DeepLink] fetch plot error: $e');
    }
    return null;
  }

  /// Auto-select a plot from a deep link when viewport data is available.
  ///
  /// This is called after viewport fetch completes. If there's a pending
  /// auto-select, find the matching plot and open the details panel.
  void _tryAutoSelectPlotFromDeepLink(List<MapPlotFeature> plots) {
    final pending = _pendingPlotAutoSelect;
    if (pending == null) return;

    // Expire after 10 seconds to avoid retrying indefinitely.
    final setAt = _pendingPlotAutoSelectAt;
    if (setAt != null && DateTime.now().difference(setAt).inSeconds > 10) {
      debugPrint(
        '[DeepLink] plot auto-select expired for ${pending.plotId}',
      );
      _pendingPlotAutoSelect = null;
      _pendingPlotAutoSelectAt = null;
      return;
    }

    // Find the plot by ID.
    MapPlotFeature? match;
    for (final plot in plots) {
      if (plot.plotId == pending.plotId) {
        match = plot;
        break;
      }
    }

    if (match == null) {
      // Don't clear pending — the camera animation may still be in progress
      // and a subsequent viewport fetch (triggered by onCameraIdle) will
      // include the target plot once the camera settles.
      debugPrint(
        '[DeepLink] plot ${pending.plotId} not found in viewport response, will retry',
      );
      return;
    }

    // Clear pending now that we've found the plot.
    _pendingPlotAutoSelect = null;
    _pendingPlotAutoSelectAt = null;

    // Select the plot (opens the bottom panel).
    _safeSetState(() {
      _selectedPlot = match;
      _selectedPlotHighlightPolygons =
          _buildSelectedPlotHighlightPolygons(match!);
      // Clear deep-link focus since we're now fully selected.
      _focusedPlotIdFromDeepLink = null;
    });
  }

  /// Focus a layout from a deep link.
  ///
  /// This fetches the layout boundary from the share API and animates
  /// the camera to focus on the layout.
  Future<void> _focusLayoutFromDeepLink(String layoutId) async {
    if (!mounted) return;

    _safeSetState(() {
      _hasSelectedPlace = true;
    });

    // Contract search overlay to see the map.
    _searchOverlayKey.currentState?.contract();

    // Fetch the layout share summary to get coordinates and boundary.
    final summary = await _fetchLayoutShareSummary(layoutId);
    if (summary == null) {
      return;
    }

    // Draw preview boundary if available.
    final boundaryGeoJson = summary['boundaryGeoJson'] as String?;
    if (boundaryGeoJson != null && boundaryGeoJson.isNotEmpty) {
      _drawLayoutPreviewPolygonIfAvailable(layoutId, boundaryGeoJson);
    }

    // Focus camera on the layout center.
    final lat = summary['centerLatitude'] as double?;
    final lng = summary['centerLongitude'] as double?;
    if (lat != null && lng != null) {
      await _focusPropertyOnMap(
        target: LatLng(lat, lng),
        zoom: _layoutFocusZoomTarget,
      );
    }

    // Trigger viewport refresh to load layout data.
    unawaited(_fetchViewport());
  }

  /// Fetch layout share summary from the API.
  Future<Map<String, dynamic>?> _fetchLayoutShareSummary(
    String layoutId,
  ) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/share/property/Layout/$layoutId';

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[DeepLink] layout fetch error: $e');
    }
    return null;
  }
}
