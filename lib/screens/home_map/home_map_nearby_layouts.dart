part of '../home_map_screen.dart';

enum _NearbyLayoutsDialogCloseReason {
  manual,
}

extension _HomeMapNearbyLayouts on _HomeMapScreenState {
  static const double _nearbyLayoutsAutoRadiusKm = 50.0;
  String _formatNearbyDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  String? _layoutLocationLabel(NearbyPropertyCard item) {
    final addr = item.address.trim();
    final city = item.city.trim();

    if (addr.isNotEmpty) return addr;
    if (city.isNotEmpty) return city;
    return null;
  }

  String? _layoutAreaLabel(NearbyPropertyCard item) {
    final area = item.area?.trim();
    if (area != null && area.isNotEmpty) return area;
    return null;
  }

  String? _layoutPlotsLabel(NearbyPropertyCard item) {
    final count = item.plotsCount;
    if (count == null) return null;
    return '$count plots';
  }

  bool _isNearbyNew(DateTime createdAt) {
    final now = DateTime.now();
    return now.difference(createdAt).abs() <=
        _HomeMapScreenState._nearbyNewThreshold;
  }

  Future<void> _loadNearbyLayouts(
    LatLng anchor, {
    required int limit,
    double? radiusKm,
  }) async {
    final token = AuthScope.of(context).session?.token;
    _updateState(() {
      _nearbyLayoutsError = null;
    });

    try {
      final results = await _mapApi.getNearbyLayouts(
        anchor: anchor,
        limit: limit,
        radiusKm: radiusKm,
        bearerToken: token,
      );
      if (!mounted) return;
      _updateState(() {
        _nearbyLayouts = results;
      });
    } on MapApiException catch (ex) {
      if (!mounted) return;
      _updateState(() {
        _nearbyLayoutsError = ex.message;
        _nearbyLayouts = const <NearbyPropertyCard>[];
      });
    } catch (_) {
      if (!mounted) return;
      _updateState(() {
        _nearbyLayoutsError = 'Failed to load nearby layouts.';
        _nearbyLayouts = const <NearbyPropertyCard>[];
      });
    }
  }

