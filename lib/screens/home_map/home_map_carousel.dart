part of '../home_map_screen.dart';

extension _HomeMapCarousel on _HomeMapScreenState {
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

  List<MapPropertyFeature> _sortedIndependentHousesForViewport(
    MapViewportResponse response,
  ) {
    final center = _lastCameraPosition.target;
    final houses = response.properties
        .where((p) => p.propertyType.trim() == 'IndependentHouse')
        .toList(growable: false);

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

    return houses;
  }

  Future<void> _handleIndependentHouseTapped(
    MapPropertyFeature feature, {
    required LatLng target,
    required double zoom,
  }) async {
    _closePlotPanel();

    // Build a viewport-only carousel list.
    final candidates = _independentHousesInView.isNotEmpty
        ? _independentHousesInView
        : <MapPropertyFeature>[feature];

    var nextIndex = candidates.indexWhere(
      (p) => p.featureId.trim() == feature.featureId.trim(),
    );
    if (nextIndex < 0) nextIndex = 0;

    _updateState(() {
      _selectedProperty = feature;
      _activeIndependentHouseIndex = nextIndex;
    });

    // Ensure carousel controller exists and is aligned to selected item.
    _independentHouseCarouselController?.dispose();
    _independentHouseCarouselController = PageController(
      initialPage: nextIndex,
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
    final items = _independentHousesInView;
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
        padEnds: false,
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
