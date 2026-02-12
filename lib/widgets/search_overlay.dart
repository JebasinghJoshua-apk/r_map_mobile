import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/search_constants.dart';
import '../models/auth_session.dart';
import '../models/my_property_list_item.dart';
import '../models/recent_place.dart';
import '../models/saved_property.dart';
import '../services/analytics_service.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_saved_properties_api.dart';
import '../state/auth_scope.dart';
import '../utils/anchored_popover_geometry.dart';
import 'auth_dialog.dart';
import 'dialogs/favorites_dialog.dart';
import 'dialogs/my_properties_dialog.dart';
import 'toast_message.dart';

class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.googlePlace,
    required this.onPlaceSelected,
    this.onShortlistedPlaceSelected,
    this.onShortlistedPropertySelected,
    this.onMyPropertySelected,
    this.onMyPropertyDeleted,
    this.onMyPropertiesOpened,
    this.getMapCenter,
    this.getMapZoom,
    this.onSearchTap,
    this.onFilterTap,
    this.onOpenChanged,
    this.hasActiveFilters = false,
    this.favoritesCount,
  });

  final GooglePlace googlePlace;
  final Future<void> Function(LatLng target, String label, double zoom)
      onPlaceSelected;

  final Future<void> Function(LatLng target, String label, double zoom)?
      onShortlistedPlaceSelected;

  final Future<void> Function(SavedProperty saved)?
      onShortlistedPropertySelected;

  final Future<void> Function(MyPropertyListItem item)? onMyPropertySelected;
  final Future<void> Function(MyPropertyListItem item)? onMyPropertyDeleted;
  final VoidCallback? onMyPropertiesOpened;
  final LatLng? Function()? getMapCenter;
  final double? Function()? getMapZoom;

  final VoidCallback? onSearchTap;
  final void Function(Rect panelAnchorRect, Rect arrowAnchorRect)? onFilterTap;
  final ValueChanged<bool>? onOpenChanged;
  final bool hasActiveFilters;
  final int? favoritesCount;

  @override
  SearchOverlayState createState() => SearchOverlayState();
}

enum _ProfileMenuAction {
  login,
  myProperties,
  favorites,
  logout,
}

class SearchOverlayState extends State<SearchOverlay> {
  final MobileBffMapApi _mapApi = MobileBffMapApi();
  final MobileBffSavedPropertiesApi _savedPropertiesApi =
      MobileBffSavedPropertiesApi();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _searchCardKey = GlobalKey();
  final GlobalKey _filterButtonKey = GlobalKey();

  Timer? _debounce;
  Timer? _keyboardShowTimer;

  final List<AutocompletePrediction> _predictions = <AutocompletePrediction>[];
  List<RecentPlace> _recentPlaces = <RecentPlace>[];

  bool _isLoading = false;
  bool _isCompactMode = false;
  bool _suppressSuggestionAndRecentPanels = false;
  bool? _lastReportedOpen;

  /// Collapse the search bar to compact mode.
  ///
  /// Called externally when a property is selected (e.g. from deep link).
  void contract() {
    if (!mounted) return;
    if (_isCompactMode) return;
    setState(() {
      _isCompactMode = true;
      _predictions.clear();
    });
    _focusNode.unfocus();
    _keyboardShowTimer?.cancel();
    _reportOpenStateIfChanged();
  }

  bool get _shouldShowRecents {
    return !_suppressSuggestionAndRecentPanels &&
        !_isCompactMode &&
        _controller.text.trim().isEmpty &&
        _recentPlaces.isNotEmpty;
  }

  bool get _shouldShowSuggestions {
    return !_suppressSuggestionAndRecentPanels &&
        !_isCompactMode &&
        _predictions.isNotEmpty;
  }

  bool _computeIsOpen() {
    if (_isCompactMode) return false;
    return _focusNode.hasFocus || _shouldShowRecents || _shouldShowSuggestions;
  }

