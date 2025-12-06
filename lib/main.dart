import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: _initialCameraPosition,
        onMapCreated: _onMapCreated,
        markers: _markers,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
      ),
    );
  }
}
