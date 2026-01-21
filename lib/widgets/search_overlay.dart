import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/search_constants.dart';
import '../models/my_property_list_item.dart';
import '../models/recent_place.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import 'auth_dialog.dart';
import 'toast_message.dart';

enum _ProfileMenuAction {
  login,
  myProperties,
  logout,
}

class SearchOverlay extends StatefulWidget {
  final GooglePlace googlePlace;
  final void Function(LatLng position, String label, double zoom)
      onPlaceSelected;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;
  final ValueChanged<MyPropertyListItem>? onMyPropertySelected;

  const SearchOverlay({
    super.key,
    required this.googlePlace,
    required this.onPlaceSelected,
    this.onSearchTap,
    this.onFilterTap,
    this.hasActiveFilters = false,
    this.onMyPropertySelected,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final MobileBffMapApi _mapApi = MobileBffMapApi();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<AutocompletePrediction> _predictions = [];
  List<RecentPlace> _recentPlaces = [];
  Timer? _debounce;
  Timer? _keyboardShowTimer;
  bool _isLoading = false;
  bool _isCompactMode = false;

  static const Duration _newThreshold = Duration(days: 7);

  bool get _shouldShowRecents =>
      _controller.text.isEmpty && _recentPlaces.isNotEmpty;

  bool _isNew(DateTime createdAt) {
    if (createdAt == DateTime.fromMillisecondsSinceEpoch(0)) return false;
    return DateTime.now().difference(createdAt) <= _newThreshold;
  }

  Future<void> showMyPropertiesPopup() async {
    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      ToastMessage.show(context, 'Please login to view your properties.');
      return;
    }

    String formatDate(DateTime dt) {
      final d = dt.toLocal();
      return '${d.day}/${d.month}/${d.year}';
    }

    List<MyPropertyListItem> items = const <MyPropertyListItem>[];
    bool isLoading = true;
    String? error;
    bool started = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> load() async {
              setModalState(() {
                isLoading = true;
                error = null;
              });

              try {
                final results = await _mapApi.getMyProperties(
                  bearerToken: token,
                );
                setModalState(() {
                  items = results;
                });
              } on MapApiException catch (ex) {
                setModalState(() {
                  items = const <MyPropertyListItem>[];
                  error = ex.message;
                });
              } catch (_) {
                setModalState(() {
                  items = const <MyPropertyListItem>[];
                  error = 'Failed to load your properties.';
                });
              } finally {
                setModalState(() {
                  isLoading = false;
                });
              }
            }

            Future<void> refresh() async {
              if (isLoading) return;
              await load();
            }

            if (!started) {
              started = true;
              unawaited(load());
            }

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
            final dialogHeight = (size.height * 0.82).clamp(360.0, 680.0);

            final sorted = items.toList(growable: false)
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                      child: Row(
                        children: [
                          const Text(
                            'My properties',
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
                            onPressed: isLoading ? null : refresh,
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
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (error != null && error!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      const Divider(height: 1),
                    Expanded(
                      child: sorted.isEmpty
                          ? const Center(
                              child: Text(
                                'No properties found.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              itemCount: sorted.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = sorted[index];
                                final isNew = _isNew(item.createdAt);

                                final name = item.name.trim().isEmpty
                                    ? (item.propertyType.trim().isEmpty
                                        ? 'Property'
                                        : item.propertyType.trim())
                                    : item.name.trim();

                                final locationLabel = item.locationLabel.trim();
                                final locationMissing = locationLabel.isEmpty;

                                final typeLabel =
                                    item.propertyType.trim().isEmpty
                                        ? 'Property'
                                        : item.propertyType.trim();

                                final dateSource = item.createdAt ==
                                        DateTime.fromMillisecondsSinceEpoch(0)
                                    ? item.updatedAt
                                    : item.createdAt;
                                final dateLabel = formatDate(dateSource);

                                Future<void> focus() async {
                                  Navigator.of(context).pop();
                                  if (!mounted) return;
                                  widget.onMyPropertySelected?.call(item);
                                }

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: focus,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
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
                                                                    TextSpan(text: name),
                                                                    WidgetSpan(
                                                                      alignment: PlaceholderAlignment.middle,
                                                                      child: Padding(
                                                                        padding: const EdgeInsets.only(left: 8),
                                                                        child: DecoratedBox(
                                                                          decoration: BoxDecoration(
                                                                            color: const Color(0xFFECFDF5),
                                                                            borderRadius: BorderRadius.circular(6),
                                                                            border: Border.all(
                                                                              color: const Color(0xFF34D399),
                                                                            ),
                                                                          ),
                                                                          child: const Padding(
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
                                                                    TextOverflow.ellipsis,
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
                                                                overflow:
                                                                    TextOverflow.ellipsis,
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
                                                        Icons
                                                            .location_on_outlined,
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
                                                          locationMissing
                                                              ? 'Location not added'
                                                              : locationLabel,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
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
                                                      metaChip(
                                                        Icons.category_outlined,
                                                        typeLabel,
                                                      ),
                                                      metaChip(
                                                        Icons.schedule,
                                                        dateLabel,
                                                      ),
                                                      if (!item.isApproved)
                                                        metaChip(
                                                          Icons
                                                              .pending_actions_outlined,
                                                          'Pending',
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
  }

  @override
  void initState() {
    super.initState();
    _loadRecentPlaces();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusSearchField(forceKeyboard: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _keyboardShowTimer?.cancel();
    super.dispose();
  }

  void _focusSearchField({bool forceKeyboard = false}) {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_focusNode);
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    if (forceKeyboard) {
      _keyboardShowTimer?.cancel();
      _keyboardShowTimer = Timer(const Duration(milliseconds: 30), () {
        if (mounted) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    }
  }

  void _enterExpandedMode() {
    final bool wasCompact = _isCompactMode;
    if (wasCompact) {
      setState(() {
        _isCompactMode = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSearchField(forceKeyboard: true);
    });
  }

  Future<void> _loadRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(recentPlacesStorageKey) ?? [];
    final parsed = stored
        .map(RecentPlace.fromJsonString)
        .whereType<RecentPlace>()
        .toList();
    if (!mounted) return;
    setState(() {
      _recentPlaces = parsed;
    });
  }

  Future<void> _saveRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      recentPlacesStorageKey,
      _recentPlaces.map((place) => place.toJsonString()).toList(),
    );
  }

  Future<void> _clearRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(recentPlacesStorageKey);
    if (!mounted) return;
    setState(() {
      _recentPlaces = [];
    });
  }

  Future<void> _upsertRecentPlace(RecentPlace place) async {
    if (!mounted) return;
    setState(() {
      _recentPlaces
          .removeWhere((existing) => existing.placeId == place.placeId);
      _recentPlaces.insert(0, place);
      if (_recentPlaces.length > 5) {
        _recentPlaces = _recentPlaces.sublist(0, 5);
      }
    });
    await _saveRecentPlaces();
  }

  Future<void> _handleRecentTap(RecentPlace place) async {
    final success = await _selectPlace(place.placeId, place.displayLabel);
    if (success) {
      await _upsertRecentPlace(place);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _predictions.clear();
        _isLoading = false;
      });
      _enterExpandedMode();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });
      try {
        final response = await widget.googlePlace.autocomplete.get(
          query,
          language: 'en',
          location: tamilNaduBiasPoint,
          radius: tamilNaduRadiusMeters,
          strictbounds: true,
          components: [Component('country', 'in')],
        );
        if (!mounted) return;
        setState(() {
          _predictions
            ..clear()
            ..addAll(response?.predictions ?? []);
        });
      } catch (e) {
        debugPrint('Autocomplete error: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    });
  }

  Future<bool> _selectPlace(String placeId, String fallbackLabel) async {
    if (!mounted) return false;
    setState(() {
      _isLoading = true;
    });
    try {
      final details = await widget.googlePlace.details.get(placeId);
      final location = details?.result?.geometry?.location;
      if (location == null) {
        return false;
      }

      final label = details?.result?.name ?? fallbackLabel;
      final latLng = LatLng(location.lat ?? 0, location.lng ?? 0);

      final types = details?.result?.types?.whereType<String>().toList() ??
          const <String>[];
      final zoom = _suggestZoomForPlaceTypes(types, label);

      widget.onPlaceSelected(latLng, label, zoom);
      if (!mounted) return true;
      setState(() {
        _controller.text = label;
        _predictions.clear();
        _isCompactMode = true;
      });
      FocusScope.of(context).unfocus();
      _keyboardShowTimer?.cancel();
      SystemChannels.textInput.invokeMethod('TextInput.hide');

      return true;
    } catch (e) {
      debugPrint('Error selecting place: $e');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _suggestZoomForPlaceTypes(List<String> types, String label) {
    // Heuristic: label visibility is controlled by Google map tiles, so we
    // can't reliably detect if a name will be rendered. Instead, align zoom
    // with the place granularity.
    final set = types.map((t) => t.trim().toLowerCase()).toSet();

    // Broad regions
    if (set.contains('country')) return 5.5;
    if (set.contains('administrative_area_level_1')) return 8.5; // state

    // Cities / districts
    // Some smaller towns come back as `locality` but look better at a
    // neighborhood-ish zoom (15.8), while major metros are better at 13.8.
    if (set.contains('locality') ||
        set.contains('administrative_area_level_2')) {
      final normalizedName = label.trim().toLowerCase();
      const majorCitiesAtCityZoom = <String>{
        'madurai',
        'coimbatore',
        'chennai',
      };
      return majorCitiesAtCityZoom.contains(normalizedName) ? 13.8 : 15.8;
    }

    // Neighborhood-level
    if (set.contains('sublocality') ||
        set.contains('sublocality_level_1') ||
        set.contains('neighborhood')) {
      return 15.8;
    }

    // Streets / POIs / addresses
    if (set.contains('route')) return 15.8;
    if (set.contains('street_address') ||
        set.contains('premise') ||
        set.contains('establishment') ||
        set.contains('point_of_interest')) {
      return 15.8;
    }

    return 15.8;
  }

  Future<void> _handlePredictionTap(AutocompletePrediction prediction) async {
    final placeId = prediction.placeId;
    if (placeId == null) return;

    final mainText =
        prediction.structuredFormatting?.mainText ?? prediction.description;
    final fallbackLabel = prediction.description ?? mainText ?? 'Selected';
    final success = await _selectPlace(placeId, fallbackLabel);
    if (success) {
      final recent = RecentPlace(
        placeId: placeId,
        title: mainText ?? fallbackLabel,
        subtitle: prediction.structuredFormatting?.secondaryText ?? '',
      );
      await _upsertRecentPlace(recent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showBrandHeader = !_isCompactMode;
    final bool showCompactRLogoInSearchBar = _isCompactMode;
    final double searchCardRadius = _isCompactMode ? 6 : 10;

    final Widget searchCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(searchCardRadius),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.onSearchTap?.call(),
            child: Row(
              children: [
                if (showCompactRLogoInSearchBar)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, right: 8),
                    child: _RLogoTile(),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.search, color: Colors.grey, size: 22),
                  ),
                if (showCompactRLogoInSearchBar) ...[
                  const _VerticalSeparator(),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search for places...',
                    ),
                    onChanged: _onQueryChanged,
                    onTap: () {
                      widget.onSearchTap?.call();
                      _enterExpandedMode();
                    },
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 40,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _controller.clear();
                      });
                      _enterExpandedMode();
                      _onQueryChanged('');
                    },
                  ),
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.tune, color: Color(0xFF0FAD97)),
                      if (widget.hasActiveFilters)
                        const Positioned(
                          top: -1,
                          right: -1,
                          child: SizedBox(
                            width: 9,
                            height: 9,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFF0FAD97),
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 42,
                    height: 40,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _keyboardShowTimer?.cancel();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                    widget.onFilterTap?.call();
                  },
                ),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          if (_shouldShowRecents)
            Column(
              children: [
                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  child: Row(
                    children: [
                      const Text(
                        'RECENT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _clearRecentPlaces,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 24),
                        ),
                        child: const Text(
                          'CLEAR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0FAD97),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentPlaces.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final place = _recentPlaces[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on,
                          color: Color(0xFF0FAD97)),
                      title: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.3,
                          ),
                          children: [
                            TextSpan(
                              text: place.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (place.subtitle.isNotEmpty)
                              TextSpan(
                                text: ' ${place.subtitle}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF475467),
                                ),
                              ),
                          ],
                        ),
                      ),
                      onTap: () => _handleRecentTap(place),
                    );
                  },
                ),
              ],
            )
          else if (_predictions.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _predictions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  final mainText = prediction.structuredFormatting?.mainText ??
                      prediction.description ??
                      '';
                  final secondaryText =
                      prediction.structuredFormatting?.secondaryText;

                  return ListTile(
                    dense: true,
                    leading:
                        const Icon(Icons.location_on, color: Color(0xFF0FAD97)),
                    title: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(
                            text: mainText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (secondaryText != null && secondaryText.isNotEmpty)
                            TextSpan(
                              text: ' $secondaryText',
                              style: const TextStyle(
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF475467),
                              ),
                            ),
                        ],
                      ),
                    ),
                    onTap: () => _handlePredictionTap(prediction),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );

    if (!showBrandHeader) {
      return Row(
        children: [
          Expanded(child: searchCard),
          const SizedBox(width: 7),
          const _CompactProfileButton(),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF14B8A6),
                        Color(0xFF0D9488),
                        Color(0xFF0F766E),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'R',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(
                      left: 4, right: 16, top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'eal Estate Map',
                    style: TextStyle(
                      color: Color(0xFF00796B),
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          searchCard,
        ],
      ),
    );
  }
}

class _RLogoTile extends StatelessWidget {
  const _RLogoTile();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF14B8A6),
              Color(0xFF0D9488),
              Color(0xFF0F766E),
            ],
          ),
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        child: Center(
          child: Text(
            'R',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 22,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Color(0xFFE2E8F0),
      ),
    );
  }
}

