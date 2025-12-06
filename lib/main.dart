import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

const String _googlePlacesApiKey = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: 'AIzaSyCY-mEvaGFsjSCLSNruAE2jNtfEKOYmgTU',
);

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

  static final CameraPosition _initialCameraPosition = const CameraPosition(
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
  Timer? _debounce;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _predictions.clear();
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      setState(() => _isLoading = true);
      final response = await widget.googlePlace.autocomplete.get(
        value,
        types: 'establishment',
      );
      setState(() {
        _predictions
          ..clear()
          ..addAll(response?.predictions ?? []);
        _isLoading = false;
      });
    });
  }

  Future<void> _handlePredictionTap(AutocompletePrediction prediction) async {
    final placeId = prediction.placeId;
    if (placeId == null) return;
    setState(() => _isLoading = true);
    final details = await widget.googlePlace.details.get(
      placeId,
      fields: 'name,formatted_address,geometry/location',
    );
    setState(() => _isLoading = false);

    final location = details?.result?.geometry?.location;
    if (location == null) return;

    final label = details?.result?.name ?? prediction.description ?? 'Selected';
    final latLng = LatLng(location.lat ?? 0, location.lng ?? 0);

    widget.onPlaceSelected(latLng, label);
    setState(() {
      _controller.text = label;
      _predictions.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 16,
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
                if (_predictions.isNotEmpty)
                  const Divider(
                      height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                if (_predictions.isNotEmpty)
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
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on,
                              color: Color(0xFF0FAD97)),
                          title: Text(
                            prediction.structuredFormatting?.mainText ??
                                prediction.description ??
                                '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          subtitle:
                              prediction.structuredFormatting?.secondaryText !=
                                      null
                                  ? Text(
                                      prediction.structuredFormatting
                                              ?.secondaryText ??
                                          '',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF475467)),
                                    )
                                  : null,
                          onTap: () => _handlePredictionTap(prediction),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
