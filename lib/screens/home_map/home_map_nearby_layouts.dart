part of '../home_map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Nearby Layouts — close-reason enum
// ─────────────────────────────────────────────────────────────────────────────

enum _NearbyLayoutsDialogCloseReason {
  manual,
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension: formatting helpers, data loading, popup, & preview polygons
// ─────────────────────────────────────────────────────────────────────────────

extension _HomeMapNearbyLayouts on _HomeMapScreenState {
  static const double _nearbyLayoutsAutoRadiusKm = 50.0;

  // ── Formatting helpers ──────────────────────────────────────────────────

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

  /// Haversine distance between anchor and item in km.
  String _distanceLabel(LatLng anchor, NearbyPropertyCard item) {
    const R = 6371.0; // Earth radius in km
    final dLat = _deg2rad(item.latitude - anchor.latitude);
    final dLng = _deg2rad(item.longitude - anchor.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(anchor.latitude)) *
            math.cos(_deg2rad(item.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final d = R * c;
    if (d < 1) {
      return '${(d * 1000).round()} m';
    }
    return '${d.toStringAsFixed(1)} km';
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180);

  // ── API / data loading ──────────────────────────────────────────────────

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

  // ── Popup orchestration ─────────────────────────────────────────────────

  Future<void> _openNearbyLayoutsPopup({
    required LatLng anchor,
    bool showWhenEmpty = false,
    bool isManualOpen = false,
  }) async {
    // If the panel is already open and this is an automatic (non-manual) call,
    // skip to avoid duplicating the bottom sheet.
    if (_isNearbyLayoutsDialogOpen && !isManualOpen) return;

    if (_isNearbyLayoutsDialogOpen) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }

    _dismissKeyboard();
    _closeAnyPanel();

    const baseRadiusKm = _nearbyLayoutsAutoRadiusKm;
    const limit = 15;
    final effectiveShowWhenEmpty = showWhenEmpty || isManualOpen;

    await _loadNearbyLayouts(anchor, limit: limit, radiusKm: baseRadiusKm);
    if (!mounted) return;

    final initialError = _nearbyLayoutsError;
    if (initialError != null && initialError.trim().isNotEmpty) {
      ToastMessage.show(context, initialError);
      return;
    }

    final initialItems = _nearbyLayouts ?? const <NearbyPropertyCard>[];
    if (initialItems.isEmpty && !effectiveShowWhenEmpty) {
      _activatePendingCoachmarks();
      return;
    }

    _NearbyLayoutsDialogCloseReason? closeReason;
    var modalItems = _nearbyLayouts ?? const <NearbyPropertyCard>[];
    var modalError = _nearbyLayoutsError;
    var modalLoading = false;
    var activeRequestId = 0;

    try {
      _isNearbyLayoutsDialogOpen = true;
      closeReason = await showModalBottomSheet<_NearbyLayoutsDialogCloseReason>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
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

              return _NearbyLayoutsSheet(
                items: modalItems,
                error: modalError,
                isLoading: modalLoading,
                anchor: anchor,
                onQueryChanged: refetchForQuery,
                onCloseManual: () =>
                    Navigator.of(context, rootNavigator: true).pop(
                  _NearbyLayoutsDialogCloseReason.manual,
                ),
                onFocus: (item) async {
                  Navigator.of(sheetContext, rootNavigator: true).pop();
                  _onNearbyLayoutFocused(item, anchor);
                },
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

    _activatePendingCoachmarks();
  }

  /// Handle user tapping a layout card in the nearby sheet.
  Future<void> _onNearbyLayoutFocused(
    NearbyPropertyCard item,
    LatLng anchor,
  ) async {
    // Clear property type filter if it would exclude the selected layout.
    final currentFilter = _selectedPropertyType?.trim();
    if (currentFilter != null &&
        currentFilter.isNotEmpty &&
        currentFilter != 'Layout') {
      _updateState(() {
        _selectedPropertyType = null;
      });
      _lastViewportSignature = null;
    }

    _drawLayoutPreviewPolygonIfAvailable(item.id, item.boundaryGeoJson);
    final zoom = item.mobileFocusZoomLevel ?? item.focusZoomLevel ?? _layoutFocusZoomTarget;
    await _focusPropertyOnMap(
      target: LatLng(item.latitude, item.longitude),
      zoom: zoom,
    );
  }

  void _triggerNearbyLayoutsReopenHint() {
    _nearbyLayoutsReopenHintTimer?.cancel();

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

  // ── Layout preview polygons ─────────────────────────────────────────────

  /// Draw layout preview polygon using boundary from nearby response.
  /// If boundaryGeoJson is null/empty, falls back to API call.
  void _drawLayoutPreviewPolygonIfAvailable(
    String layoutId,
    String? boundaryGeoJson,
  ) {
    if (boundaryGeoJson != null && boundaryGeoJson.trim().isNotEmpty) {
      _drawLayoutPreviewPolygonFromGeoJson(layoutId, boundaryGeoJson);
    } else {
      _fetchAndDrawLayoutPreviewPolygon(layoutId);
    }
  }

  /// Fetch layout boundary from API and draw preview polygon.
  void _fetchAndDrawLayoutPreviewPolygon(String layoutId) {
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
        // Silently ignore – preview is optional.
      }
    }();
  }

  /// Draw a preview polygon from GeoJSON string.
  void _drawLayoutPreviewPolygonFromGeoJson(
    String layoutId,
    String boundaryGeoJson,
  ) {
    final layoutPrefix = 'layout:$layoutId:';
    final alreadyRendered = _layoutPolygons.any(
      (p) => p.polygonId.value.startsWith(layoutPrefix),
    );
    if (alreadyRendered) return;

    final polygons = GeoJson.tryParsePolygons(boundaryGeoJson);
    if (polygons.isEmpty) return;

    final previewSet = <Polygon>{};
    for (var i = 0; i < polygons.length; i++) {
      final ring = polygons[i];
      if (ring.length < 4) continue;

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

// ─────────────────────────────────────────────────────────────────────────────
// Widget: _NearbyLayoutsSheet (bottom-sheet root)
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyLayoutsSheet extends StatefulWidget {
  const _NearbyLayoutsSheet({
    required this.items,
    required this.error,
    required this.isLoading,
    required this.anchor,
    required this.onQueryChanged,
    required this.onCloseManual,
    required this.onFocus,
  });

  final List<NearbyPropertyCard> items;
  final String? error;
  final bool isLoading;
  final LatLng anchor;
  final Future<void> Function(String query) onQueryChanged;
  final VoidCallback onCloseManual;
  final Future<void> Function(NearbyPropertyCard item) onFocus;

  @override
  State<_NearbyLayoutsSheet> createState() => _NearbyLayoutsSheetState();
}

class _NearbyLayoutsSheetState extends State<_NearbyLayoutsSheet> {
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

  List<NearbyPropertyCard> _filterLocally(
    List<NearbyPropertyCard> items,
    String query,
  ) {
    if (query.isEmpty) return items;
    return items.where((item) {
      final name = item.name.trim().toLowerCase();
      final addr = item.address.trim().toLowerCase();
      final city = item.city.trim().toLowerCase();
      final area = (item.area ?? '').trim().toLowerCase();
      return name.contains(query) ||
          addr.contains(query) ||
          city.contains(query) ||
          area.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQuery.trim().toLowerCase();
    final items = widget.items;
    final shownItems = _filterLocally(items, q);

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.50,
          minChildSize: 0.30,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                _buildDragHandle(),
                _buildHeader(),
                _buildSearchField(q),
                _buildStatusIndicator(context),
                _buildBody(
                  items: items,
                  shownItems: shownItems,
                  query: q,
                  scrollController: scrollController,
                  bottomPadding: bottomPadding,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Sheet sub-sections ────────────────────────────────────────────────

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Nearby Layouts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onCloseManual,
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(String query) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          _scheduleServerSearch(value);
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          hintText: 'Search layouts anywhere...',
          hintStyle: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(Icons.search, size: 22),
          suffixIcon: query.isEmpty
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
                  icon: const Icon(Icons.close, size: 20),
                ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    if (widget.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (widget.error != null && widget.error!.trim().isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          widget.error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBody({
    required List<NearbyPropertyCard> items,
    required List<NearbyPropertyCard> shownItems,
    required String query,
    required ScrollController scrollController,
    required double bottomPadding,
  }) {
    if (items.isEmpty) {
      return Expanded(
        child: _NearbyEmptyState(hasQuery: query.isNotEmpty),
      );
    }
    if (shownItems.isEmpty) {
      return const Expanded(
        child: _NearbyEmptyState(hasQuery: true, localFilterOnly: true),
      );
    }
    return Expanded(
      child: ListView.separated(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomPadding),
        itemCount: shownItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final item = shownItems[index];
          return _NearbyLayoutCardItem(
            item: item,
            onTap: () => widget.onFocus(item),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: _NearbyEmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState({
    required this.hasQuery,
    this.localFilterOnly = false,
  });

  /// Whether a search query is active.
  final bool hasQuery;

  /// True when server returned results but local filter excluded them all.
  final bool localFilterOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off_outlined : Icons.explore_outlined,
            size: 48,
            color: const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'No matches' : 'No layouts nearby (within 50 km)',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
            textAlign: TextAlign.center,
          ),
          if (!hasQuery && !localFilterOnly) ...[
            const SizedBox(height: 6),
            const Text(
              'Search to see layouts from anywhere',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: _NearbyLayoutCardItem (individual list row)
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyLayoutCardItem extends StatelessWidget {
  const _NearbyLayoutCardItem({
    required this.item,
    required this.onTap,
  });

  final NearbyPropertyCard item;
  final VoidCallback onTap;

  // ── Formatting helpers (pure, no dependency on parent state) ───────────

  static const Duration _newThreshold = Duration(days: 7);

  static String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  static String? _locationLabel(NearbyPropertyCard item) {
    final addr = item.address.trim();
    final city = item.city.trim();
    if (addr.isNotEmpty) return addr;
    if (city.isNotEmpty) return city;
    return null;
  }

  static String? _areaLabel(NearbyPropertyCard item) {
    final area = item.area?.trim();
    if (area != null && area.isNotEmpty) return area;
    return null;
  }

  static String? _plotsLabel(NearbyPropertyCard item) {
    final count = item.plotsCount;
    if (count == null) return null;
    return '$count plots';
  }

  static bool _isNew(DateTime createdAt) {
    return DateTime.now().difference(createdAt).abs() <= _newThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _isNew(item.createdAt);
    final locationMissing = !item.hasLocation;
    final name = item.name.trim().isEmpty ? 'Layout' : item.name.trim();
    final locationLabel = _locationLabel(item);
    final plotsLabel = _plotsLabel(item);
    final areaLabel = _areaLabel(item);
    final dateLabel = _formatDate(item.createdAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                // ── Left accent strip ──
                Container(
                  width: 4,
                  constraints: const BoxConstraints(minHeight: 80),
                  color:
                      isNew ? const Color(0xFF34D399) : const Color(0xFF0D9488),
                ),
                // ── Content ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleRow(name, isNew),
                        const SizedBox(height: 6),
                        _buildLocationRow(locationLabel, locationMissing),
                        const SizedBox(height: 8),
                        _buildMetaChips(
                          plotsLabel: plotsLabel,
                          areaLabel: areaLabel,
                          dateLabel: dateLabel,
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Navigate chevron ──
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Card sub-sections ─────────────────────────────────────────────────

  Widget _buildTitleRow(String name, bool isNew) {
    const titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0F766E),
    );

    final titleWidget = isNew
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: name),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF34D399)),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        child: Text(
                          'NEW',
                          style: TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          )
        : Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          );

    return Row(
      children: [
        Expanded(child: titleWidget),
      ],
    );
  }

  Widget _buildLocationRow(String? locationLabel, bool locationMissing) {
    final color =
        locationMissing ? const Color(0xFFDC2626) : const Color(0xFF64748B);
    return Row(
      children: [
        Icon(Icons.location_on_outlined, size: 15, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            locationLabel ?? 'Location not added',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChips({
    required String? plotsLabel,
    required String? areaLabel,
    required String dateLabel,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (plotsLabel != null)
          _NearbyMetaChip(icon: Icons.grid_on_outlined, label: plotsLabel),
        if (areaLabel != null)
          _NearbyMetaChip(icon: Icons.straighten_outlined, label: areaLabel),
        _NearbyMetaChip(icon: Icons.schedule, label: dateLabel),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: _NearbyMetaChip (small icon + text badge)
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyMetaChip extends StatelessWidget {
  const _NearbyMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
