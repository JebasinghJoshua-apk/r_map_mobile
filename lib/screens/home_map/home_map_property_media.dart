part of '../home_map_screen.dart';

extension _HomeMapPropertyMedia on _HomeMapScreenState {
  String? _propertyMediaCacheKey(MapPropertyFeature feature) {
    final t = feature.propertyType.trim();
    final id = feature.featureId.trim();
    if (t.isEmpty || id.isEmpty) return null;
    return '$t:$id';
  }

  void _openPropertyDetails(MapPropertyFeature feature) {
    if (!mounted) return;

    _dismissKeyboard();

    // Layouts have their own dedicated detail screen (fetches full data by
    // id), unlike the generic PropertyDetailScreen router used for other
    // property types.
    if (feature.propertyType.trim() == 'Layout') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LayoutDetailScreen(
            layoutId: feature.featureId.trim(),
            fallbackFeature: feature,
          ),
        ),
      );
      return;
    }

    final cacheKey = _propertyMediaCacheKey(feature);
    final cached = cacheKey == null ? null : _propertyMediaCache[cacheKey];
    final urls = cached?.urls;
    final isLoading = cached?.isLoading ?? false;
    final error = cached?.error;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          feature: feature,
          imageUrls: urls,
          isLoadingImages: isLoading,
          imagesError: error,
        ),
      ),
    );
  }

  void _ensurePropertyMediaLoaded(MapPropertyFeature feature) {
    final key = _propertyMediaCacheKey(feature);
    if (key == null) return;

    final existing = _propertyMediaCache[key];
    if (existing != null) {
      if (existing.isLoading) return;
      if (existing.urls != null) {
        // Cache hit: sync the legacy selected-property fields (they may
        // have been cleared by a prior panel close) instead of leaving
        // the panel with stale/empty image state.
        if (_selectedProperty?.featureId.trim() == feature.featureId.trim()) {
          _updateState(() {
            _selectedPropertyMediaUrls = existing.urls;
            _isSelectedPropertyMediaLoading = false;
            _selectedPropertyMediaError = existing.error;
          });
        }
        return;
      }
      // If we previously failed, allow retry on reselect.
    }

    final seq = ++_propertyMediaSeq;
    _propertyMediaCache[key] = _PropertyMediaCacheEntry(
      urls: null,
      isLoading: true,
      error: null,
      requestSeq: seq,
    );

    // Keep legacy selected-property fields in sync for current panel.
    if (_selectedProperty?.featureId.trim() == feature.featureId.trim()) {
      _updateState(() {
        _selectedPropertyMediaUrls = null;
        _isSelectedPropertyMediaLoading = true;
        _selectedPropertyMediaError = null;
      });
    }

    unawaited(_fetchPropertyMedia(feature, cacheKey: key, requestSeq: seq));
  }

  Future<void> _fetchPropertyMedia(
    MapPropertyFeature feature, {
    required String cacheKey,
    required int requestSeq,
  }) async {
    final propertyType = feature.propertyType.trim();
    final entityId = feature.featureId.trim();
    if (propertyType.isEmpty || entityId.isEmpty) {
      if (!mounted) return;
      final current = _propertyMediaCache[cacheKey];
      if (current == null || current.requestSeq != requestSeq) return;
      _updateState(() {
        _propertyMediaCache[cacheKey] = current.copyWith(
          urls: const <String>[],
          isLoading: false,
          error: 'Photos not available.',
        );
        if (_selectedProperty?.featureId.trim() == entityId) {
          _selectedPropertyMediaUrls = const <String>[];
          _isSelectedPropertyMediaLoading = false;
          _selectedPropertyMediaError = 'Photos not available.';
        }
      });
      return;
    }

    final token = AuthScope.of(context).session?.token;

    try {
      final images = await _mapApi.getPropertyMedia(
        propertyType: propertyType,
        entityId: entityId,
        bearerToken: token,
      );

      if (!mounted) return;
      final current = _propertyMediaCache[cacheKey];
      if (current == null || current.requestSeq != requestSeq) return;

      final urls = <String>[];
      for (final img in images) {
        final u = img.fileUrl.trim();
        if (u.isEmpty) continue;
        if (!urls.contains(u)) urls.add(u);
      }

      _updateState(() {
        _propertyMediaCache[cacheKey] = current.copyWith(
          urls: urls,
          isLoading: false,
          error: null,
        );

        if (_selectedProperty?.featureId.trim() == entityId) {
          _selectedPropertyMediaUrls = urls;
          _isSelectedPropertyMediaLoading = false;
          _selectedPropertyMediaError = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final current = _propertyMediaCache[cacheKey];
      if (current == null || current.requestSeq != requestSeq) return;
      _updateState(() {
        _propertyMediaCache[cacheKey] = current.copyWith(
          urls: const <String>[],
          isLoading: false,
          error: e.toString(),
        );
        if (_selectedProperty?.featureId.trim() == entityId) {
          _selectedPropertyMediaUrls = const <String>[];
          _isSelectedPropertyMediaLoading = false;
          _selectedPropertyMediaError = e.toString();
        }
      });
    }
  }
}
