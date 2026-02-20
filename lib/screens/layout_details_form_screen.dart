import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';

import '../constants/api_constants.dart';
import '../constants/search_constants.dart';
import '../services/mobile_bff_layouts_api.dart';
import '../state/auth_scope.dart';
import '../widgets/api_key_missing_banner.dart';
import '../widgets/layout_qr_code_sheet.dart';
import '../widgets/toast_message.dart';

/// Screen for admin users to create a new layout by drawing boundary and filling details.
class LayoutDetailsFormScreen extends StatefulWidget {
  const LayoutDetailsFormScreen({
    super.key,
    this.initialCenter,
    this.initialZoom,
  });

  final LatLng? initialCenter;
  final double? initialZoom;

  @override
  State<LayoutDetailsFormScreen> createState() =>
      _LayoutDetailsFormScreenState();
}

class _LayoutDetailsFormScreenState extends State<LayoutDetailsFormScreen> {
  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629); // India

  late final LatLng _center;
  late final double _zoom;
  List<LatLng> _boundaryPoints = <LatLng>[];

  final MobileBffLayoutsApi _layoutsApi = MobileBffLayoutsApi();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  GooglePlace? _googlePlace;
  Timer? _searchDebounce;
  int _autocompleteSeq = 0;
  bool _isAutocompleteLoading = false;
  final List<AutocompletePrediction> _predictions = <AutocompletePrediction>[];

  GoogleMapController? _controller;

  MapType _mapType = MapType.hybrid;
  String? _lightMapStyle;

  // Form fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _surveyNumberController = TextEditingController();
  final TextEditingController _approvalNumberController =
      TextEditingController();
  final TextEditingController _locationDetailsController =
      TextEditingController();
  final TextEditingController _additionalDetailsController =
      TextEditingController();
  final TextEditingController _contactNumbersController =
      TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _plotsCountController = TextEditingController();

  bool _isSaving = false;
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMapStyle());

    _center = widget.initialCenter ?? _fallbackCenter;
    _zoom = widget.initialZoom ?? 16;

    final key = googlePlacesApiKey.trim();
    if (key.isNotEmpty && key != 'YOUR_GOOGLE_PLACES_API_KEY') {
      _googlePlace = GooglePlace(key);
    }

    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && mounted) {
        setState(() {
          _predictions.clear();
          _isAutocompleteLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _nameController.dispose();
    _areaController.dispose();
    _surveyNumberController.dispose();
    _approvalNumberController.dispose();
    _locationDetailsController.dispose();
    _additionalDetailsController.dispose();
    _contactNumbersController.dispose();
    _descriptionController.dispose();
    _plotsCountController.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style =
        await rootBundle.loadString('assets/map_light.json').catchError((_) {
      return '';
    });
    if (mounted) {
      setState(() {
        _lightMapStyle = style;
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _boundaryPoints = [..._boundaryPoints, point];
    });
  }

  void _undoLastPoint() {
    if (_boundaryPoints.isEmpty) return;
    setState(() {
      _boundaryPoints = _boundaryPoints.sublist(0, _boundaryPoints.length - 1);
    });
  }

  void _clearAllPoints() {
    if (_boundaryPoints.isEmpty) return;
    setState(() {
      _boundaryPoints = <LatLng>[];
    });
  }

  void _toggleMapType() {
    setState(() {
      if (_mapType == MapType.hybrid) {
        _mapType = MapType.normal;
      } else {
        _mapType = MapType.hybrid;
      }
    });
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions.clear();
        _isAutocompleteLoading = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchAutocomplete(query);
    });
  }

  Future<void> _fetchAutocomplete(String query) async {
    final place = _googlePlace;
    if (place == null) return;

    final requestSeq = ++_autocompleteSeq;
    setState(() {
      _isAutocompleteLoading = true;
    });

    try {
      final result = await place.autocomplete.get(
        query,
        components: [Component('country', 'in')],
      );
      if (!mounted || requestSeq != _autocompleteSeq) return;

      setState(() {
        _predictions.clear();
        _predictions.addAll(result?.predictions ?? []);
        _isAutocompleteLoading = false;
      });
    } catch (_) {
      if (!mounted || requestSeq != _autocompleteSeq) return;
      setState(() {
        _isAutocompleteLoading = false;
      });
    }
  }

  Future<void> _onPredictionSelected(AutocompletePrediction prediction) async {
    _searchFocusNode.unfocus();
    final place = _googlePlace;
    if (place == null) return;

    final placeId = prediction.placeId;
    if (placeId == null) return;

    try {
      final details = await place.details.get(placeId);
      final loc = details?.result?.geometry?.location;
      if (loc != null && _controller != null) {
        await _controller!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(loc.lat!, loc.lng!), 18),
        );
      }
    } catch (_) {
      // ignore
    }

    setState(() {
      _searchController.clear();
      _predictions.clear();
    });
  }

  void _proceedToForm() {
    if (_boundaryPoints.length < 3) {
      ToastMessage.show(context, 'Draw at least 3 points to define boundary');
      return;
    }
    setState(() {
      _showForm = true;
    });
  }

  void _backToMap() {
    setState(() {
      _showForm = false;
    });
  }

  Future<void> _saveLayout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ToastMessage.show(context, 'Please enter a layout name');
      return;
    }

    if (_boundaryPoints.length < 3) {
      ToastMessage.show(context, 'Layout boundary must have at least 3 points');
      return;
    }

    final token = AuthScope.of(context).session?.token;
    if (token == null || token.isEmpty) {
      ToastMessage.show(context, 'Please login to create a layout');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Convert LatLng list to [[lat, lng], ...] array
      final boundaryLatLng = _boundaryPoints
          .map((p) => [p.latitude, p.longitude])
          .toList(growable: false);

      final plotsCountText = _plotsCountController.text.trim();
      final plotsCount =
          plotsCountText.isNotEmpty ? int.tryParse(plotsCountText) : null;

      final response = await _layoutsApi.createLayoutDraft(
        name: name,
        boundaryLatLng: boundaryLatLng,
        area: _areaController.text.trim(),
        surveyNumber: _surveyNumberController.text.trim(),
        approvalNumber: _approvalNumberController.text.trim(),
        locationDetails: _locationDetailsController.text.trim(),
        additionalDetails: _additionalDetailsController.text.trim(),
        contactNumbers: _contactNumbersController.text.trim(),
        description: _descriptionController.text.trim(),
        plotsCount: plotsCount,
        bearerToken: token,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ToastMessage.show(context, 'Layout created successfully!');

      // Show QR code sheet
      await _showQrCodeSheet(response);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on LayoutsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, 'Failed to create layout');
    }
  }

  Future<void> _showQrCodeSheet(LayoutDraftResponse layout) async {
    final shareUrl = _buildShareUrl(layout.id, layout.shortCode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LayoutQrCodeSheet(
        layoutId: layout.id,
        layoutName: layout.name,
        shareUrl: shareUrl,
      ),
    );
  }

  String _buildShareUrl(String layoutId, [String? shortCode]) {
    final base = ApiConstants.webBaseUrl.replaceAll(RegExp(r'/$'), '');
    // Use short URL if available for cleaner QR codes
    if (shortCode != null && shortCode.isNotEmpty) {
      return '$base/s/$shortCode';
    }
    return '$base/property/Layout/$layoutId';
  }

  Set<Polygon> _buildPolygons() {
    if (_boundaryPoints.length < 3) return const <Polygon>{};

    return <Polygon>{
      Polygon(
        polygonId: const PolygonId('layout_boundary'),
        points: _boundaryPoints,
        strokeWidth: 3,
        strokeColor: const Color(0xFF1D4ED8),
        fillColor: const Color(0xFF2563EB).withOpacity(0.20),
        consumeTapEvents: false,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < _boundaryPoints.length; i++) {
      markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: _boundaryPoints[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          anchor: const Offset(0.5, 0.5),
          draggable: true,
          onDrag: (newPos) {
            setState(() {
              _boundaryPoints = List<LatLng>.from(_boundaryPoints)
                ..[i] = newPos;
            });
          },
          onDragEnd: (newPos) {
            setState(() {
              _boundaryPoints = List<LatLng>.from(_boundaryPoints)
                ..[i] = newPos;
            });
          },
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_boundaryPoints.length < 2) return const <Polyline>{};

    // Draw lines between consecutive points (open path while drawing)
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('boundary_outline'),
        points: _boundaryPoints,
        color: const Color(0xFF1D4ED8),
        width: 3,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final keyAvailable = googlePlacesApiKey.trim().isNotEmpty &&
        googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY';

    if (_showForm) {
      return _buildFormView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Layout Boundary'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_boundaryPoints.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last point',
              onPressed: _undoLastPoint,
            ),
          if (_boundaryPoints.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear all',
              onPressed: _clearAllPoints,
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: _zoom,
            ),
            mapType: _mapType,
            style: _mapType == MapType.normal ? _lightMapStyle : null,
            onMapCreated: (controller) {
              _controller = controller;
            },
            onTap: _onMapTap,
            polygons: _buildPolygons(),
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),

          // API key warning
          if (!keyAvailable)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ApiKeyMissingBanner(),
            ),

          // Search bar
          if (keyAvailable)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search location...',
                        prefixIcon: _isAutocompleteLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _predictions.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_predictions.isNotEmpty)
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _predictions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final pred = _predictions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(
                              pred.structuredFormatting?.mainText ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              pred.structuredFormatting?.secondaryText ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onPredictionSelected(pred),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // Map controls
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              children: [
                _mapControlButton(
                  icon: _mapType == MapType.hybrid
                      ? Icons.map_outlined
                      : Icons.satellite_alt,
                  tooltip: 'Toggle map type',
                  onTap: _toggleMapType,
                ),
                const SizedBox(height: 8),
                _mapControlButton(
                  icon: Icons.my_location,
                  tooltip: 'My location',
                  onTap: () async {
                    // Re-center to current location
                    // For now just reset to initial center
                    await _controller?.animateCamera(
                      CameraUpdate.newLatLngZoom(_center, _zoom),
                    );
                  },
                ),
              ],
            ),
          ),

          // Instructions and point count
          Positioned(
            left: 12,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x20000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tap on map to draw boundary',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Points: ${_boundaryPoints.length}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _boundaryPoints.length >= 3
                          ? const Color(0xFF059669)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Next button
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton(
              onPressed: _boundaryPoints.length >= 3 ? _proceedToForm : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0FAD97),
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Next: Fill Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              color: const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layout Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _backToMap,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Boundary preview card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF059669),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Boundary Drawn',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          '${_boundaryPoints.length} points',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _backToMap,
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Name field (required)
            _buildTextField(
              controller: _nameController,
              label: 'Layout Name *',
              hint: 'Enter layout name',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Area and Plot Count row
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _areaController,
                    label: 'Area',
                    hint: 'e.g., 10 Acres',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _plotsCountController,
                    label: 'Plot Count',
                    hint: 'e.g., 120',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Survey Number
            _buildTextField(
              controller: _surveyNumberController,
              label: 'Survey Number',
              hint: 'Enter survey number',
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Approval Number
            _buildTextField(
              controller: _approvalNumberController,
              label: 'Approval Number',
              hint: 'Enter approval number',
            ),
            const SizedBox(height: 16),

            // Location Details
            _buildTextField(
              controller: _locationDetailsController,
              label: 'Location Details',
              hint: 'Enter location/address',
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Contact Numbers
            _buildTextField(
              controller: _contactNumbersController,
              label: 'Contact Numbers',
              hint: 'e.g., 9876543210, 9988776655',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Additional Details
            _buildTextField(
              controller: _additionalDetailsController,
              label: 'Additional Details',
              hint: 'Any additional information',
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Description
            _buildTextField(
              controller: _descriptionController,
              label: 'Description',
              hint: 'Marketing description (optional)',
              maxLines: 4,
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton(
              onPressed: _isSaving ? null : _saveLayout,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0FAD97),
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save & Generate QR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF0FAD97), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
