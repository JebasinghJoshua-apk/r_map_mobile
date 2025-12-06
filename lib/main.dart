import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _googlePlacesApiKey = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: 'AIzaSyCY-mEvaGFsjSCLSNruAE2jNtfEKOYmgTU',
);

const LatLon _tamilNaduBiasPoint = LatLon(11.1271, 78.6569);
const int _tamilNaduRadiusMeters =
    400000; // Covers Tamil Nadu while keeping results regional
const String _recentPlacesStorageKey = 'rmap_recent_places_v1';

void main() {
  runApp(const RMapApp());
}

class RMapApp extends StatelessWidget {
  const RMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeMapScreen(),
    );
  }
}

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  GoogleMapController? _mapController;
  GooglePlace? _googlePlace;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target:
        LatLng(37.4221, -122.0841), // Google HQ coordinates as a default view.
    zoom: 14,
  );

  final Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId('default-marker'),
      position: LatLng(37.4221, -122.0841),
      infoWindow: InfoWindow(title: 'R Map Home Base'),
    ),
  };

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  void initState() {
    super.initState();
    if (_googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(_googlePlacesApiKey);
    }
  }

  Future<void> _moveCameraTo(LatLng target, String label) async {
    if (_mapController == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16),
      ),
    );
    setState(() {
      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('selected-place'),
            position: target,
            infoWindow: InfoWindow(title: label),
          ),
        );
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            markers: _markers,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
          ),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _googlePlace == null
                ? const _ApiKeyMissingBanner()
                : _SearchOverlay(
                    googlePlace: _googlePlace!,
                    onPlaceSelected: _moveCameraTo,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchOverlay extends StatefulWidget {
  final GooglePlace googlePlace;
  final void Function(LatLng position, String label) onPlaceSelected;

  const _SearchOverlay({
    required this.googlePlace,
    required this.onPlaceSelected,
  });

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<AutocompletePrediction> _predictions = [];
  List<_RecentPlace> _recentPlaces = [];
  Timer? _debounce;
  bool _isLoading = false;

  bool get _shouldShowRecents =>
      _controller.text.isEmpty && _recentPlaces.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadRecentPlaces();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recentPlacesStorageKey) ?? [];
    final parsed = stored
        .map(_RecentPlace.fromJsonString)
        .whereType<_RecentPlace>()
        .toList();
    if (!mounted) return;
    setState(() {
      _recentPlaces = parsed;
    });
  }

  Future<void> _saveRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentPlacesStorageKey,
      _recentPlaces.map((place) => place.toJsonString()).toList(),
    );
  }

  Future<void> _clearRecentPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentPlacesStorageKey);
    if (!mounted) return;
    setState(() {
      _recentPlaces = [];
    });
  }

  Future<void> _upsertRecentPlace(_RecentPlace place) async {
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

  Future<void> _handleRecentTap(_RecentPlace place) async {
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
          location: _tamilNaduBiasPoint,
          radius: _tamilNaduRadiusMeters,
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

      widget.onPlaceSelected(latLng, label);
      if (!mounted) return true;
      setState(() {
        _controller.text = label;
        _predictions.clear();
      });
      FocusScope.of(context).unfocus();
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

  Future<void> _handlePredictionTap(AutocompletePrediction prediction) async {
    final placeId = prediction.placeId;
    if (placeId == null) return;

    final mainText =
        prediction.structuredFormatting?.mainText ?? prediction.description;
    final fallbackLabel = prediction.description ?? mainText ?? 'Selected';
    final success = await _selectPlace(placeId, fallbackLabel);
    if (success) {
      final recent = _RecentPlace(
        placeId: placeId,
        title: mainText ?? fallbackLabel,
        subtitle: prediction.structuredFormatting?.secondaryText ?? '',
      );
      await _upsertRecentPlace(recent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _controller.text.trim().isNotEmpty;
    final bool showBrandHeader = !hasQuery;

    final Widget searchCard = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.search, color: Colors.grey, size: 22),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search for places...',
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                ),
              IconButton(
                icon: const Icon(Icons.tune, color: Color(0xFF0FAD97)),
                onPressed: () {},
              ),
            ],
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
                        onPressed: () {
                          _clearRecentPlaces();
                        },
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
      return searchCard;
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
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
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
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
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

class _RecentPlace {
  final String placeId;
  final String title;
  final String subtitle;

  const _RecentPlace({
    required this.placeId,
    required this.title,
    required this.subtitle,
  });

  String get displayLabel => subtitle.isNotEmpty ? '$title $subtitle' : title;

  String toJsonString() => jsonEncode({
        'placeId': placeId,
        'title': title,
        'subtitle': subtitle,
      });

  static _RecentPlace? fromJsonString(String value) {
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      final placeId = map['placeId'] as String?;
      final title = map['title'] as String?;
      if (placeId == null || title == null) {
        return null;
      }
      return _RecentPlace(
        placeId: placeId,
        title: title,
        subtitle: map['subtitle'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class _ApiKeyMissingBanner extends StatelessWidget {
  const _ApiKeyMissingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Text(
        'Provide a Google Places API key using the '
        'GOOGLE_PLACES_API_KEY dart define to enable search.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.black54),
      ),
    );
  }
}
