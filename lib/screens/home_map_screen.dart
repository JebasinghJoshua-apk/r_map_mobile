import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

import '../constants/search_constants.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/search_overlay.dart';
import '../widgets/toast_message.dart';
import '../models/map_viewport_models.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  GoogleMapController? _mapController;
  GooglePlace? _googlePlace;
  late final MobileBffMapApi _mapApi;
  String? _lightMapStyle;
  MapType _mapType = MapType.normal;
  final ValueNotifier<double> _zoomNotifier =
      ValueNotifier(_initialCameraPosition.zoom);

  bool _isViewportLoading = false;
  Timer? _viewportLoadingTimer;

  final LinkedHashMap<String, _ViewportRenderCacheEntry> _viewportCache =
      LinkedHashMap<String, _ViewportRenderCacheEntry>();
  static const int _viewportCacheMaxEntries = 24;
  static const Duration _viewportCacheTtl = Duration(seconds: 30);

  CameraPosition _lastCameraPosition = _initialCameraPosition;
  double? _effectiveZoom;
  Timer? _viewportDebounceTimer;
  int _viewportRequestSeq = 0;
  String? _lastViewportSignature;
  DateTime? _lastViewportErrorAt;

  static const double _styleZoomMinDelta = 0.25;
  static const double _overlayRetentionMultiplier = 1.75;

  static const double _hybridZoomEnter = 19.0;
  static const double _hybridZoomExit = 18.7;

  static const String _lightMapStyleAssetPath = 'assets/map_light.json';

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(37.4221, -122.0841),
    zoom: 14,
  );

  Set<Marker> _viewportMarkers = <Marker>{};
  Marker? _selectedPlaceMarker;

  Set<Polygon> _plotPolygons = <Polygon>{};
  Set<Polygon> _amenityPolygons = <Polygon>{};
  Set<Polygon> _roadPolygons = <Polygon>{};
  Set<Polyline> _roadPolylines = <Polyline>{};

  static const double _minPlotPolygonZoom = 16.2;
  static const double _minRoadOverlayZoom = 16.0;

  @override
  void initState() {
    super.initState();
    _mapApi = MobileBffMapApi();
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
    _viewportDebounceTimer?.cancel();
    _viewportLoadingTimer?.cancel();
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
      _selectedPlaceMarker = Marker(
        markerId: const MarkerId('selected-place'),
        position: target,
        infoWindow: InfoWindow(title: label),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraIdle() {
    if (_mapController == null) return;

    _viewportDebounceTimer?.cancel();
    _viewportDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      await _fetchViewport();
    });
  }

  void _setViewportLoading(bool value) {
    if (!mounted) return;

    // Small delay avoids spinner flicker on fast cache hits.
    if (value) {
      _viewportLoadingTimer?.cancel();
      _viewportLoadingTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        setState(() => _isViewportLoading = true);
      });
      return;
    }

    _viewportLoadingTimer?.cancel();
    if (_isViewportLoading) {
      setState(() => _isViewportLoading = false);
    }
  }

  _ViewportRenderCacheEntry? _tryGetCachedViewport(String signature) {
    final entry = _viewportCache.remove(signature);
    if (entry == null) return null;
    final isFresh =
        DateTime.now().difference(entry.createdAt) <= _viewportCacheTtl;
    if (!isFresh) {
      return null;
    }

    // Reinsert to mark as most recently used.
    _viewportCache[signature] = entry;
    return entry;
  }

  void _putCachedViewport(String signature, _ViewportRenderCacheEntry entry) {
    _viewportCache.remove(signature);
    _viewportCache[signature] = entry;

    while (_viewportCache.length > _viewportCacheMaxEntries) {
      _viewportCache.remove(_viewportCache.keys.first);
    }
  }

  Future<void> _fetchViewport() async {
    final controller = _mapController;
    if (controller == null) return;

    final token = AuthScope.of(context).session?.token;

    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }

    final zoom = _effectiveZoom ?? _lastCameraPosition.zoom;
    const propertyTypes = <String>[];

    final expandedBounds = _expandBounds(bounds, _overlayRetentionMultiplier);

    final signature =
        _buildViewportSignature(expandedBounds, zoom, propertyTypes);
    if (signature == _lastViewportSignature) {
      return;
    }
    _lastViewportSignature = signature;

    final cached = _tryGetCachedViewport(signature);
    if (cached != null) {
      setState(() {
        _viewportMarkers = cached.markers;
        _plotPolygons = cached.plotPolygons;
        _amenityPolygons = cached.amenityPolygons;
        _roadPolygons = cached.roadPolygons;
        _roadPolylines = cached.roadPolylines;
      });
      return;
    }

    final requestId = ++_viewportRequestSeq;

    _setViewportLoading(true);

    try {
      final response = await _mapApi.getViewport(
        bounds: expandedBounds,
        zoom: zoom,
        propertyTypes: propertyTypes,
        bearerToken: token,
      );

      if (!mounted || requestId != _viewportRequestSeq) {
        _setViewportLoading(false);
        return;
      }

      final rendered = _renderViewport(
        response: response,
        zoom: _lastCameraPosition.zoom,
      );
      _putCachedViewport(signature, rendered);

      setState(() {
        _viewportMarkers = rendered.markers;
        _plotPolygons = rendered.plotPolygons;
        _amenityPolygons = rendered.amenityPolygons;
        _roadPolygons = rendered.roadPolygons;
        _roadPolylines = rendered.roadPolylines;
      });
      _setViewportLoading(false);
    } catch (e) {
      if (!mounted || requestId != _viewportRequestSeq) {
        _setViewportLoading(false);
        return;
      }

      _setViewportLoading(false);
      final now = DateTime.now();
      final lastError = _lastViewportErrorAt;
      if (lastError == null || now.difference(lastError).inSeconds >= 8) {
        _lastViewportErrorAt = now;
        ToastMessage.show(context, e.toString());
      }
    }
  }

  _ViewportRenderCacheEntry _renderViewport({
    required MapViewportResponse response,
    required double zoom,
  }) {
    final nextMarkers = <Marker>{};
    for (final feature in response.properties) {
      final center = feature.centerPoint;
      if (center == null) continue;

      final title = feature.name.trim().isEmpty
          ? (feature.propertyType.trim().isEmpty
              ? 'Property'
              : feature.propertyType)
          : feature.name;

      nextMarkers.add(
        Marker(
          markerId: MarkerId('property:${feature.propertyId}'),
          position: center,
          infoWindow: InfoWindow(
            title: title,
            snippet: feature.listingType,
          ),
        ),
      );
    }

    final shouldShowPolygons = zoom >= _minPlotPolygonZoom;
    final shouldShowRoads = zoom >= _minRoadOverlayZoom;
    final nextPlotPolygons = <Polygon>{};
    final nextAmenityPolygons = <Polygon>{};
    final nextRoadPolygons = <Polygon>{};
    final nextRoadPolylines = <Polyline>{};

    if (shouldShowPolygons) {
      for (final plot in response.plots) {
        final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextPlotPolygons.add(
            Polygon(
              polygonId: PolygonId('plot:${plot.plotId}:$i'),
              points: points,
              strokeWidth: 2,
              strokeColor: const Color(0xFF0B5FA5),
              fillColor: const Color(0x550B5FA5),
              consumeTapEvents: false,
            ),
          );
        }
      }

      for (final amenity in response.amenities) {
        final polygons = GeoJson.tryParsePolygons(amenity.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextAmenityPolygons.add(
            Polygon(
              polygonId: PolygonId('amenity:${amenity.amenityId}:$i'),
              points: points,
              strokeWidth: 2,
              strokeColor: const Color(0xFF6A1B9A),
              fillColor: const Color(0x556A1B9A),
              consumeTapEvents: false,
            ),
          );
        }
      }
    }

    if (shouldShowRoads) {
      for (final road in response.roads) {
        final lines = GeoJson.tryParseLineStrings(road.roadGeoJson);

        if (lines.isNotEmpty) {
          for (var i = 0; i < lines.length; i++) {
            final points = lines[i];
            if (points.length < 2) continue;

            // Rough width scaling: keep readable at common zooms.
            final width = (road.widthInFeet ?? 12) >= 20 ? 5 : 3;
            nextRoadPolylines.add(
              Polyline(
                polylineId: PolylineId('road:${road.roadId}:$i'),
                points: points,
                width: width,
                color: const Color(0xFF4A4A4A),
                geodesic: true,
              ),
            );
          }
          continue;
        }

        // Fallback: some datasets may encode roads as Polygon/MultiPolygon.
        final roadPolygons = GeoJson.tryParsePolygons(road.roadGeoJson);
        for (var i = 0; i < roadPolygons.length; i++) {
          final points = roadPolygons[i];
          if (points.length < 3) continue;
          nextRoadPolygons.add(
            Polygon(
              polygonId: PolygonId('roadpoly:${road.roadId}:$i'),
              points: points,
              strokeWidth: 1,
              strokeColor: const Color(0xFF4A4A4A),
              fillColor: const Color(0x554A4A4A),
              consumeTapEvents: false,
            ),
          );
        }
      }
    }

    return _ViewportRenderCacheEntry(
      markers: Set<Marker>.unmodifiable(nextMarkers),
      plotPolygons: Set<Polygon>.unmodifiable(nextPlotPolygons),
      amenityPolygons: Set<Polygon>.unmodifiable(nextAmenityPolygons),
      roadPolygons: Set<Polygon>.unmodifiable(nextRoadPolygons),
      roadPolylines: Set<Polyline>.unmodifiable(nextRoadPolylines),
    );
  }

  String _buildViewportSignature(
    LatLngBounds bounds,
    double zoom,
    List<String> propertyTypes,
  ) {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final filterSignature = propertyTypes
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return [
      minLat.toStringAsFixed(5),
      maxLat.toStringAsFixed(5),
      minLng.toStringAsFixed(5),
      maxLng.toStringAsFixed(5),
      zoom.toStringAsFixed(2),
      filterSignature.join(','),
    ].join('|');
  }

  void _toggleSatelliteMode() {
    setState(() {
      _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
    });
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double multiplier) {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();

    final expandedLatHalf = (latSpan == 0 ? 0.01 : latSpan) * multiplier / 2;
    final expandedLngHalf = (lngSpan == 0 ? 0.01 : lngSpan) * multiplier / 2;

    double clampLat(double v) => v.clamp(-90.0, 90.0).toDouble();
    double clampLng(double v) {
      var x = v;
      while (x > 180) {
        x -= 360;
      }
      while (x < -180) {
        x += 360;
      }
      return x;
    }

    final sw = LatLng(
      clampLat(centerLat - expandedLatHalf),
      clampLng(centerLng - expandedLngHalf),
    );
    final ne = LatLng(
      clampLat(centerLat + expandedLatHalf),
      clampLng(centerLng + expandedLngHalf),
    );

    final south = sw.latitude < ne.latitude ? sw.latitude : ne.latitude;
    final north = sw.latitude > ne.latitude ? sw.latitude : ne.latitude;
    final west = sw.longitude < ne.longitude ? sw.longitude : ne.longitude;
    final east = sw.longitude > ne.longitude ? sw.longitude : ne.longitude;

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      ..._viewportMarkers,
      if (_selectedPlaceMarker != null) _selectedPlaceMarker!,
    };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: _onMapCreated,
            onCameraMove: (position) {
              _lastCameraPosition = position;
              if (_effectiveZoom == null ||
                  (position.zoom - _effectiveZoom!).abs() >=
                      _styleZoomMinDelta) {
                _effectiveZoom = position.zoom;
              }
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
            onCameraIdle: _onCameraIdle,
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
            markers: markers,
            polygons: {
              ..._plotPolygons,
              ..._amenityPolygons,
              ..._roadPolygons,
            },
            polylines: _roadPolylines,
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
          if (_isViewportLoading)
            Positioned(
              right: 16,
              bottom: 64,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Loading…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewportRenderCacheEntry {
  _ViewportRenderCacheEntry({
    required this.markers,
    required this.plotPolygons,
    required this.amenityPolygons,
    required this.roadPolygons,
    required this.roadPolylines,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final Set<Marker> markers;
  final Set<Polygon> plotPolygons;
  final Set<Polygon> amenityPolygons;
  final Set<Polygon> roadPolygons;
  final Set<Polyline> roadPolylines;
  final DateTime createdAt;
}