  Future<void> _openNearbyLayoutsPopup({
    required LatLng anchor,
    bool showWhenEmpty = false,
    bool isManualOpen = false,
  }) async {
    if (_isNearbyLayoutsDialogOpen) {
      // Close any existing dialog via the root navigator.
      // Using a stored dialog BuildContext can crash during teardown
      // (Flutter framework assertion about dependencies being empty).
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }

    _dismissKeyboard();
    _closeAnyPanel();

    // Manual open should behave like auto-open by default:
    // show nearest 15 layouts within 50km.
    const baseRadiusKm = _nearbyLayoutsAutoRadiusKm;
    const limit = 15;
    final effectiveShowWhenEmpty = showWhenEmpty || isManualOpen;

    Future<void> load() async {
      await _loadNearbyLayouts(
        anchor,
        limit: limit,
        radiusKm: baseRadiusKm,
      );
    }

    // Fetch first; only show the popup after we have a response.
    await load();
    if (!mounted) return;
    final initialError = _nearbyLayoutsError;
    if (initialError != null && initialError.trim().isNotEmpty) {
      ToastMessage.show(context, initialError);
      return;
    }

    final initialItems = _nearbyLayouts ?? const <NearbyPropertyCard>[];
    if (initialItems.isEmpty && !effectiveShowWhenEmpty) return;

    _NearbyLayoutsDialogCloseReason? closeReason;
    try {
      _isNearbyLayoutsDialogOpen = true;
      closeReason = await showDialog<_NearbyLayoutsDialogCloseReason>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          var modalItems = _nearbyLayouts ?? const <NearbyPropertyCard>[];
          var modalError = _nearbyLayoutsError;
          var modalLoading = false;
          var activeRequestId = 0;

          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> refetchForQuery(String query) async {
                final requestId = ++activeRequestId;

                setModalState(() {
                  modalLoading = true;
                  modalError = null;
                });

                final token = AuthScope.of(context).session?.token;
                final trimmed = query.trim();
                final radius = trimmed.isEmpty ? baseRadiusKm : null;
                final effectiveQuery = trimmed.isEmpty ? null : trimmed;

                try {
                  final results = await _mapApi.getNearbyLayouts(
                    anchor: anchor,
                    limit: limit,
                    radiusKm: radius,
                    query: effectiveQuery,
                    bearerToken: token,
                  );
                  if (!mounted) return;
                  if (requestId != activeRequestId) return;
                  setModalState(() {
                    modalItems = results;
                  });
                } on MapApiException catch (ex) {
                  if (!mounted) return;
                  if (requestId != activeRequestId) return;
                  setModalState(() {
                    modalError = ex.message;
                    modalItems = const <NearbyPropertyCard>[];
                  });
                } catch (_) {
                  if (!mounted) return;
                  if (requestId != activeRequestId) return;
                  setModalState(() {
                    modalError = 'Failed to load nearby layouts.';
                    modalItems = const <NearbyPropertyCard>[];
                  });
                } finally {
                  if (!mounted) return;
                  if (requestId != activeRequestId) return;
                  setModalState(() {
                    modalLoading = false;
                  });
                }
              }

              return _NearbyLayoutsDialog(
                items: modalItems,
                error: modalError,
                isLoading: modalLoading,
                onQueryChanged: refetchForQuery,
                onCloseManual: () =>
                    Navigator.of(context, rootNavigator: true).pop(
                  _NearbyLayoutsDialogCloseReason.manual,
                ),
                onFocus: (item) async {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  // Fetch boundary preview via API (same as web) and draw preview polygon.
                  _fetchAndDrawLayoutPreviewPolygon(item.id);
                  final zoom = item.focusZoomLevel ?? _layoutFocusZoomTarget;
                  await _focusPropertyOnMap(
                    target: LatLng(item.latitude, item.longitude),
                    zoom: zoom,
                  );
                },
                isNearbyNew: _isNearbyNew,
                formatNearbyDate: _formatNearbyDate,
                layoutLocationLabel: _layoutLocationLabel,
                layoutPlotsLabel: _layoutPlotsLabel,
                layoutAreaLabel: _layoutAreaLabel,
              );
            },
          );
        },
      );
    } finally {
      _isNearbyLayoutsDialogOpen = false;
    }

    if (closeReason == _NearbyLayoutsDialogCloseReason.manual) {
      _triggerNearbyLayoutsReopenHint();
    }
  }

  void _triggerNearbyLayoutsReopenHint() {
    _nearbyLayoutsReopenHintTimer?.cancel();

    // Single slow blink (on, then off).
    _updateState(() {
      _isNearbyLayoutsReopenHintOn = true;
    });

    _nearbyLayoutsReopenHintTimer =
        Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _nearbyLayoutsReopenHintTimer = null;
      _updateState(() {
        _isNearbyLayoutsReopenHintOn = false;
      });
    });
  }

  /// Fetch layout boundary from API and draw preview polygon.
  /// Same approach as web: calls the boundary API instead of using nearby DTO.
  void _fetchAndDrawLayoutPreviewPolygon(String layoutId) {
    // Fire-and-forget async call (same pattern as web)
    () async {
      try {
        final preview = await _mapApi.getLayoutBoundaryPreview(
          layoutId: layoutId,
        );
        if (!mounted) return;
        if (preview == null) return;

        final boundaryGeoJson = preview.boundaryGeoJson;
        if (boundaryGeoJson == null || boundaryGeoJson.trim().isEmpty) {
          return;
        }

        _drawLayoutPreviewPolygonFromGeoJson(layoutId, boundaryGeoJson);
      } catch (_) {
        // Silently ignore - preview is optional
      }
    }();
  }

  /// Draw a preview polygon from GeoJSON string.
  /// The preview is cleared automatically when viewport data arrives.
  void _drawLayoutPreviewPolygonFromGeoJson(
    String layoutId,
    String boundaryGeoJson,
  ) {
    final polygons = GeoJson.tryParsePolygons(boundaryGeoJson);
    if (polygons.isEmpty) {
      return;
    }

    final previewSet = <Polygon>{};
    for (var i = 0; i < polygons.length; i++) {
      final ring = polygons[i];
      if (ring.length < 3) continue;

      previewSet.add(
        Polygon(
          polygonId: PolygonId('layout_preview_${layoutId}_$i'),
          points: ring,
          strokeColor:
              _layoutPreviewStroke.withOpacity(_layoutPreviewStrokeOpacity),
          strokeWidth: _layoutPreviewStrokeWidth,
          fillColor: _layoutPreviewFill.withOpacity(_layoutPreviewFillOpacity),
          zIndex: _layoutPreviewZIndex,
          consumeTapEvents: false,
        ),
      );
    }

    if (previewSet.isNotEmpty) {
      _updateState(() {
        _layoutPreviewPolygons = previewSet;
      });
    }
  }

  /// Clear the layout preview polygon.
  void _clearLayoutPreviewPolygon() {
    if (_layoutPreviewPolygons.isEmpty) return;
    _updateState(() {
      _layoutPreviewPolygons = <Polygon>{};
    });
  }
}

class _NearbyLayoutsDialog extends StatefulWidget {
  const _NearbyLayoutsDialog({
    required this.items,
    required this.error,
    required this.isLoading,
    required this.onQueryChanged,
    required this.onCloseManual,
    required this.onFocus,
    required this.isNearbyNew,
    required this.formatNearbyDate,
    required this.layoutLocationLabel,
    required this.layoutPlotsLabel,
    required this.layoutAreaLabel,
  });

  final List<NearbyPropertyCard> items;
  final String? error;
  final bool isLoading;
  final Future<void> Function(String query) onQueryChanged;
  final VoidCallback onCloseManual;
  final Future<void> Function(NearbyPropertyCard item) onFocus;

  final bool Function(DateTime createdAt) isNearbyNew;
  final String Function(DateTime dt) formatNearbyDate;
  final String? Function(NearbyPropertyCard item) layoutLocationLabel;
  final String? Function(NearbyPropertyCard item) layoutPlotsLabel;
  final String? Function(NearbyPropertyCard item) layoutAreaLabel;