class _CompactProfileButton extends StatelessWidget {
  const _CompactProfileButton();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final session = auth.session;

    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          },
          child: PopupMenuButton<_ProfileMenuAction>(
            tooltip: 'Profile',
            position: PopupMenuPosition.under,
            padding: EdgeInsets.zero,
            offset: const Offset(0, 10),
            child: const SizedBox.expand(
              child: Center(
                child: Icon(
                  Icons.person_outline,
                  color: Color(0xFF0FAD97),
                ),
              ),
            ),
            onSelected: (value) {
              switch (value) {
                case _ProfileMenuAction.login:
                  FocusManager.instance.primaryFocus?.unfocus();
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                  AuthDialog.showLogin(context);
                  break;
                case _ProfileMenuAction.myProperties:
                  FocusManager.instance.primaryFocus?.unfocus();
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                  final overlayState =
                      context.findAncestorStateOfType<_SearchOverlayState>();
                  overlayState?.showMyPropertiesPopup();
                  break;
                case _ProfileMenuAction.logout:
                  FocusManager.instance.primaryFocus?.unfocus();
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                  auth.logout().then((_) {
                    if (!context.mounted) return;
                    ToastMessage.show(context, 'Logged out');
                  }).catchError((_) {
                    if (!context.mounted) return;
                    ToastMessage.show(context, 'Logout failed');
                  });
                  break;
              }
            },
            itemBuilder: (context) {
              if (session == null) {
                return const <PopupMenuEntry<_ProfileMenuAction>>[
                  PopupMenuItem<_ProfileMenuAction>(
                    value: _ProfileMenuAction.login,
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.login, size: 18),
                        SizedBox(width: 10),
                        Text('Login'),
                      ],
                    ),
                  ),
                ];
              }

              final fullName =
                  '${session.user.firstName} ${session.user.lastName}'.trim();
              final displayName =
                  fullName.isEmpty ? session.user.phoneNumber : fullName;

              return <PopupMenuEntry<_ProfileMenuAction>>[
                PopupMenuItem<_ProfileMenuAction>(
                  enabled: false,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, $displayName',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 8),
                const PopupMenuItem<_ProfileMenuAction>(
                  value: _ProfileMenuAction.myProperties,
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.business_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('My Properties'),
                    ],
                  ),
                ),
                const PopupMenuItem<_ProfileMenuAction>(
                  value: _ProfileMenuAction.logout,
                  height: 40,
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 10),
                      Text('Logout'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ),
      ),
    );
  }
}
