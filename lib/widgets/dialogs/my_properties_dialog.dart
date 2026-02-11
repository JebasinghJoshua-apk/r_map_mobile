import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/my_property_list_item.dart';
import '../../screens/property_details_form_screen.dart';
import '../../screens/property_polygon_editor_screen.dart';
import '../../services/mobile_bff_map_api.dart';
import '../../utils/geojson.dart';
import '../toast_message.dart';

class MyPropertiesDialog extends StatefulWidget {
  const MyPropertiesDialog({
    super.key,
    required this.bearerToken,
    required this.mapApi,
    required this.getMapCenter,
    required this.getMapZoom,
    required this.onMyPropertySelected,
    required this.onMyPropertyDeleted,
    required this.onOpened,
  });

  final String bearerToken;
  final MobileBffMapApi mapApi;
  final LatLng? Function()? getMapCenter;
  final double? Function()? getMapZoom;
  final Future<void> Function(MyPropertyListItem item)? onMyPropertySelected;
  final Future<void> Function(MyPropertyListItem item)? onMyPropertyDeleted;
  final VoidCallback? onOpened;

  @override
  State<MyPropertiesDialog> createState() => _MyPropertiesDialogState();
}

class _MyPropertiesDialogState extends State<MyPropertiesDialog> {
  List<MyPropertyListItem> _items = const <MyPropertyListItem>[];
  bool _isLoading = true;
  String? _error;
  final Set<String> _deletingIds = <String>{};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onOpened?.call();
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isNew(DateTime createdAt) {
    final now = DateTime.now();
    return now.difference(createdAt).inDays < 7;
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await widget.mapApi.getMyProperties(
        bearerToken: widget.bearerToken,
      );
      if (!mounted) return;
      setState(() {
        _items = results;
      });
    } on MapApiException catch (ex) {
      if (!mounted) return;
      setState(() {
        _items = const <MyPropertyListItem>[];
        _error = ex.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <MyPropertyListItem>[];
        _error = 'Failed to load your properties.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openEditor({
    required PropertyPolygonEditorMode mode,
    LatLng? center,
    double? zoom,
    List<LatLng>? initialPoints,
    bool showDetailsOnNext = false,
    String? initialPropertyType,
    String? excludePropertyId,
    String? propertyId,
  }) async {
    final points =
        await Navigator.of(context, rootNavigator: true).push<List<LatLng>>(
      MaterialPageRoute(
        builder: (_) => PropertyPolygonEditorScreen(
          mode: mode,
          initialCenter: center,
          initialZoom: zoom,
          initialPoints: initialPoints,
          bearerToken: widget.bearerToken,
          excludePropertyId: excludePropertyId,
          popOnNext: !showDetailsOnNext,
          onNext: showDetailsOnNext
              ? (points) async {
                  await Navigator.of(context, rootNavigator: true).push<String>(
                    MaterialPageRoute(
                      builder: (_) => PropertyDetailsFormScreen(
                        boundaryPoints: points,
                        initialPropertyType: initialPropertyType,
                        propertyId: propertyId,
                      ),
                    ),
                  );
                }
              : null,
        ),
      ),
    );

    if (!mounted) return;
    if (points != null && points.length >= 3) {
      if (mode == PropertyPolygonEditorMode.edit) {
        ToastMessage.show(context, 'Polygon updated.');
      }
    }
  }

  Future<String?> _pickPropertyTypeForAdd() async {
    const options = <String>[
      'Independent House',
      'Plot',
      'Apartment',
      'Land',
      'Commercial Space',
    ];

    return showDialog<String>(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final maxWidth = size.width - 64;
        final dialogWidth = maxWidth < 332 ? maxWidth : 332.0;
        final dialogMaxHeight = (size.height - 96).clamp(240.0, 520.0);

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: dialogMaxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Add Property',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final opt = options[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        overlayColor: WidgetStateProperty.resolveWith(
                          (states) {
                            if (states.contains(WidgetState.pressed)) {
                              return const Color(0xFF0FAD97).withOpacity(0.10);
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return const Color(0xFF0FAD97).withOpacity(0.06);
                            }
                            return null;
                          },
                        ),
                        onTap: () => Navigator.of(context).pop(opt),
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
                              children: [
                                Expanded(
                                  child: Text(
                                    opt,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteProperty(MyPropertyListItem item) async {
    final id = item.id.trim();
    if (id.isEmpty) {
      ToastMessage.show(context, 'Invalid property id.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete property?'),
            content: const Text(
              'This will permanently delete this property and its details. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _deletingIds.add(id);
    });

    try {
      await widget.mapApi.deleteProperty(
        propertyType: item.propertyType,
        propertyId: id,
        bearerToken: widget.bearerToken,
      );

      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != id).toList(growable: false);
        _deletingIds.remove(id);
      });

      await widget.onMyPropertyDeleted?.call(item);

      if (mounted) {
        ToastMessage.show(context, 'Property deleted.');
      }
    } on MapApiException catch (ex) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(id);
      });
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(id);
      });
      ToastMessage.show(context, 'Failed to delete property.');
    }
  }

  Widget _metaChip(IconData icon, String text) {
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

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool enabled = true,
    Color? iconColor,
    Color? borderColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled
                    ? (borderColor ?? const Color(0xFFE2E8F0))
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: enabled
                  ? (iconColor ?? const Color(0xFF64748B))
                  : const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxWidth = size.width - 24;
    final dialogWidth = maxWidth < 460 ? maxWidth : 460.0;
    final dialogHeight = (size.height * 0.82).clamp(360.0, 680.0);

    final sorted = _items.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final shouldShrink = sorted.length <= 3;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Text(
                    'My Properties',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        '${sorted.length}',
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final selectedType = await _pickPropertyTypeForAdd();
                      if (!mounted) return;
                      if (selectedType == null || selectedType.trim().isEmpty) {
                        return;
                      }
                      final center = widget.getMapCenter?.call();
                      final zoom = widget.getMapZoom?.call();
                      await _openEditor(
                        mode: PropertyPolygonEditorMode.add,
                        center: center,
                        zoom: zoom,
                        showDetailsOnNext: true,
                        initialPropertyType: selectedType,
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0FAD97),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_error != null && _error!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              const Divider(height: 1),
            Flexible(
              fit: FlexFit.loose,
              child: sorted.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Center(
                        child: Text(
                          'No properties found.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(999),
                      child: ListView.separated(
                        controller: _scrollController,
                        shrinkWrap: shouldShrink,
                        physics: shouldShrink
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = sorted[index];
                          final isNew = _isNew(item.createdAt);
                          final isDeleting =
                              _deletingIds.contains(item.id.trim());

                          final name = item.name.trim().isEmpty
                              ? (item.propertyType.trim().isEmpty
                                  ? 'Property'
                                  : item.propertyType.trim())
                              : item.name.trim();

                          final locationLabel = item.locationLabel.trim();
                          final locationMissing = locationLabel.isEmpty;

                          final typeLabel = item.propertyType.trim().isEmpty
                              ? 'Property'
                              : item.propertyType.trim();
                          final normalizedType =
                              item.propertyType.trim().toLowerCase();
                          final normalizedCompact =
                              normalizedType.replaceAll(RegExp(r'\s+'), '');
                          final plotsCount = item.plotsCount ?? 0;
                          final hasMultiplePlots =
                              normalizedCompact == 'plot' && plotsCount > 1;
                          final isLayoutProperty =
                              normalizedType.contains('layout');
                          final isEditableProperty = const <String>{
                                'plot',
                                'apartment',
                                'independenthouse',
                                'commercialspace',
                                'land',
                              }.contains(normalizedCompact) &&
                              !hasMultiplePlots;
                          final canDeleteProperty = !isDeleting &&
                              isEditableProperty &&
                              !isLayoutProperty;
                          final deleteDisabledReason = canDeleteProperty
                              ? 'Delete'
                              : (isDeleting
                                  ? 'Deleting...'
                                  : (hasMultiplePlots
                                      ? 'Delete disabled'
                                      : 'Delete (web only)'));

                          final dateSource = item.createdAt ==
                                  DateTime.fromMillisecondsSinceEpoch(0)
                              ? item.updatedAt
                              : item.createdAt;
                          final dateLabel = _formatDate(dateSource);

                          Future<void> focus() async {
                            Navigator.of(context).pop();
                            await widget.onMyPropertySelected?.call(item);
                          }

                          Future<void> edit() async {
                            if (!isEditableProperty || isLayoutProperty) {
                              return;
                            }

                            LatLng? center =
                                item.centerPoint ?? widget.getMapCenter?.call();
                            List<LatLng>? initialPoints;

                            try {
                              final detailPropertyId = item.propertyId.trim();
                              final detail =
                                  await widget.mapApi.getPropertyDetail(
                                propertyId: detailPropertyId.isEmpty
                                    ? item.id
                                    : detailPropertyId,
                                bearerToken: widget.bearerToken,
                              );
                              final polygons = GeoJson.tryParsePolygons(
                                detail.propertyBoundaryGeoJson,
                              );
                              if (polygons.isNotEmpty) {
                                initialPoints = polygons.first;
                                center ??= GeoJson.tryParsePoint(
                                  detail.centerPointGeoJson,
                                );
                              }
                            } on MapApiException catch (ex) {
                              if (!mounted) return;
                              ToastMessage.show(this.context, ex.message);
                            } catch (_) {
                              if (!mounted) return;
                              ToastMessage.show(
                                this.context,
                                'Failed to load property boundary.',
                              );
                            }

                            if (!mounted) return;
                            await _openEditor(
                              mode: PropertyPolygonEditorMode.edit,
                              center: center,
                              initialPoints: initialPoints,
                              excludePropertyId: item.propertyId,
                              showDetailsOnNext: true,
                              initialPropertyType: item.propertyType,
                              propertyId: item.propertyId,
                            );
                          }

                          Future<void> deleteProperty() async {
                            await _deleteProperty(item);
                          }

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => unawaited(focus()),
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
                                                                text: name,
                                                              ),
                                                              WidgetSpan(
                                                                alignment:
                                                                    PlaceholderAlignment
                                                                        .middle,
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .only(
                                                                    left: 8,
                                                                  ),
                                                                  child:
                                                                      DecoratedBox(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: const Color(
                                                                          0xFFECFDF5),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              6),
                                                                      border:
                                                                          Border
                                                                              .all(
                                                                        color: const Color(
                                                                            0xFF34D399),
                                                                      ),
                                                                    ),
                                                                    child:
                                                                        const Padding(
                                                                      padding:
                                                                          EdgeInsets
                                                                              .symmetric(
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF0F766E),
                                                          ),
                                                        )
                                                      : Text(
                                                          name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
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
                                                      ? const Color(0xFFDC2626)
                                                      : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    locationMissing
                                                        ? 'Location not added'
                                                        : locationLabel,
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
                                                _metaChip(
                                                  Icons.category_outlined,
                                                  typeLabel,
                                                ),
                                                _metaChip(
                                                  Icons.schedule,
                                                  dateLabel,
                                                ),
                                                if (!item.isApproved)
                                                  _metaChip(
                                                    Icons
                                                        .pending_actions_outlined,
                                                    'Pending',
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _actionIcon(
                                            icon: Icons.edit_outlined,
                                            tooltip: isEditableProperty &&
                                                    !isLayoutProperty
                                                ? 'Edit'
                                                : (hasMultiplePlots
                                                    ? 'Edit disabled'
                                                    : 'Edit (web only)'),
                                            onTap: isEditableProperty &&
                                                    !isLayoutProperty
                                                ? () => unawaited(edit())
                                                : () => ToastMessage.showAbove(
                                                      context,
                                                      hasMultiplePlots
                                                          ? 'Only single-plot properties can be edited on mobile.'
                                                          : 'Layout editable only in web screen.',
                                                    ),
                                            enabled: isEditableProperty &&
                                                !isLayoutProperty,
                                          ),
                                          const SizedBox(width: 6),
                                          _actionIcon(
                                            icon: Icons.delete_outline,
                                            tooltip: deleteDisabledReason,
                                            onTap: canDeleteProperty
                                                ? () =>
                                                    unawaited(deleteProperty())
                                                : (isDeleting
                                                    ? null
                                                    : () =>
                                                        ToastMessage.showAbove(
                                                          context,
                                                          hasMultiplePlots
                                                              ? 'Only single-plot properties can be deleted on mobile.'
                                                              : 'Layout deletions are available on the web screen.',
                                                        )),
                                            enabled: canDeleteProperty,
                                            iconColor: const Color(0xFFDC2626),
                                            borderColor:
                                                const Color(0xFFFEE2E2),
                                          ),
                                        ],
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
            ),
          ],
        ),
      ),
    );
  }
}
