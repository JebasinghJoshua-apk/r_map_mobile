import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/saved_property.dart';
import '../../services/mobile_bff_saved_properties_api.dart';
import '../toast_message.dart';

class FavoritesDialog extends StatefulWidget {
  const FavoritesDialog({
    super.key,
    required this.bearerToken,
    required this.savedPropertiesApi,
    required this.onPlaceSelected,
    required this.onOpened,
  });

  final String bearerToken;
  final MobileBffSavedPropertiesApi savedPropertiesApi;
  final Future<void> Function(LatLng target, String label, double zoom)
      onPlaceSelected;
  final VoidCallback? onOpened;

  @override
  State<FavoritesDialog> createState() => _FavoritesDialogState();
}

class _FavoritesDialogState extends State<FavoritesDialog> {
  List<SavedProperty> _items = const <SavedProperty>[];
  bool _isLoading = true;
  String? _error;
  final Set<String> _removingIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onOpened?.call();
    });
    unawaited(_load());
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
      final results = await widget.savedPropertiesApi.getSavedProperties(
        bearerToken: widget.bearerToken,
      );
      if (!mounted) return;
      setState(() {
        _items = results;
      });
    } on SavedPropertiesApiException catch (ex) {
      if (!mounted) return;
      setState(() {
        _items = const <SavedProperty>[];
        _error = ex.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <SavedProperty>[];
        _error = 'Failed to load shortlisted properties.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeFavorite(String propertyId) async {
    if (_removingIds.contains(propertyId)) return;
    setState(() => _removingIds.add(propertyId));

    try {
      await widget.savedPropertiesApi.unsaveProperty(
        propertyId: propertyId,
        bearerToken: widget.bearerToken,
      );

      if (!mounted) return;
      setState(() {
        _items = _items
            .where((e) => e.propertyId.trim() != propertyId)
            .toList(growable: false);
      });
    } on SavedPropertiesApiException catch (ex) {
      if (!mounted) return;
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      ToastMessage.show(context, 'Failed to remove from shortlist');
    } finally {
      if (mounted) {
        setState(() => _removingIds.remove(propertyId));
      }
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
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

    final shouldShrink = sorted.length <= 3;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
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
                  const Icon(
                    Icons.favorite,
                    color: Color(0xFFE11D48),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Shortlisted',
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
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : () => unawaited(_load()),
                    icon: const Icon(Icons.refresh),
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
                          'No shortlisted properties yet.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: shouldShrink,
                      physics: shouldShrink
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final saved = sorted[index];
                        final propertyId = saved.propertyId.trim().isEmpty
                            ? saved.property.id.trim()
                            : saved.propertyId.trim();
                        final isRemoving = _removingIds.contains(propertyId);

                        final p = saved.property;
                        final name = p.name.trim().isEmpty
                            ? (p.propertyTypeName?.trim().isEmpty ?? true
                                ? 'Property'
                                : p.propertyTypeName!.trim())
                            : p.name.trim();

                        final locationLabel = p.locationLabel.trim();
                        final locationMissing = locationLabel.isEmpty;

                        final typeLabel =
                            (p.propertyTypeName ?? '').trim().isEmpty
                                ? 'Property'
                                : p.propertyTypeName!.trim();
                        final dateLabel = _formatDate(saved.savedAt);
                        final isPending = p.isApproved == false;
                        final isNew = _isNew(saved.savedAt);

                        Future<void> focus() async {
                          final center = p.centerPoint;
                          if (center == null) {
                            if (!mounted) return;
                            ToastMessage.show(
                                context, 'Location not available');
                            return;
                          }

                          Navigator.of(context).pop();
                          await widget.onPlaceSelected(center, name, 18);
                        }

                        Future<void> remove() async {
                          if (propertyId.isEmpty) {
                            if (!mounted) return;
                            ToastMessage.show(context, 'Invalid property id');
                            return;
                          }
                          await _removeFavorite(propertyId);
                        }

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isRemoving ? null : () => unawaited(focus()),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                                                        BorderRadius
                                                                            .circular(6),
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
                                                                    child: Text(
                                                                      'NEW',
                                                                      style:
                                                                          TextStyle(
                                                                        color: Color(
                                                                            0xFF059669),
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
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF0F766E),
                                                        ),
                                                      )
                                                    : Text(
                                                        name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              Color(0xFF0F766E),
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
                                                    fontWeight: FontWeight.w600,
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
                                              if (isPending)
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
                                          icon: Icons.visibility_outlined,
                                          tooltip: 'View',
                                          onTap: isRemoving
                                              ? null
                                              : () => unawaited(focus()),
                                        ),
                                        const SizedBox(width: 6),
                                        _actionIcon(
                                          icon: Icons.delete_outline,
                                          tooltip: isRemoving
                                              ? 'Removing...'
                                              : 'Remove',
                                          onTap: isRemoving
                                              ? null
                                              : () => unawaited(remove()),
                                          enabled: !isRemoving,
                                          iconColor: const Color(0xFFDC2626),
                                          borderColor: const Color(0xFFFEE2E2),
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
          ],
        ),
      ),
    );
  }
}