  @override
  State<_NearbyLayoutsDialog> createState() => _NearbyLayoutsDialogState();
}

class _NearbyLayoutsDialogState extends State<_NearbyLayoutsDialog> {
  late final TextEditingController _searchController;
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleServerSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(widget.onQueryChanged(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final items = widget.items;
    final shownItems = q.isEmpty
        ? items
        : items.where((item) {
            final name = item.name.trim().toLowerCase();
            final addr = item.address.trim().toLowerCase();
            final city = item.city.trim().toLowerCase();
            final area = (item.area ?? '').trim().toLowerCase();
            return name.contains(q) ||
                addr.contains(q) ||
                city.contains(q) ||
                area.contains(q);
          }).toList(growable: false);

    Widget metaChip(IconData icon, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ],
      );
    }

    final size = MediaQuery.of(context).size;
    final maxWidth = size.width - 24;
    final dialogWidth = maxWidth < 460 ? maxWidth : 460.0;
    const maxVisibleItems = 4;
    const cardHeight = 92.0;
    const cardGap = 8.0;
    const listPaddingVertical = 12.0 + 16.0;
    // Search row + paddings.
    const headerHeight = 98.0;
    const dividerHeight = 1.0;

    final visibleCount = math.min(shownItems.length, maxVisibleItems);
    final listHeight = visibleCount == 0
        ? 140.0
        : (visibleCount * cardHeight) +
            (math.max(0, visibleCount - 1) * cardGap) +
            listPaddingVertical;
    final targetHeight = headerHeight + dividerHeight + listHeight;
    final dialogHeight = math.min(targetHeight, size.height * 0.98);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });

                        // Server-side behavior:
                        // - non-empty query => omit radiusKm and send query
                        // - empty query => restore 50km radius and clear query
                        _scheduleServerSearch(value);
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        hintText: 'Search layouts',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                  _scheduleServerSearch('');
                                },
                                icon: const Icon(Icons.close),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: widget.onCloseManual,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (widget.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (widget.error != null && widget.error!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  widget.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            q.isEmpty
                                ? 'No layouts nearby (within 50 km)'
                                : 'No matches',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (q.isEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Search to see layouts from anywhere',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF94A3B8),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    )
                  : shownItems.isEmpty
                      ? Center(
                          child: Text(
                            'No matches',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: shownItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = shownItems[index];
                            final isNew = widget.isNearbyNew(item.createdAt);
                            final locationMissing = !item.hasLocation;

                            final name = item.name.trim().isEmpty
                                ? 'Layout'
                                : item.name.trim();
                            final locationLabel =
                                widget.layoutLocationLabel(item);
                            final plotsLabel = widget.layoutPlotsLabel(item);
                            final areaLabel = widget.layoutAreaLabel(item);
                            final dateLabel =
                                widget.formatNearbyDate(item.createdAt);

                            Future<void> focus() => widget.onFocus(item);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: focus,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: isNew
                                                        ? Text.rich(
                                                            TextSpan(
                                                              children: [
                                                                TextSpan(
                                                                    text: name),
                                                                WidgetSpan(
                                                                  alignment:
                                                                      PlaceholderAlignment
                                                                          .middle,
                                                                  child:
                                                                      Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        left:
                                                                            8),
                                                                    child:
                                                                        DecoratedBox(
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: const Color(
                                                                            0xFFECFDF5),
                                                                        borderRadius:
                                                                            BorderRadius.circular(6),
                                                                        border:
                                                                            Border.all(
                                                                          color:
                                                                              const Color(0xFF34D399),
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          const Padding(
                                                                        padding:
                                                                            EdgeInsets.symmetric(
                                                                          horizontal:
                                                                              8,
                                                                          vertical:
                                                                              2,
                                                                        ),
                                                                        child:
                                                                            Text(
                                                                          'NEW',
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                Color(0xFF059669),
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight:
                                                                                FontWeight.w800,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Color(
                                                                  0xFF0F766E),
                                                            ),
                                                          )
                                                        : Text(
                                                            name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Color(
                                                                  0xFF0F766E),
                                                            ),
                                                          ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.location_on_outlined,
                                                    size: 16,
                                                    color: locationMissing
                                                        ? const Color(
                                                            0xFFDC2626)
                                                        : const Color(
                                                            0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      locationLabel ??
                                                          'Location not added',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: locationMissing
                                                            ? const Color(
                                                                0xFFDC2626)
                                                            : const Color(
                                                                0xFF475569),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Wrap(
                                                spacing: 14,
                                                runSpacing: 8,
                                                children: [
                                                  if (plotsLabel != null)
                                                    metaChip(
                                                      Icons.grid_on_outlined,
                                                      plotsLabel,
                                                    ),
                                                  if (areaLabel != null)
                                                    metaChip(
                                                      Icons.straighten_outlined,
                                                      areaLabel,
                                                    ),
                                                  metaChip(
                                                    Icons.schedule,
                                                    dateLabel,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Material(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            onTap: focus,
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color:
                                                      const Color(0xFFE2E8F0),
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.near_me_outlined,
                                                size: 18,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
