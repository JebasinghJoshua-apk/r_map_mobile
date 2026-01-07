import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

import '../constants/search_constants.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/search_overlay.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  GoogleMapController? _mapController;
  GooglePlace? _googlePlace;
  String? _lightMapStyle;

  static const String _lightMapStyleAssetPath = 'assets/map_light.json';

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(37.4221, -122.0841),
    zoom: 14,
  );

  final Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId('default-marker'),
      position: LatLng(37.4221, -122.0841),
      infoWindow: InfoWindow(title: 'R Map Home Base'),
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadLightMapStyle();
    if (googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(googlePlacesApiKey);
    }
  }

  Future<void> _loadLightMapStyle() async {
    try {
      final style = await rootBundle.loadString(_lightMapStyleAssetPath);
      if (!mounted) return;
      setState(() {
        _lightMapStyle = style;
      });
    } catch (e) {
      debugPrint('Failed to load map style: $e');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
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

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            style: _lightMapStyle,
            markers: _markers,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
          ),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _googlePlace == null
                ? const ApiKeyMissingBanner()
                : SearchOverlay(
                    googlePlace: _googlePlace!,
                    onPlaceSelected: _moveCameraTo,
                  ),
          ),
        ],
      ),
    );
  }
}
