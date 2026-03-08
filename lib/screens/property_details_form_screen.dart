import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/api_constants.dart';
import '../models/image_summary.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../utils/pending_map_focus.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/property_form/property_form.dart';
import '../widgets/toast_message.dart';

/// Screen for creating or editing property details.
class PropertyDetailsFormScreen extends StatefulWidget {
  const PropertyDetailsFormScreen({
    required this.boundaryPoints,
    this.propertyId,
    this.initialPropertyType,
    super.key,
  });

  /// The polygon boundary points for the property.
  final List<LatLng> boundaryPoints;

  /// If provided, the screen is in edit mode for this property.
  final String? propertyId;

  /// The initial property type to select.
  final String? initialPropertyType;

  @override
  State<PropertyDetailsFormScreen> createState() =>
      _PropertyDetailsFormScreenState();
}

class _PropertyDetailsFormScreenState extends State<PropertyDetailsFormScreen> {
  bool get _isEdit =>
      widget.propertyId != null && widget.propertyId!.trim().isNotEmpty;

  final MobileBffMapApi _api = MobileBffMapApi();
  final ImagePicker _imagePicker = ImagePicker();
  int _photoSequence = 0;

  bool _isSaving = false;
  bool _isPrefilling = false;
  bool _didPrefillFromEditPayload = false;
  int _prefillRevision = 0;

  String _propertyType = 'Plot';
  String _listingType = 'Sell';
  String? _errListingType;

  // Property type form states
  final PlotFormState _plotState = PlotFormState();
  final HouseFormState _houseState = HouseFormState();
  final ApartmentFormState _apartmentState = ApartmentFormState();
  final LandFormState _landState = LandFormState();
  final CommercialFormState _commercialState = CommercialFormState();

  // Title manually edited flags
  bool _plotTitleManuallyEdited = false;
  bool _houseTitleManuallyEdited = false;
  bool _apartmentTitleManuallyEdited = false;
  bool _landTitleManuallyEdited = false;
  bool _commercialTitleManuallyEdited = false;

  // Photo state
  final List<ImageSummary> _existingPhotos = <ImageSummary>[];
  final List<SelectedPhoto> _photos = <SelectedPhoto>[];
  bool _isLoadingExistingPhotos = false;
  bool _didLoadExistingPhotos = false;

  // Contact prefill flag
  bool _didPrefillContactFromUser = false;

  // Text controllers
  late final TextEditingController _plotTitleController;
  late final TextEditingController _houseTitleController;
  late final TextEditingController _apartmentTitleController;
  late final TextEditingController _landTitleController;
  late final TextEditingController _commercialTitleController;

  late final TextEditingController _plotPriceController;
  late final TextEditingController _housePriceController;
  late final TextEditingController _apartmentPriceController;
  late final TextEditingController _landPriceController;
  late final TextEditingController _commercialPriceController;

  late final TextEditingController _plotContactNameController;
  late final TextEditingController _plotContactNumberController;
  late final TextEditingController _houseContactNameController;
  late final TextEditingController _houseContactNumberController;
  late final TextEditingController _apartmentContactNameController;
  late final TextEditingController _apartmentContactNumberController;
  late final TextEditingController _landContactNameController;
  late final TextEditingController _landContactNumberController;
  late final TextEditingController _commercialContactNameController;
  late final TextEditingController _commercialContactNumberController;

  int get _totalPhotoCount => _existingPhotos.length + _photos.length;

