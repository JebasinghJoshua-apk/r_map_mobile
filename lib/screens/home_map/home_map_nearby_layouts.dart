part of '../home_map_screen.dart';

enum _NearbyLayoutsDialogCloseReason {
  manual,
}

extension _HomeMapNearbyLayouts on _HomeMapScreenState {
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

  Future<void> _loadNearbyLayouts(LatLng anchor) async {
    final token = AuthScope.of(context).session?.token;
    _updateState(() {
      _isNearbyLayoutsLoading = true;
      _nearbyLayoutsError = null;
    });

    try {
      final results = await _mapApi.getNearbyLayouts(
        anchor: anchor,
        limit: 15,
        radiusKm: 30,
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
    } finally {
      if (mounted) {
        _updateState(() {
          _isNearbyLayoutsLoading = false;
        });
      }
    }
  }

  Future<void> _openNearbyLayoutsPopup({required LatLng anchor}) async {
    if (_isNearbyLayoutsDialogOpen) {
      final dialogContext = _nearbyLayoutsDialogContext;
      if (dialogContext != null) {
        Navigator.of(dialogContext).pop();
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }

    _dismissKeyboard();
    _closeAnyPanel();

    // Fetch first; only show the popup after we have a response.
    await _loadNearbyLayouts(anchor);
    if (!mounted) return;
    final initialError = _nearbyLayoutsError;
    if (initialError != null && initialError.trim().isNotEmpty) {
      ToastMessage.show(context, initialError);
      return;
    }

    final initialItems = _nearbyLayouts ?? const <NearbyPropertyCard>[];
    if (initialItems.isEmpty) {
      return;
    }

    _NearbyLayoutsDialogCloseReason? closeReason;
    try {
      _isNearbyLayoutsDialogOpen = true;
      closeReason = await showDialog<_NearbyLayoutsDialogCloseReason>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          _nearbyLayoutsDialogContext = dialogContext;

          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> refresh() async {
                if (_isNearbyLayoutsLoading) return;
                await _loadNearbyLayouts(anchor);
                if (!mounted) return;
                setModalState(() {});
              }

              final items = _nearbyLayouts ?? const <NearbyPropertyCard>[];
              final error = _nearbyLayoutsError;

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
              const headerHeight = 102.0;
              const dividerHeight = 1.0;

              final visibleCount = math.min(items.length, maxVisibleItems);
              final listHeight = visibleCount == 0
                  ? 140.0
                  : (visibleCount * cardHeight) +
                      (math.max(0, visibleCount - 1) * cardGap) +
                      listPaddingVertical;
              final targetHeight = headerHeight + dividerHeight + listHeight;
              final dialogHeight = math.min(targetHeight, size.height * 0.98);

              return Dialog(
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox(
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          children: [
                            const Text(
                              'Layouts near Aruppukkottai',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (items.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF2F3),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${items.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed:
                                  _isNearbyLayoutsLoading ? null : refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(
                                _NearbyLayoutsDialogCloseReason.manual,
                              ),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      if (_isNearbyLayoutsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: LinearProgressIndicator(minHeight: 2),
                        )
                      else if (error != null && error.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            error,
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
                            ? const Center(
                                child: Text(
                                  'No layouts found near this point.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final isNew = _isNearbyNew(item.createdAt);
                                  final locationMissing = !item.hasLocation;

                                  final name = item.name.trim().isEmpty
                                      ? 'Layout'
                                      : item.name.trim();
                                  final locationLabel =
                                      _layoutLocationLabel(item);
                                  final plotsLabel = _layoutPlotsLabel(item);
                                  final areaLabel = _layoutAreaLabel(item);
                                  final dateLabel =
                                      _formatNearbyDate(item.createdAt);

                                  Future<void> focus() async {
                                    Navigator.of(context).pop();
                                    final zoom = item.focusZoomLevel ??
                                        _layoutFocusZoomTarget;
                                    await _focusPropertyOnMap(
                                      target:
                                          LatLng(item.latitude, item.longitude),
                                      zoom: zoom,
                                    );
                                  }

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: focus,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(10),
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
                                                                          text:
                                                                              name),
                                                                      WidgetSpan(
                                                                        alignment:
                                                                            PlaceholderAlignment.middle,
                                                                        child:
                                                                            Padding(
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              left: 8),
                                                                          child:
                                                                              DecoratedBox(
                                                                            decoration:
                                                                                BoxDecoration(
                                                                              color: const Color(0xFFECFDF5),
                                                                              borderRadius: BorderRadius.circular(6),
                                                                              border: Border.all(
                                                                                color: const Color(0xFF34D399),
                                                                              ),
                                                                            ),
                                                                            child:
                                                                                const Padding(
                                                                              padding: EdgeInsets.symmetric(
                                                                                horizontal: 8,
                                                                                vertical: 2,
                                                                              ),
                                                                              child: Text(
                                                                                'NEW',
                                                                                style: TextStyle(
                                                                                  color: Color(0xFF059669),
                                                                                  fontSize: 10,
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
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        15,
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
                                                                    fontSize:
                                                                        15,
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
                                                          Icons
                                                              .location_on_outlined,
                                                          size: 16,
                                                          color: locationMissing
                                                              ? const Color(
                                                                  0xFFDC2626)
                                                              : const Color(
                                                                  0xFF64748B),
                                                        ),
                                                        const SizedBox(
                                                            width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            locationLabel ??
                                                                'Location not added',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
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
                                                            Icons
                                                                .grid_on_outlined,
                                                            plotsLabel,
                                                          ),
                                                        if (areaLabel != null)
                                                          metaChip(
                                                            Icons
                                                                .straighten_outlined,
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
                                                          BorderRadius.circular(
                                                              10),
                                                      border: Border.all(
                                                        color: const Color(
                                                            0xFFE2E8F0),
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
            },
          );
        },
      );
    } finally {
      _isNearbyLayoutsDialogOpen = false;
      _nearbyLayoutsDialogContext = null;
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
}
