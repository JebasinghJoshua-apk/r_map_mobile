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
  MapType _mapType = MapType.normal;
  final ValueNotifier<double> _zoomNotifier =
      ValueNotifier(_initialCameraPosition.zoom);

  static const double _hybridZoomEnter = 19.0;
  static const double _hybridZoomExit = 18.7;

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
    _zoomNotifier.dispose();
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

  void _toggleSatelliteMode() {
    setState(() {
      _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            onCameraMove: (position) {
              _zoomNotifier.value = position.zoom;

              final shouldBeHybrid = _mapType == MapType.hybrid
                  ? position.zoom >= _hybridZoomExit
                  : position.zoom >= _hybridZoomEnter;

              final nextMapType =
                  shouldBeHybrid ? MapType.hybrid : MapType.normal;
              if (nextMapType != _mapType) {
                setState(() {
                  _mapType = nextMapType;
                });
              }
            },
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
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
          Positioned(
            left: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'satellite-toggle',
              onPressed: _toggleSatelliteMode,
              tooltip: _mapType == MapType.hybrid
                  ? 'Switch to map view'
                  : 'Switch to satellite view',
              child: Icon(
                _mapType == MapType.hybrid
                    ? Icons.map_outlined
                    : Icons.satellite_alt_outlined,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: ValueListenableBuilder<double>(
              valueListenable: _zoomNotifier,
              builder: (context, zoom, _) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      'Zoom: ${zoom.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