  int get _remainingPhotoSlots {
    final remaining = kMaxPropertyPhotos - _totalPhotoCount;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPropertyType?.trim();
    _propertyType = kPropertyTypes.contains(initial) ? initial! : 'Plot';

    // Initialize controllers
    _plotTitleController = TextEditingController(text: _plotState.title);
    _houseTitleController = TextEditingController(text: _houseState.title);
    _apartmentTitleController =
        TextEditingController(text: _apartmentState.title);
    _landTitleController = TextEditingController(text: _landState.title);
    _commercialTitleController =
        TextEditingController(text: _commercialState.title);

    _plotPriceController = TextEditingController(text: _plotState.price);
    _housePriceController = TextEditingController(text: _houseState.price);
    _apartmentPriceController =
        TextEditingController(text: _apartmentState.price);
    _landPriceController = TextEditingController(text: _landState.price);
    _commercialPriceController =
        TextEditingController(text: _commercialState.price);

    _plotContactNameController =
        TextEditingController(text: _plotState.contactName);
    _plotContactNumberController =
        TextEditingController(text: _plotState.contactNumber);
    _houseContactNameController =
        TextEditingController(text: _houseState.contactName);
    _houseContactNumberController =
        TextEditingController(text: _houseState.contactNumber);
    _apartmentContactNameController =
        TextEditingController(text: _apartmentState.contactName);
    _apartmentContactNumberController =
        TextEditingController(text: _apartmentState.contactNumber);
    _landContactNameController =
        TextEditingController(text: _landState.contactName);
    _landContactNumberController =
        TextEditingController(text: _landState.contactNumber);
    _commercialContactNameController =
        TextEditingController(text: _commercialState.contactName);
    _commercialContactNumberController =
        TextEditingController(text: _commercialState.contactNumber);

    unawaited(_prefillFromEditPayloadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    unawaited(_prefillFromEditPayloadIfNeeded());

    final session = AuthScope.of(context).session;
    final user = session?.user;

    if (_didPrefillContactFromUser || user == null) {
      return;
    }

    final name = user.displayName.trim();
    final phone = user.phoneNumber.trim();

    bool changed = false;

    if (name.isNotEmpty) {
      _prefillContactName(name);
      changed = true;
    }

    if (phone.isNotEmpty) {
      _prefillContactNumber(phone);
      changed = true;
    }

    _didPrefillContactFromUser = true;
    if (changed) {
      setState(() {});
    }
  }

  void _prefillContactName(String name) {
    if (_plotContactNameController.text.trim().isEmpty) {
      _plotState.contactName = name;
      _setControllerText(_plotContactNameController, name);
    }
    if (_houseContactNameController.text.trim().isEmpty) {
      _houseState.contactName = name;
      _setControllerText(_houseContactNameController, name);
    }
    if (_apartmentContactNameController.text.trim().isEmpty) {
      _apartmentState.contactName = name;
      _setControllerText(_apartmentContactNameController, name);
    }
    if (_landContactNameController.text.trim().isEmpty) {
      _landState.contactName = name;
      _setControllerText(_landContactNameController, name);
    }
    if (_commercialContactNameController.text.trim().isEmpty) {
      _commercialState.contactName = name;
      _setControllerText(_commercialContactNameController, name);
    }
  }

  void _prefillContactNumber(String phone) {
    if (_plotContactNumberController.text.trim().isEmpty) {
      _plotState.contactNumber = phone;
      _setControllerText(_plotContactNumberController, phone);
    }
    if (_houseContactNumberController.text.trim().isEmpty) {
      _houseState.contactNumber = phone;
      _setControllerText(_houseContactNumberController, phone);
    }
    if (_apartmentContactNumberController.text.trim().isEmpty) {
      _apartmentState.contactNumber = phone;
      _setControllerText(_apartmentContactNumberController, phone);
    }
    if (_landContactNumberController.text.trim().isEmpty) {
      _landState.contactNumber = phone;
      _setControllerText(_landContactNumberController, phone);
    }
    if (_commercialContactNumberController.text.trim().isEmpty) {
      _commercialState.contactNumber = phone;
      _setControllerText(_commercialContactNumberController, phone);
    }
  }

  @override
  void dispose() {
    _plotTitleController.dispose();
    _houseTitleController.dispose();
    _apartmentTitleController.dispose();
    _landTitleController.dispose();
    _commercialTitleController.dispose();

    _plotPriceController.dispose();
    _housePriceController.dispose();
    _apartmentPriceController.dispose();
    _landPriceController.dispose();
    _commercialPriceController.dispose();

    _plotContactNameController.dispose();
    _plotContactNumberController.dispose();
    _houseContactNameController.dispose();
    _houseContactNumberController.dispose();
    _apartmentContactNameController.dispose();
    _apartmentContactNumberController.dispose();
    _landContactNameController.dispose();
    _landContactNumberController.dispose();
    _commercialContactNameController.dispose();
    _commercialContactNumberController.dispose();

    super.dispose();
  }

  void _setControllerText(TextEditingController controller, String text) {
    final value = controller.value;
    controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  String _absoluteMediaUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final base = ApiConstants.mobileBffBaseUrl;
    if (base.trim().isEmpty) return trimmed;

    final normalizedBase = base.endsWith('/') ? base : '$base/';
    final baseUri = Uri.parse(normalizedBase);
    final relative = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return baseUri.resolve(relative).toString();
  }

  //===========================================================================
  // Title Generation
  //===========================================================================

  String _generatePlotTitle() {
    final loc = _plotState.location.trim();
    if (loc.isEmpty) return 'Plot';
    return 'Plot in $loc';
  }

  String _generateHouseTitle() {
    final loc = _houseState.location.trim();
    final bedrooms = parseInt(_houseState.bedrooms);
    final bhk = (bedrooms != null && bedrooms > 0) ? '$bedrooms BHK ' : '';
    final base = '${bhk}Independent House'.trim();
    if (loc.isEmpty) return base.isEmpty ? 'Independent House' : base;
    return '$base in $loc';
  }

  String _generateApartmentTitle() {
    final loc = _apartmentState.location.trim();
    final bedrooms = parseInt(_apartmentState.bedrooms);
    final bhk = (bedrooms != null && bedrooms > 0) ? '$bedrooms BHK ' : '';
    final base = '${bhk}Apartment'.trim();
    if (loc.isEmpty) return base.isEmpty ? 'Apartment' : base;
    return '$base in $loc';
  }

  String _generateLandTitle() {
    final loc = _landState.location.trim();
    if (loc.isEmpty) return 'Land';
    return 'Land in $loc';
  }

  String _generateCommercialTitle() {
    final loc = _commercialState.location.trim();
    final space = _commercialState.spaceType.trim();
    final base = space.isEmpty ? 'Commercial Space' : space;
    if (loc.isEmpty) return base;
    return '$base in $loc';
  }

  void _applyPlotAutoTitle() {
    final generated = _generatePlotTitle().trim();
    if (generated.isEmpty) return;
    if (_plotTitleManuallyEdited && _plotState.title.trim().isNotEmpty) return;
    _plotState.title = generated;
    _setControllerText(_plotTitleController, generated);
    _plotState.errTitle = null;
  }

  void _applyHouseAutoTitle() {
    final generated = _generateHouseTitle().trim();
    if (generated.isEmpty) return;
    if (_houseTitleManuallyEdited && _houseState.title.trim().isNotEmpty) {
      return;
    }
    _houseState.title = generated;
    _setControllerText(_houseTitleController, generated);
    _houseState.errTitle = null;
  }

  void _applyApartmentAutoTitle() {
    final generated = _generateApartmentTitle().trim();
    if (generated.isEmpty) return;
    if (_apartmentTitleManuallyEdited &&
        _apartmentState.title.trim().isNotEmpty) {
      return;
    }
    _apartmentState.title = generated;
    _setControllerText(_apartmentTitleController, generated);
  }

  void _applyLandAutoTitle() {
    final generated = _generateLandTitle().trim();
    if (generated.isEmpty) return;
    if (_landTitleManuallyEdited && _landState.title.trim().isNotEmpty) return;
    _landState.title = generated;
    _setControllerText(_landTitleController, generated);
    _landState.errTitle = null;
  }

  void _applyCommercialAutoTitle() {
    final generated = _generateCommercialTitle().trim();
    if (generated.isEmpty) return;
    if (_commercialTitleManuallyEdited &&
        _commercialState.title.trim().isNotEmpty) {
      return;
    }
    _commercialState.title = generated;
    _setControllerText(_commercialTitleController, generated);
    _commercialState.errTitle = null;
  }

  //===========================================================================
  // Photo Management
  //===========================================================================

  SelectedPhoto _wrapPhoto(XFile file) {
    _photoSequence += 1;
    final id = '${DateTime.now().microsecondsSinceEpoch}_$_photoSequence';
    return SelectedPhoto(id: id, file: file);
  }

  Future<void> _showAddPhotoOptions() async {
    if (_totalPhotoCount >= kMaxPropertyPhotos) {
      ToastMessage.show(
          context, 'You can add up to $kMaxPropertyPhotos photos.');
      return;
    }

    if (!mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add photos',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'camera') {
      await _captureFromCamera();
    } else {
      await _pickFromGallery();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_totalPhotoCount >= kMaxPropertyPhotos) {
      ToastMessage.show(
          context, 'You can add up to $kMaxPropertyPhotos photos.');
      return;
    }

    try {
      final beforeCount = _totalPhotoCount;
      final picks = await _imagePicker.pickMultiImage(imageQuality: 85);
      if (picks.isEmpty) return;
      if (!mounted) return;
      setState(() {
        final remaining = _remainingPhotoSlots;
        if (remaining <= 0) {
          return;
        }
        _photos.addAll(picks.take(remaining).map(_wrapPhoto));
      });

      if (mounted && (beforeCount + picks.length) > kMaxPropertyPhotos) {
        ToastMessage.show(
            context, 'Only the first $kMaxPropertyPhotos photos were kept.');
      }
    } catch (e) {
      ToastMessage.show(context, 'Could not open gallery. Please try again.');
      if (kDebugMode) {
        debugPrint('Gallery pick failed: $e');
      }
    }
  }

  Future<void> _captureFromCamera() async {
    if (_totalPhotoCount >= kMaxPropertyPhotos) {
      ToastMessage.show(
          context, 'You can add up to $kMaxPropertyPhotos photos.');
      return;
    }

    try {
      final shot = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (shot == null) return;
      if (!mounted) return;
      setState(() {
        if (_totalPhotoCount >= kMaxPropertyPhotos) return;
        _photos.add(_wrapPhoto(shot));
      });
    } catch (e) {
      ToastMessage.show(
          context, 'Could not open camera. Please allow camera permission.');
      if (kDebugMode) {
        debugPrint('Camera capture failed: $e');
      }
    }
  }

  void _clearNewPhotos() {
    if (_photos.isEmpty) return;
    setState(() {
      _photos.clear();
    });
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _photos.length) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      if (newIndex < 0) newIndex = 0;
      if (newIndex >= _photos.length) newIndex = _photos.length - 1;
      final item = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, item);
    });
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= _photos.length) return;
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _reorderExistingPhotos(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _existingPhotos.length) return;
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      if (newIndex < 0) newIndex = 0;
      if (newIndex >= _existingPhotos.length) {
        newIndex = _existingPhotos.length - 1;
      }
      final item = _existingPhotos.removeAt(oldIndex);
      _existingPhotos.insert(newIndex, item);
    });
  }

  Future<void> _deleteExistingPhoto(int index) async {
    if (!_isEdit) return;
    if (index < 0 || index >= _existingPhotos.length) return;
    if (_isSaving || _isPrefilling) return;

    final img = _existingPhotos[index];
    final id = img.id?.trim() ?? '';
    if (id.isEmpty) {
      ToastMessage.show(context, 'This photo cannot be deleted.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete photo?'),
          content: const Text('This will permanently remove the photo.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      ToastMessage.show(context, 'Please login to delete photos.');
      return;
    }

    try {
      await _api.deleteImage(imageId: id, bearerToken: token);
      if (!mounted) return;
      setState(() {
        _existingPhotos.removeAt(index);
      });
      ToastMessage.show(context, 'Photo deleted.');
    } on MapApiException catch (ex) {
      if (!mounted) return;
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      ToastMessage.show(context, 'Failed to delete photo.');
    }
  }

  Future<void> _persistExistingPhotoOrder(String bearerToken) async {
    if (!_isEdit) return;
    if (_existingPhotos.isEmpty) return;

    for (var i = 0; i < _existingPhotos.length; i += 1) {
      final img = _existingPhotos[i];
      final id = img.id?.trim() ?? '';
      if (id.isEmpty) continue;

      try {
        await _api.updateImage(
          imageId: id,
          bearerToken: bearerToken,
          displayOrder: i + 1,
          isPrimary: i == 0,
        );
      } on MapApiException catch (ex) {
        debugPrint('Failed to update image $id order: ${ex.message}');
      } catch (_) {
        debugPrint('Failed to update image $id order');
      }
    }
  }

  //===========================================================================
  // Prefill Logic
  //===========================================================================

  Future<void> _prefillFromEditPayloadIfNeeded() async {
    if (!_isEdit) return;
    if (_didPrefillFromEditPayload) return;

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      return;
    }

    final propertyId = widget.propertyId!.trim();
    if (propertyId.isEmpty) return;

    if (mounted) {
      setState(() {
        _isPrefilling = true;
      });
    }

    try {
      final payload = await _api.getPropertyEditPayload(
        propertyId: propertyId,
        bearerToken: token,
      );
      if (!mounted) return;

      final rawType =
          (payload['type'] ?? payload['propertyType'] ?? '').toString().trim();

      final entityRaw = payload['entity'];
      final entity =
          entityRaw is Map ? entityRaw.cast<String, dynamic>() : payload;

      final resolvedType = _resolvePropertyTypeLabel(rawType, entity);
      final listing = _resolveListingType(
        _pickValueCaseInsensitive(entity, 'listingType'),
      );

      unawaited(
        _loadExistingPhotosIfNeeded(
          propertyTypeLabel: resolvedType,
          entity: entity,
          bearerToken: token,
        ),
      );

      setState(() {
        _propertyType = resolvedType;
        _listingType = listing;
        _prefillPropertyFields(entity);
        _prefillRevision += 1;
        _didPrefillFromEditPayload = true;
      });
    } on MapApiException catch (ex) {
      if (!mounted) return;
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      ToastMessage.show(context, 'Failed to load property details.');
    } finally {
      if (mounted) {
        setState(() {
          _isPrefilling = false;
        });
      }
    }
  }

  void _prefillPropertyFields(Map<String, dynamic> entity) {
    if (_propertyType == 'Plot') {
      _plotState.title = _pickString(entity, ['propertyTitle']);
      _plotState.area = _pickString(entity, ['areaLabel']);
      _plotState.price = formatIndianPrice(
        _stringFromNum(_pickDouble(entity, ['price'])),
      );
      _plotState.location = _pickString(entity, ['location']);
      _plotState.moreDetails = _pickString(
        entity,
        ['additionalInformation', 'additionalDetails'],
      );
      _plotState.contactName = _pickString(entity, ['contactName']);
      _plotState.contactNumber = _pickString(entity, ['contactNumber']);

      _setControllerText(_plotTitleController, _plotState.title);
      _setControllerText(_plotPriceController, _plotState.price);
      _setControllerText(_plotContactNameController, _plotState.contactName);
      _setControllerText(
          _plotContactNumberController, _plotState.contactNumber);
    } else if (_propertyType == 'Independent House') {
      _houseState.title = _pickString(entity, ['propertyTitle']);
      _houseState.bedrooms =
          _stringFromNum(_pickInt(entity, ['bedrooms']) ?? '');
      _houseState.builtUpArea = _stringFromNum(
        _pickDouble(entity, ['builtUpAreaInSquareFeet']) ?? '',
      );
      _houseState.floors = _stringFromNum(_pickInt(entity, ['floors']) ?? '');
      _houseState.buildingAgeYears =
          _stringFromNum(_pickInt(entity, ['buildingAge']) ?? '');
      _houseState.carParking = carParkingLabelFromCount(
        _pickInt(entity, ['carParkingCount']),
      );
      _houseState.price = formatIndianPrice(
        _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
      );
      _houseState.location = _pickString(entity, ['location']);
      _houseState.moreDetails = _pickString(entity, ['additionalDetails']);
      _houseState.contactName = _pickString(entity, ['contactName']);
      _houseState.contactNumber = _pickString(entity, ['contactNumber']);

      _setControllerText(_houseTitleController, _houseState.title);
      _setControllerText(_housePriceController, _houseState.price);
      _setControllerText(_houseContactNameController, _houseState.contactName);
      _setControllerText(
          _houseContactNumberController, _houseState.contactNumber);
    } else if (_propertyType == 'Apartment') {
      _apartmentState.title = _pickString(entity, ['propertyTitle']);
      _apartmentState.bedrooms =
          _stringFromNum(_pickInt(entity, ['bedrooms']) ?? '');
      _apartmentState.area = _stringFromNum(
        _pickDouble(entity, ['areaInSquareFeet']) ?? '',
      );
      _apartmentState.floor = _stringFromNum(_pickInt(entity, ['floor']) ?? '');
      _apartmentState.totalFloors =
          _stringFromNum(_pickInt(entity, ['totalFloors']) ?? '');
      _apartmentState.carParking = carParkingLabelFromCount(
        _pickInt(entity, ['carParkingCount']),
      );
      _apartmentState.buildingAgeYears =
          _stringFromNum(_pickInt(entity, ['buildingAge']) ?? '');
      _apartmentState.price = formatIndianPrice(
        _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
      );
      _apartmentState.location = _pickString(entity, ['location']);
      _apartmentState.moreInfo = _pickString(
        entity,
        ['additionalInformation', 'additionalDetails'],
      );
      _apartmentState.contactName = _pickString(entity, ['contactName']);
      _apartmentState.contactNumber = _pickString(entity, ['contactNumber']);

      _setControllerText(_apartmentTitleController, _apartmentState.title);
      _setControllerText(_apartmentPriceController, _apartmentState.price);
      _setControllerText(
          _apartmentContactNameController, _apartmentState.contactName);
      _setControllerText(
          _apartmentContactNumberController, _apartmentState.contactNumber);
    } else if (_propertyType == 'Land') {
      _landState.title = _pickString(entity, ['propertyTitle']);
      _landState.landType =
          landTypeLabelFromValue(_pickInt(entity, ['landType']));
      _landState.area = _pickString(entity, ['areaLabel']);
      _landState.price = formatIndianPrice(
        _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
      );
      _landState.location = _pickString(entity, ['location']);
      _landState.moreInfo = _pickString(
        entity,
        ['additionalInformation', 'additionalDetails'],
      );
      _landState.contactName = _pickString(entity, ['contactName']);
      _landState.contactNumber = _pickString(entity, ['contactNumber']);

      _setControllerText(_landTitleController, _landState.title);
      _setControllerText(_landPriceController, _landState.price);
      _setControllerText(_landContactNameController, _landState.contactName);
      _setControllerText(
          _landContactNumberController, _landState.contactNumber);
    } else {
      _commercialState.title = _pickString(entity, ['propertyTitle']);
      _commercialState.spaceType = _pickString(entity, ['spaceType']);
      _commercialState.builtUpArea = _stringFromNum(
        _pickDouble(entity, ['builtUpAreaInSquareFeet']) ?? '',
      );
      _commercialState.price = formatIndianPrice(
        _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
      );
      _commercialState.location = _pickString(entity, ['location']);
      _commercialState.additionalDetails = _pickString(
        entity,
        ['additionalDetails', 'additionalInformation'],
      );
      _commercialState.contactName = _pickString(entity, ['contactName']);
      _commercialState.contactNumber = _pickString(entity, ['contactNumber']);

      _setControllerText(_commercialTitleController, _commercialState.title);
      _setControllerText(_commercialPriceController, _commercialState.price);
      _setControllerText(
          _commercialContactNameController, _commercialState.contactName);
      _setControllerText(
          _commercialContactNumberController, _commercialState.contactNumber);
    }
  }

  Future<void> _loadExistingPhotosIfNeeded({
    required String propertyTypeLabel,
    required Map<String, dynamic> entity,
    required String bearerToken,
  }) async {
    if (!_isEdit) return;
    if (_didLoadExistingPhotos) return;

    final entityId = _pickEntityIdForMedia(entity);
    if (entityId.isEmpty) {
      _didLoadExistingPhotos = true;
      return;
    }

    final propertyTypeKey = mediaKeyForPropertyType(propertyTypeLabel);

    if (mounted) {
      setState(() {
        _isLoadingExistingPhotos = true;
      });
    }

    try {
      final images = await _api.getPropertyMedia(
        propertyType: propertyTypeKey,
        entityId: entityId,
        bearerToken: bearerToken,
      );

      if (!mounted) return;
      setState(() {
        _existingPhotos
          ..clear()
          ..addAll(images);
        _didLoadExistingPhotos = true;
      });
    } on MapApiException catch (ex) {
      if (!mounted) return;
      _didLoadExistingPhotos = true;
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      _didLoadExistingPhotos = true;
      ToastMessage.show(context, 'Failed to load existing photos.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingExistingPhotos = false;
        });
      }
    }
  }

  //===========================================================================
  // Utility Methods
  //===========================================================================

  Object? _pickValueCaseInsensitive(Map<String, dynamic> entity, String key) {
    if (entity.containsKey(key)) return entity[key];
    final target = key.toLowerCase();
    for (final entry in entity.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value;
      }
    }
    return null;
  }

  String _pickString(Map<String, dynamic> entity, List<String> keys) {
    for (final k in keys) {
      final v = _pickValueCaseInsensitive(entity, k);
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  int? _pickInt(Map<String, dynamic> entity, List<String> keys) {
    for (final k in keys) {
      final v = _pickValueCaseInsensitive(entity, k);
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double? _pickDouble(Map<String, dynamic> entity, List<String> keys) {
    for (final k in keys) {
      final v = _pickValueCaseInsensitive(entity, k);
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v.trim().replaceAll(',', ''));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _stringFromNum(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is int) return v.toString();
    if (v is double) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toString();
    }
    if (v is num) return v.toString();
    return v.toString();
  }

  String _pickEntityIdForMedia(Map<String, dynamic> entity) {
    final candidates = <String>[
      'id',
      'plotId',
      'houseId',
      'flatId',
      'apartmentId',
      'landId',
      'commercialSpaceId',
      'commercialId',
    ];
    for (final key in candidates) {
      final value = _pickValueCaseInsensitive(entity, key);
      final asString = value?.toString().trim() ?? '';
      if (asString.isNotEmpty) return asString;
    }
    return '';
  }

  String _resolveListingType(Object? raw) {
    final v = raw?.toString().trim() ?? '';
    if (v.isEmpty) return _listingType;
    final lower = v.toLowerCase();
    if (lower == 'buy' || lower == 'sell') return 'Sell';
    if (lower == 'rent') return 'Rent';
    if (lower == 'lease') return 'Lease';
    final titled = v.length <= 1
        ? v.toUpperCase()
        : '${v.substring(0, 1).toUpperCase()}${v.substring(1)}';
    return kListingTypes.contains(titled) ? titled : v;
  }

  String _resolvePropertyTypeLabel(
      String rawType, Map<String, dynamic> entity) {
    final trimmed = rawType.trim();
    if (trimmed.isNotEmpty && kPropertyTypes.contains(trimmed)) {
      return trimmed;
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('independent') || lower.contains('house')) {
      return 'Independent House';
    }
    if (lower.contains('apartment') || lower.contains('flat')) {
      return 'Apartment';
    }
    if (lower.contains('plot')) {
      return 'Plot';
    }
    if (lower.contains('land')) {
      return 'Land';
    }
    if (lower.contains('commercial')) {
      return 'Commercial Space';
    }

    if (entity.containsKey('plots') || entity.containsKey('Plots')) {
      return 'Plot';
    }
    if (entity.containsKey('landType') || entity.containsKey('LandType')) {
      return 'Land';
    }
    if (entity.containsKey('spaceType') || entity.containsKey('SpaceType')) {
      return 'Commercial Space';
    }
    if (entity.containsKey('floor') || entity.containsKey('Floor')) {
      return 'Apartment';
    }
    if (entity.containsKey('houseBoundaryGeoJson') ||
        entity.containsKey('HouseBoundaryGeoJson')) {
      return 'Independent House';
    }

    return _propertyType;
  }

  //===========================================================================
  // Save Logic
  //===========================================================================

  Future<void> _handleSave() async {
    if (_isSaving || _isPrefilling) return;

    _clearAllErrors();

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      AuthDialog.showLogin(context);
      return;
    }

    final boundaryGeoJson = GeoJson.polygonToGeoJson(widget.boundaryPoints);
    if (boundaryGeoJson == null || boundaryGeoJson.trim().isEmpty) {
      ToastMessage.show(
          context, 'Draw the property boundary polygon before saving.');
      return;
    }

    // Apply auto-title if needed
    _applyAutoTitleForCurrentType();

    // Validate and get payload
    final result = _validateCurrentPropertyType(boundaryGeoJson);

    if (!result.isValid) {
      if (result.errorMessage != null) {
        ToastMessage.show(context, result.errorMessage!);
      }
      setState(() {});
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final editPropertyId = widget.propertyId?.trim();
      final isEdit = editPropertyId != null && editPropertyId.isNotEmpty;

      String propertyIdForUploads;
      if (isEdit) {
        await _api.updatePropertyViaEditEndpoint(
          propertyId: editPropertyId,
          payload: result.payload!,
          bearerToken: token,
        );
        propertyIdForUploads = editPropertyId;
      } else {
        final created = await _api.createPropertyByType(
          propertyType: result.createType!,
          payload: result.payload!,
          bearerToken: token,
        );
        final createdId = (created['propertyId'] ??
                created['PropertyId'] ??
                created['id'] ??
                created['Id'])
            ?.toString();
        if (createdId == null || createdId.trim().isEmpty) {
          throw const MapApiException(
              'Created property response was missing an id.');
        }
        propertyIdForUploads = createdId;
      }

      PendingMapFocus.set(
        PendingMapFocusRequest(
          propertyId: propertyIdForUploads,
          boundaryPoints: widget.boundaryPoints,
        ),
      );

      if (isEdit) {
        await _persistExistingPhotoOrder(token);
      }

      final failedUploads = await _uploadNewPhotos(propertyIdForUploads, token);

      try {
        await _api.getPropertyDetail(
          propertyId: propertyIdForUploads,
          bearerToken: token,
        );
      } catch (_) {
        if (mounted) {
          ToastMessage.showAbove(
            context,
            'Property saved, but failed to refresh details.',
          );
        }
      }

      if (!mounted) return;

      String toastMessage;
      if (failedUploads.isNotEmpty) {
        for (final msg in failedUploads) {
          debugPrint('Photo upload failed: $msg');
        }
        toastMessage = failedUploads.length == 1
            ? 'Property saved, but 1 photo failed to upload. ${failedUploads.first}'
            : 'Property saved, but ${failedUploads.length} photo(s) failed to upload.';
      } else {
        toastMessage = 'Property saved';
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }

      if (!mounted) return;

      await _showSuccessDialog(toastMessage);
    } on MapApiException catch (ex) {
      if (!mounted) return;
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      ToastMessage.show(context, 'Failed to save property.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _clearAllErrors() {
    _plotState
      ..errArea = null
      ..errPrice = null
      ..errLocation = null
      ..errTitle = null
      ..errMoreDetails = null
      ..errContactName = null
      ..errContactNumber = null;

    _houseState
      ..errBedrooms = null
      ..errBuiltUpArea = null
      ..errFloors = null
      ..errCarParking = null
      ..errPrice = null
      ..errLocation = null
      ..errTitle = null
      ..errContactName = null
      ..errContactNumber = null;

    _apartmentState
      ..errBedrooms = null
      ..errArea = null
      ..errFloor = null
      ..errTotalFloors = null
      ..errCarParking = null
      ..errBuildingAgeYears = null
      ..errPrice = null
      ..errLocation = null;

    _landState
      ..errLandType = null
      ..errArea = null
      ..errPrice = null
      ..errLocation = null
      ..errTitle = null
      ..errContactName = null
      ..errContactNumber = null;

    _commercialState
      ..errSpaceType = null
      ..errBuiltUpArea = null
      ..errPrice = null
      ..errLocation = null
      ..errTitle = null
      ..errContactName = null
      ..errContactNumber = null;

    _errListingType = null;
  }

  void _applyAutoTitleForCurrentType() {
    switch (_propertyType) {
      case 'Plot':
        if (_plotState.title.trim().isEmpty) _applyPlotAutoTitle();
        break;
      case 'Independent House':
        if (_houseState.title.trim().isEmpty) _applyHouseAutoTitle();
        break;
      case 'Apartment':
        if (_apartmentState.title.trim().isEmpty) _applyApartmentAutoTitle();
        break;
      case 'Land':
        if (_landState.title.trim().isEmpty) _applyLandAutoTitle();
        break;
      default:
        if (_commercialState.title.trim().isEmpty) _applyCommercialAutoTitle();
        break;
    }
  }

  ValidationResult _validateCurrentPropertyType(String boundaryGeoJson) {
    switch (_propertyType) {
      case 'Plot':
        return validatePlotForm(
          state: _plotState,
          listingType: _listingType,
          boundaryGeoJson: boundaryGeoJson,
        );
      case 'Independent House':
        return validateHouseForm(
          state: _houseState,
          listingType: _listingType,
          boundaryGeoJson: boundaryGeoJson,
        );
      case 'Apartment':
        return validateApartmentForm(
          state: _apartmentState,
          listingType: _listingType,
          boundaryGeoJson: boundaryGeoJson,
        );
      case 'Land':
        return validateLandForm(
          state: _landState,
          listingType: _listingType,
          boundaryGeoJson: boundaryGeoJson,
        );
      default:
        return validateCommercialForm(
          state: _commercialState,
          listingType: _listingType,
          boundaryGeoJson: boundaryGeoJson,
        );
    }
  }

  Future<List<String>> _uploadNewPhotos(String propertyId, String token) async {
    final failedUploads = <String>[];
    if (_photos.isEmpty) return failedUploads;

    for (var i = 0; i < _photos.length; i += 1) {
      final picked = _photos[i].file;
      try {
        final existingCount = _existingPhotos.length;
        final shouldMakePrimary = existingCount == 0 && i == 0;
        // Convert HEIC/HEIF to JPEG before uploading
        final fileToUpload = await _ensureUploadableFormat(File(picked.path));
        await _api.uploadPropertyImage(
          propertyId: propertyId,
          file: fileToUpload,
          bearerToken: token,
          isPrimary: shouldMakePrimary,
          displayOrder: existingCount + i + 1,
          altText: picked.name,
        );
      } on MapApiException catch (ex) {
        failedUploads.add('${picked.name}: ${ex.message}');
      } catch (_) {
        failedUploads.add('${picked.name}: upload failed');
      }
    }
    return failedUploads;
  }

  /// Converts HEIC/HEIF images to JPEG so the API can accept them.
  /// Uses Flutter's built-in image codec which supports HEIC on iOS/Android.
  /// Returns the original file if it's already an allowed format.
  Future<File> _ensureUploadableFormat(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (ext != 'heic' && ext != 'heif') return file;

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      codec.dispose();

      if (byteData == null) return file;

      // Write as .png in the same directory (API accepts PNG)
      final pngPath =
          '${file.path.substring(0, file.path.lastIndexOf('.'))}.png';
      final pngFile = File(pngPath);
      await pngFile.writeAsBytes(byteData.buffer.asUint8List());
      return pngFile;
    } catch (e) {
      debugPrint('HEIC conversion failed: $e');
      return file; // Fall back to original if conversion fails
    }
  }

  Future<void> _showSuccessDialog(String toastMessage) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        final maxWidth = size.width - 64;
        final dialogWidth = maxWidth < 332 ? maxWidth : 332.0;
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dialogWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: const [
                        Text(
                          'Successfully saved',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          toastMessage,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap OK to return to the map.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0FAD97),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(dialogContext, rootNavigator: true)
                                .pop();
                            Navigator.of(context, rootNavigator: true)
                                .popUntil((route) => route.isFirst);
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  //===========================================================================
  // Build Methods
  //===========================================================================

  List<Widget> _buildPropertyFields() {
    switch (_propertyType) {
      case 'Plot':
        return buildPlotFormFields(
          state: _plotState,
          titleController: _plotTitleController,
          priceController: _plotPriceController,
          contactNameController: _plotContactNameController,
          contactNumberController: _plotContactNumberController,
          onAreaChanged: () => setState(() {}),
          onPriceChanged: () => setState(() {}),
          onLocationChanged: () => setState(() => _applyPlotAutoTitle()),
          onTitleChanged: () => setState(() {
            _plotTitleManuallyEdited = _plotState.title.trim().isNotEmpty;
          }),
          onMoreDetailsChanged: () => setState(() {}),
          onContactNameChanged: () => setState(() {}),
          onContactNumberChanged: () => setState(() {}),
          prefillRevision: _prefillRevision,
        );
      case 'Independent House':
        return buildHouseFormFields(
          state: _houseState,
          titleController: _houseTitleController,
          priceController: _housePriceController,
          contactNameController: _houseContactNameController,
          contactNumberController: _houseContactNumberController,
          onBedroomsChanged: () => setState(() => _applyHouseAutoTitle()),
          onBuiltUpAreaChanged: () => setState(() {}),
          onFloorsChanged: () => setState(() {}),
          onCarParkingChanged: () => setState(() {}),
          onBuildingAgeChanged: () => setState(() {}),
          onPriceChanged: () => setState(() {}),
          onLocationChanged: () => setState(() => _applyHouseAutoTitle()),
          onTitleChanged: () => setState(() {
            _houseTitleManuallyEdited = _houseState.title.trim().isNotEmpty;
          }),
          onMoreDetailsChanged: () => setState(() {}),
          onContactNameChanged: () => setState(() {}),
          onContactNumberChanged: () => setState(() {}),
          prefillRevision: _prefillRevision,
        );
      case 'Apartment':
        return buildApartmentFormFields(
          state: _apartmentState,
          titleController: _apartmentTitleController,
          priceController: _apartmentPriceController,
          contactNameController: _apartmentContactNameController,
          contactNumberController: _apartmentContactNumberController,
          onBedroomsChanged: () => setState(() => _applyApartmentAutoTitle()),
          onAreaChanged: () => setState(() {}),
          onFloorChanged: () => setState(() {}),
          onTotalFloorsChanged: () => setState(() {}),
          onCarParkingChanged: () => setState(() {}),
          onBuildingAgeChanged: () => setState(() {}),
          onPriceChanged: () => setState(() {}),
          onLocationChanged: () => setState(() => _applyApartmentAutoTitle()),
          onTitleChanged: () => setState(() {
            _apartmentTitleManuallyEdited =
                _apartmentState.title.trim().isNotEmpty;
          }),
          onMoreInfoChanged: () => setState(() {}),
          onContactNameChanged: () => setState(() {}),
          onContactNumberChanged: () => setState(() {}),
          prefillRevision: _prefillRevision,
        );
      case 'Land':
        return buildLandFormFields(
          state: _landState,
          titleController: _landTitleController,
          priceController: _landPriceController,
          contactNameController: _landContactNameController,
          contactNumberController: _landContactNumberController,
          onLandTypeChanged: () => setState(() => _applyLandAutoTitle()),
          onAreaChanged: () => setState(() {}),
          onPriceChanged: () => setState(() {}),
          onLocationChanged: () => setState(() => _applyLandAutoTitle()),
          onTitleChanged: () => setState(() {
            _landTitleManuallyEdited = _landState.title.trim().isNotEmpty;
          }),
          onMoreInfoChanged: () => setState(() {}),
          onContactNameChanged: () => setState(() {}),
          onContactNumberChanged: () => setState(() {}),
          prefillRevision: _prefillRevision,
        );
      default:
        return buildCommercialFormFields(
          state: _commercialState,
          listingType: _listingType,
          titleController: _commercialTitleController,
          priceController: _commercialPriceController,
          contactNameController: _commercialContactNameController,
          contactNumberController: _commercialContactNumberController,
          onSpaceTypeChanged: () => setState(() => _applyCommercialAutoTitle()),
          onBuiltUpAreaChanged: () => setState(() {}),
          onPriceChanged: () => setState(() {}),
          onLocationChanged: () => setState(() => _applyCommercialAutoTitle()),
          onTitleChanged: () => setState(() {
            _commercialTitleManuallyEdited =
                _commercialState.title.trim().isNotEmpty;
          }),
          onAdditionalDetailsChanged: () => setState(() {}),
          onContactNameChanged: () => setState(() {}),
          onContactNumberChanged: () => setState(() {}),
          prefillRevision: _prefillRevision,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showListingType = _propertyType != 'Layouts';
    return WillPopScope(
      onWillPop: () async => !_isSaving && !_isPrefilling,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'Property Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: (_isSaving || _isPrefilling) ? null : _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0FAD97),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _isSaving
                      ? 'Saving...'
                      : _isPrefilling
                          ? 'Loading...'
                          : 'Save',
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (showListingType) ...[
                    PropertyDropdown(
                      label: 'Listing Type',
                      value: _listingType,
                      options: kListingTypes,
                      onChanged: (v) => setState(() {
                        _listingType = v ?? 'Sell';
                        _errListingType = null;
                      }),
                      errorText: _propertyType == 'Commercial Space'
                          ? _errListingType
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  PropertyDropdown(
                    label: 'Property Type',
                    value: _propertyType,
                    options: kPropertyTypes,
                    onChanged: (v) =>
                        setState(() => _propertyType = v ?? 'Plot'),
                  ),
                  const SizedBox(height: 10),
                  ..._buildPropertyFields(),
                  const SizedBox(height: 16),
                  PropertyPhotoSection(
                    existingPhotos: _existingPhotos,
                    newPhotos: _photos,
                    isLoadingExistingPhotos: _isLoadingExistingPhotos,
                    onAddPhotoPressed: _showAddPhotoOptions,
                    onDeleteExistingPhoto: _deleteExistingPhoto,
                    onRemoveNewPhoto: _removeImage,
                    onReorderExistingPhotos: _reorderExistingPhotos,
                    onReorderNewPhotos: _reorderPhotos,
                    onClearNewPhotos: _clearNewPhotos,
                    absoluteMediaUrl: _absoluteMediaUrl,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_isSaving || _isPrefilling) ? null : _handleSave,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _isSaving
                                ? 'Saving...'
                                : _isPrefilling
                                    ? 'Loading...'
                                    : 'Save',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: const Color(0xFF0FAD97),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (_isSaving || _isPrefilling)
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            foregroundColor: const Color(0xFF475569),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_isSaving) _buildOverlay('Saving…'),
              if (_isPrefilling) _buildOverlay('Loading…'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(String message) {
    return Stack(
      children: [
        const ModalBarrier(
          dismissible: false,
          color: Color(0x1A000000),
        ),
        Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