  void _reportOpenStateIfChanged() {
    final onOpenChanged = widget.onOpenChanged;
    if (onOpenChanged == null) return;

    final isOpen = _computeIsOpen();
    if (_lastReportedOpen == isOpen) return;
    _lastReportedOpen = isOpen;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onOpenChanged?.call(isOpen);
    });
  }

  Future<void> showMyPropertiesPopup() async {
    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      ToastMessage.show(context, 'Please login to view your properties.');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MyPropertiesDialog(
        bearerToken: token,
        mapApi: _mapApi,
        getMapCenter: widget.getMapCenter,
        getMapZoom: widget.getMapZoom,
        onMyPropertySelected: widget.onMyPropertySelected,
        onMyPropertyDeleted: widget.onMyPropertyDeleted,
        onOpened: widget.onMyPropertiesOpened,
      ),
    );
  }

  Future<void> showFavoritesPopup() async {
    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      ToastMessage.show(context, 'Please login to view shortlisted.');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => FavoritesDialog(
        bearerToken: token,
        savedPropertiesApi: _savedPropertiesApi,
        onPlaceSelected:
            widget.onShortlistedPlaceSelected ?? widget.onPlaceSelected,
        onSavedPropertySelected: widget.onShortlistedPropertySelected,
        onOpened: widget.onMyPropertiesOpened,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRecentPlaces();

    _focusNode.addListener(_reportOpenStateIfChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusSearchField(forceKeyboard: true);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_reportOpenStateIfChanged);
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

    if (_suppressSuggestionAndRecentPanels) {
      setState(() {
        _suppressSuggestionAndRecentPanels = false;
      });
    }

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

      // Track search selection (fire-and-forget, no UI impact).
      AnalyticsService.instance.logMapSearch(query: label);

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
    _reportOpenStateIfChanged();

    final bool showBrandHeader = !_isCompactMode;
    final bool showCompactRLogoInSearchBar = _isCompactMode;
    final double searchCardRadius = _isCompactMode ? 6 : 8;

    final Widget searchCard = Container(
      key: _searchCardKey,
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
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search for places...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                    ),
                    onChanged: _onQueryChanged,
                    onTap: () {
                      widget.onSearchTap?.call();
                      if (_suppressSuggestionAndRecentPanels) {
                        setState(() {
                          _suppressSuggestionAndRecentPanels = false;
                        });
                      }
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
                        _suppressSuggestionAndRecentPanels = false;
                      });
                      _enterExpandedMode();
                      _onQueryChanged('');
                    },
                  ),
                IconButton(
                  key: _filterButtonKey,
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
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    _keyboardShowTimer?.cancel();
                    SystemChannels.textInput.invokeMethod('TextInput.hide');

                    final hasRecentsPanel = !_isCompactMode &&
                        _controller.text.trim().isEmpty &&
                        _recentPlaces.isNotEmpty;
                    final hasSuggestionsPanel =
                        !_isCompactMode && _predictions.isNotEmpty;

                    if (hasRecentsPanel || hasSuggestionsPanel) {
                      // Collapse panels first, then measure the search card
                      // after layout so the filter popover anchors tightly to
                      // the search box.
                      setState(() {
                        _suppressSuggestionAndRecentPanels = true;
                        _predictions.clear();
                        _isLoading = false;
                      });

                      // Wait for the next frame so RenderBox sizes/positions
                      // reflect the collapsed search card.
                      await WidgetsBinding.instance.endOfFrame;
                      if (!mounted) return;
                    }

                    final searchBoxContext = _searchCardKey.currentContext;
                    final panelBox =
                        searchBoxContext?.findRenderObject() as RenderBox?;
                    if (panelBox == null) return;

                    final filterBoxContext = _filterButtonKey.currentContext;
                    final arrowBox =
                        filterBoxContext?.findRenderObject() as RenderBox?;
                    if (arrowBox == null) return;

                    final panelTopLeft = panelBox.localToGlobal(Offset.zero);
                    final arrowTopLeft = arrowBox.localToGlobal(Offset.zero);
                    widget.onFilterTap?.call(
                      panelTopLeft & panelBox.size,
                      arrowTopLeft & arrowBox.size,
                    );
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
          else if (!_suppressSuggestionAndRecentPanels &&
              _predictions.isNotEmpty) ...[
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
          _CompactProfileButton(favoritesCount: widget.favoritesCount),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(243, 244, 246, 1.0),
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 14),
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

class _CompactProfileButton extends StatefulWidget {
  const _CompactProfileButton({this.favoritesCount});

  final int? favoritesCount;

  @override
  State<_CompactProfileButton> createState() => _CompactProfileButtonState();
}

class _CompactProfileButtonState extends State<_CompactProfileButton> {
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _handleTap() async {
    final auth = AuthScope.of(context);
    final session = auth.session;

    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = offset & renderBox.size;

    final selected = await _showProfileMenuPopover(
      context: context,
      anchorRect: rect,
      session: session,
      favoritesCount: widget.favoritesCount,
    );
    if (!mounted || selected == null) {
      return;
    }

    switch (selected) {
      case _ProfileMenuAction.login:
        AuthDialog.showLogin(context);
        break;
      case _ProfileMenuAction.myProperties:
        final overlayState =
            context.findAncestorStateOfType<SearchOverlayState>();
        overlayState?.showMyPropertiesPopup();
        break;
      case _ProfileMenuAction.favorites:
        final overlayState =
            context.findAncestorStateOfType<SearchOverlayState>();
        overlayState?.showFavoritesPopup();
        break;
      case _ProfileMenuAction.logout:
        auth.logout().then((_) {
          if (!mounted) return;
          ToastMessage.show(context, 'Logged out');
        }).catchError((_) {
          if (!mounted) return;
          ToastMessage.show(context, 'Logout failed');
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        key: _buttonKey,
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
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                SystemChannels.textInput.invokeMethod('TextInput.hide');
                _handleTap();
              },
              child: const Center(
                child: Icon(
                  Icons.person_outline,
                  color: Color(0xFF0FAD97),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_ProfileMenuAction?> _showProfileMenuPopover({
  required BuildContext context,
  required Rect anchorRect,
  required AuthSession? session,
  int? favoritesCount,
}) async {
  if (!context.mounted) return null;

  const horizontalPadding = 16.0;
  const arrowWidth = 18.0;
  const arrowHeight = 10.0;
  const arrowOverlapIntoPopup = 3.0;
  const popupWidth = 220.0;
  const popupGap = 9.0;
  const popupOverlapIntoAnchor = 0.0;

  return showGeneralDialog<_ProfileMenuAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Profile menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, __) {
      final media = MediaQuery.of(context);
      final geometry = AnchoredPopoverGeometry.compute(
        media: media,
        popupAnchorRect: anchorRect,
        arrowAnchorRect: anchorRect,
        horizontalPadding: horizontalPadding,
        popupWidth: popupWidth,
        arrowWidth: arrowWidth,
        popupGap: popupGap,
        popupOverlapIntoAnchor: popupOverlapIntoAnchor,
      );

      final fullName = session == null
          ? ''
          : '${session.user.firstName} ${session.user.lastName}'.trim();
      final displayName = session == null
          ? ''
          : (fullName.isEmpty ? session.user.phoneNumber : fullName);

      Widget buildItem({
        required IconData icon,
        required String label,
        required _ProfileMenuAction action,
        int? badgeCount,
      }) {
        return InkWell(
          onTap: () => Navigator.of(context).pop(action),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: const Color(0xFF334155)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        badgeCount.toString(),
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onScaleStart: (_) => Navigator.of(context).pop(),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                top: geometry.popupTop,
                left: geometry.popupLeft,
                width: popupWidth,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    elevation: 10,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (session != null) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: SizedBox(
                                height: 36,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Hi, $displayName',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE2E8F0),
                            ),
                            const SizedBox(height: 6),
                            buildItem(
                              icon: Icons.business_outlined,
                              label: 'My Properties',
                              action: _ProfileMenuAction.myProperties,
                            ),
                            buildItem(
                              icon: Icons.favorite_border,
                              label: 'Shortlisted',
                              action: _ProfileMenuAction.favorites,
                              badgeCount: favoritesCount,
                            ),
                            buildItem(
                              icon: Icons.logout,
                              label: 'Logout',
                              action: _ProfileMenuAction.logout,
                            ),
                          ] else ...[
                            buildItem(
                              icon: Icons.login,
                              label: 'Login',
                              action: _ProfileMenuAction.login,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: geometry.popupTop - arrowHeight + arrowOverlapIntoPopup,
                left: geometry.arrowLeft,
                child: const IgnorePointer(
                  child: _ProfilePopoverArrow(
                    width: arrowWidth,
                    height: arrowHeight,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.02),
            end: Offset.zero,
          ).animate(fade),
          child: child,
        ),
      );
    },
  );
}

class _ProfilePopoverArrow extends StatelessWidget {
  const _ProfilePopoverArrow({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ProfilePopoverArrowPainter(color),
    );
  }
}

class _ProfilePopoverArrowPainter extends CustomPainter {
  _ProfilePopoverArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ProfilePopoverArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
