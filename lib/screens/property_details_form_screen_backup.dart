import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/api_constants.dart';
import '../models/image_summary.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../utils/pending_map_focus.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/toast_message.dart';

class PropertyDetailsFormScreen extends StatefulWidget {
  const PropertyDetailsFormScreen({
    super.key,
    required this.boundaryPoints,
    this.initialPropertyType,
    this.propertyId,
  });

  final List<LatLng> boundaryPoints;
  final String? initialPropertyType;
  final String? propertyId;

  @override
  State<PropertyDetailsFormScreen> createState() =>
      _PropertyDetailsFormScreenState();
}

class _SelectedPhoto {
  const _SelectedPhoto({required this.id, required this.file});

  final String id;
  final XFile file;
}

class _PropertyDetailsFormScreenState extends State<PropertyDetailsFormScreen> {
  static const int _maxPhotos = 12;

  int _photoSequence = 0;

  static const List<String> _propertyTypes = <String>[
    'Plot',
    'Independent House',
    'Apartment',
    'Land',
    'Commercial Space',
  ];

  static const List<String> _listingTypes = <String>[
    'Sell',
    'Rent',
    'Lease',
  ];

  static const List<String> _commercialTypeOptions = <String>[
    'Office Space',
    'Showroom',
    'Shop',
    'Godown',
    'Industrial',
    'Co-working',
    'Restaurant',
  ];

  static const Map<String, int> _propertyTypeValueMap = {
    'Plot': 1,
    'Apartment': 2,
    'Independent House': 3,
    'Commercial Space': 4,
    'Land': 5,
  };

  static const Map<String, int> _landTypeValueMap = {
    'Residential': 1,
    'Commercial': 2,
    'Agricultural': 3,
  };

  final _api = MobileBffMapApi();
  final _imagePicker = ImagePicker();

  bool _isSaving = false;
  bool _isPrefilling = false;
  bool _didPrefillFromEditPayload = false;
  int _prefillRevision = 0;

  bool get _isEdit {
    final id = widget.propertyId;
    return id != null && id.trim().isNotEmpty;
  }

  late String _propertyType;
  String _listingType = 'Sell';

  // Plot fields
  String _plotTitle = '';
  String _plotArea = '';
  String _plotPrice = '';
  String _plotLocation = '';
  String _plotMoreDetails = '';
  String _plotContactName = '';
  String _plotContactNumber = '';

  // Independent house fields
  String _houseTitle = '';
  String _houseBedrooms = '';
  String _houseBuiltUpArea = '';
  String _houseFloors = '';
  String _houseCarParking = 'None';
  String _houseBuildingAgeYears = '';
  String _housePrice = '';
  String _houseLocation = '';
  String _houseMoreDetails = '';
  String _houseContactName = '';
  String _houseContactNumber = '';

  // Apartment fields
  String _apartmentTitle = '';
  String _apartmentBedrooms = '';
  String _apartmentArea = '';
  String _apartmentFloor = '';
  String _apartmentTotalFloors = '';
  String _apartmentCarParking = 'None';
  String _apartmentBuildingAgeYears = '';
  String _apartmentPrice = '';
  String _apartmentLocation = '';
  String _apartmentMoreInfo = '';
  String _apartmentContactName = '';
  String _apartmentContactNumber = '';

  // Land fields
  String _landTitle = '';
  String _landType = '';
  String _landArea = '';
  String _landPrice = '';
  String _landLocation = '';
  String _landMoreInfo = '';
  String _landContactName = '';
  String _landContactNumber = '';

  // Commercial fields
  String _commercialTitle = '';
  String _commercialSpaceType = '';
  String _commercialBuiltUpArea = '';
  String _commercialPrice = '';
  String _commercialLocation = '';
  String _commercialAdditionalDetails = '';
  String _commercialContactName = '';
  String _commercialContactNumber = '';

  String? _errPlotArea;
  String? _errPlotPrice;
  String? _errPlotLocation;
  String? _errPlotTitle;
  String? _errPlotMoreDetails;
  String? _errPlotContactName;
  String? _errPlotContactNumber;

  String? _errHouseBedrooms;
  String? _errHouseBuiltUpArea;
  String? _errHouseFloors;
  String? _errHouseCarParking;
  String? _errHousePrice;
  String? _errHouseLocation;
  String? _errHouseTitle;
  String? _errHouseContactName;
  String? _errHouseContactNumber;

  String? _errApartmentBedrooms;
  String? _errApartmentArea;
  String? _errApartmentFloor;
  String? _errApartmentTotalFloors;
  String? _errApartmentCarParking;
  String? _errApartmentBuildingAgeYears;
  String? _errApartmentPrice;
  String? _errApartmentLocation;

  String? _errLandType;
  String? _errLandArea;
  String? _errLandPrice;
  String? _errLandLocation;
  String? _errLandTitle;
  String? _errLandContactName;
  String? _errLandContactNumber;

  String? _errCommercialSpaceType;
  String? _errCommercialBuiltUpArea;
  String? _errCommercialPrice;
  String? _errCommercialLocation;
  String? _errCommercialTitle;
  String? _errCommercialContactName;
  String? _errCommercialContactNumber;
  String? _errListingType;

  final List<ImageSummary> _existingPhotos = <ImageSummary>[];
  bool _isLoadingExistingPhotos = false;
  bool _didLoadExistingPhotos = false;

  final List<_SelectedPhoto> _photos = <_SelectedPhoto>[];

  int get _totalPhotoCount => _existingPhotos.length + _photos.length;

  int get _remainingPhotoSlots {
    final remaining = _maxPhotos - _totalPhotoCount;
    return remaining < 0 ? 0 : remaining;
  }

  String _mediaKeyForPropertyTypeLabel(String propertyTypeLabel) {
    switch (propertyTypeLabel.trim()) {
      case 'Plot':
        return 'individualplots';
      case 'Independent House':
        return 'independenthouse';
      case 'Apartment':
        return 'apartmentflat';
      case 'Commercial Space':
        return 'commercialspace';
      case 'Land':
      default:
        return 'land';
    }
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

  Future<void> _deleteExistingPhoto(int index) async {
    if (!_isEdit) return;
    if (index < 0 || index >= _existingPhotos.length) return;
    if (_isSaving || _isPrefilling) return;

    final img = _existingPhotos[index];
    final id = img.id?.trim() ?? '';
    if (id.isEmpty) {
      _showError('This photo cannot be deleted.');
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
      _showError('Please login to delete photos.');
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

    final propertyTypeKey = _mediaKeyForPropertyTypeLabel(propertyTypeLabel);

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

  _SelectedPhoto _wrapPhoto(XFile file) {
    _photoSequence += 1;
    final id = '${DateTime.now().microsecondsSinceEpoch}_$_photoSequence';
    return _SelectedPhoto(id: id, file: file);
  }

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

  bool _didPrefillContactFromUser = false;

  bool _plotTitleManuallyEdited = false;
  bool _houseTitleManuallyEdited = false;
  bool _apartmentTitleManuallyEdited = false;
  bool _landTitleManuallyEdited = false;
  bool _commercialTitleManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPropertyType?.trim();
    _propertyType = _propertyTypes.contains(initial) ? initial! : 'Plot';
    _landType = '';

    _plotTitleController = TextEditingController(text: _plotTitle);
    _houseTitleController = TextEditingController(text: _houseTitle);
    _apartmentTitleController = TextEditingController(text: _apartmentTitle);
    _landTitleController = TextEditingController(text: _landTitle);
    _commercialTitleController = TextEditingController(text: _commercialTitle);

    _plotPriceController = TextEditingController(text: _plotPrice);
    _housePriceController = TextEditingController(text: _housePrice);
    _apartmentPriceController = TextEditingController(text: _apartmentPrice);
    _landPriceController = TextEditingController(text: _landPrice);
    _commercialPriceController = TextEditingController(text: _commercialPrice);

    _plotContactNameController = TextEditingController(text: _plotContactName);
    _plotContactNumberController =
        TextEditingController(text: _plotContactNumber);
    _houseContactNameController =
        TextEditingController(text: _houseContactName);
    _houseContactNumberController =
        TextEditingController(text: _houseContactNumber);
    _apartmentContactNameController =
        TextEditingController(text: _apartmentContactName);
    _apartmentContactNumberController =
        TextEditingController(text: _apartmentContactNumber);
    _landContactNameController = TextEditingController(text: _landContactName);
    _landContactNumberController =
        TextEditingController(text: _landContactNumber);
    _commercialContactNameController =
        TextEditingController(text: _commercialContactName);
    _commercialContactNumberController =
        TextEditingController(text: _commercialContactNumber);

    unawaited(_prefillFromEditPayloadIfNeeded());
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
    return _listingTypes.contains(titled) ? titled : v;
  }

  String _resolvePropertyTypeLabel(
      String rawType, Map<String, dynamic> entity) {
    final trimmed = rawType.trim();
    if (trimmed.isNotEmpty && _propertyTypes.contains(trimmed)) {
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

  String _formatIndianPrice(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    // Keep only digits and at most one decimal point.
    final cleaned = trimmed.replaceAll(',', '');
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(cleaned);
    if (match == null) {
      final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.isEmpty) return trimmed;
      return _formatIndianDigits(digitsOnly);
    }

    final whole = match.group(1) ?? '';
    final fraction = match.group(2);
    final formattedWhole = _formatIndianDigits(whole);
    if (fraction == null || fraction.isEmpty) {
      return formattedWhole;
    }
    return '$formattedWhole.$fraction';
  }

  String _formatIndianDigits(String digits) {
    var d = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (d.isEmpty) return '';
    if (d.length <= 3) return d;

    final last3 = d.substring(d.length - 3);
    var rest = d.substring(0, d.length - 3);

    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      parts.insert(0, rest);
    }

    return '${parts.join(',')},$last3';
  }

  String _carParkingLabelFromCount(int? count) {
    final v = count ?? 0;
    if (v <= 0) return 'None';
    if (v >= 4) return '4+';
    return v.toString();
  }

  String _landTypeLabelFromValue(int? value) {
    if (value == null) return '';
    for (final entry in _landTypeValueMap.entries) {
      if (entry.value == value) return entry.key;
    }
    return '';
  }

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

        if (_propertyType == 'Plot') {
          _plotTitle = _pickString(entity, ['propertyTitle']);
          _plotArea = _pickString(entity, ['areaLabel']);
          _plotPrice = _formatIndianPrice(
            _stringFromNum(_pickDouble(entity, ['price'])),
          );
          _plotLocation = _pickString(entity, ['location']);
          _plotMoreDetails = _pickString(
            entity,
            ['additionalInformation', 'additionalDetails'],
          );
          _plotContactName = _pickString(entity, ['contactName']);
          _plotContactNumber = _pickString(entity, ['contactNumber']);

          _setControllerText(_plotTitleController, _plotTitle);
          _setControllerText(_plotPriceController, _plotPrice);
          _setControllerText(_plotContactNameController, _plotContactName);
          _setControllerText(_plotContactNumberController, _plotContactNumber);
        } else if (_propertyType == 'Independent House') {
          _houseTitle = _pickString(entity, ['propertyTitle']);
          _houseBedrooms = _stringFromNum(_pickInt(entity, ['bedrooms']) ?? '');
          _houseBuiltUpArea = _stringFromNum(
            _pickDouble(entity, ['builtUpAreaInSquareFeet']) ?? '',
          );
          _houseFloors = _stringFromNum(_pickInt(entity, ['floors']) ?? '');
          _houseBuildingAgeYears =
              _stringFromNum(_pickInt(entity, ['buildingAge']) ?? '');
          _houseCarParking = _carParkingLabelFromCount(
            _pickInt(entity, ['carParkingCount']),
          );
          _housePrice = _formatIndianPrice(
            _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
          );
          _houseLocation = _pickString(entity, ['location']);
          _houseMoreDetails = _pickString(entity, ['additionalDetails']);
          _houseContactName = _pickString(entity, ['contactName']);
          _houseContactNumber = _pickString(entity, ['contactNumber']);

          _setControllerText(_houseTitleController, _houseTitle);
          _setControllerText(_housePriceController, _housePrice);
          _setControllerText(_houseContactNameController, _houseContactName);
          _setControllerText(
              _houseContactNumberController, _houseContactNumber);
        } else if (_propertyType == 'Apartment') {
          _apartmentTitle = _pickString(entity, ['propertyTitle']);
          _apartmentBedrooms =
              _stringFromNum(_pickInt(entity, ['bedrooms']) ?? '');
          _apartmentArea = _stringFromNum(
            _pickDouble(entity, ['areaInSquareFeet']) ?? '',
          );
          _apartmentFloor = _stringFromNum(_pickInt(entity, ['floor']) ?? '');
          _apartmentTotalFloors =
              _stringFromNum(_pickInt(entity, ['totalFloors']) ?? '');
          _apartmentCarParking = _carParkingLabelFromCount(
            _pickInt(entity, ['carParkingCount']),
          );
          _apartmentBuildingAgeYears =
              _stringFromNum(_pickInt(entity, ['buildingAge']) ?? '');
          _apartmentPrice = _formatIndianPrice(
            _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
          );
          _apartmentLocation = _pickString(entity, ['location']);
          _apartmentMoreInfo = _pickString(
            entity,
            ['additionalInformation', 'additionalDetails'],
          );
          _apartmentContactName = _pickString(entity, ['contactName']);
          _apartmentContactNumber = _pickString(entity, ['contactNumber']);

          _setControllerText(_apartmentTitleController, _apartmentTitle);
          _setControllerText(_apartmentPriceController, _apartmentPrice);
          _setControllerText(
              _apartmentContactNameController, _apartmentContactName);
          _setControllerText(
              _apartmentContactNumberController, _apartmentContactNumber);
        } else if (_propertyType == 'Land') {
          _landTitle = _pickString(entity, ['propertyTitle']);
          _landType = _landTypeLabelFromValue(_pickInt(entity, ['landType']));
          _landArea = _pickString(entity, ['areaLabel']);
          _landPrice = _formatIndianPrice(
            _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
          );
          _landLocation = _pickString(entity, ['location']);
          _landMoreInfo = _pickString(
            entity,
            ['additionalInformation', 'additionalDetails'],
          );
          _landContactName = _pickString(entity, ['contactName']);
          _landContactNumber = _pickString(entity, ['contactNumber']);

          _setControllerText(_landTitleController, _landTitle);
          _setControllerText(_landPriceController, _landPrice);
          _setControllerText(_landContactNameController, _landContactName);
          _setControllerText(_landContactNumberController, _landContactNumber);
        } else {
          _commercialTitle = _pickString(entity, ['propertyTitle']);
          _commercialSpaceType = _pickString(entity, ['spaceType']);
          _commercialBuiltUpArea = _stringFromNum(
            _pickDouble(entity, ['builtUpAreaInSquareFeet']) ?? '',
          );
          _commercialPrice = _formatIndianPrice(
            _stringFromNum(_pickDouble(entity, ['price']) ?? ''),
          );
          _commercialLocation = _pickString(entity, ['location']);
          _commercialAdditionalDetails = _pickString(
            entity,
            ['additionalDetails', 'additionalInformation'],
          );
          _commercialContactName = _pickString(entity, ['contactName']);
          _commercialContactNumber = _pickString(entity, ['contactNumber']);

          _setControllerText(_commercialTitleController, _commercialTitle);
          _setControllerText(_commercialPriceController, _commercialPrice);
          _setControllerText(
              _commercialContactNameController, _commercialContactName);
          _setControllerText(
              _commercialContactNumberController, _commercialContactNumber);
        }

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
      if (_plotContactNameController.text.trim().isEmpty) {
        _plotContactName = name;
        _setControllerText(_plotContactNameController, name);
        changed = true;
      }
      if (_houseContactNameController.text.trim().isEmpty) {
        _houseContactName = name;
        _setControllerText(_houseContactNameController, name);
        changed = true;
      }
      if (_apartmentContactNameController.text.trim().isEmpty) {
        _apartmentContactName = name;
        _setControllerText(_apartmentContactNameController, name);
        changed = true;
      }
      if (_landContactNameController.text.trim().isEmpty) {
        _landContactName = name;
        _setControllerText(_landContactNameController, name);
        changed = true;
      }
      if (_commercialContactNameController.text.trim().isEmpty) {
        _commercialContactName = name;
        _setControllerText(_commercialContactNameController, name);
        changed = true;
      }
    }

    if (phone.isNotEmpty) {
      if (_plotContactNumberController.text.trim().isEmpty) {
        _plotContactNumber = phone;
        _setControllerText(_plotContactNumberController, phone);
        changed = true;
      }
      if (_houseContactNumberController.text.trim().isEmpty) {
        _houseContactNumber = phone;
        _setControllerText(_houseContactNumberController, phone);
        changed = true;
      }
      if (_apartmentContactNumberController.text.trim().isEmpty) {
        _apartmentContactNumber = phone;
        _setControllerText(_apartmentContactNumberController, phone);
        changed = true;
      }
      if (_landContactNumberController.text.trim().isEmpty) {
        _landContactNumber = phone;
        _setControllerText(_landContactNumberController, phone);
        changed = true;
      }
      if (_commercialContactNumberController.text.trim().isEmpty) {
        _commercialContactNumber = phone;
        _setControllerText(_commercialContactNumberController, phone);
        changed = true;
      }
    }

    _didPrefillContactFromUser = true;
    if (changed) {
      setState(() {});
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

  String _generatePlotTitle() {
    final loc = _plotLocation.trim();
    if (loc.isEmpty) return 'Plot';
    return 'Plot in $loc';
  }

  String _generateHouseTitle() {
    final loc = _houseLocation.trim();
    final bedrooms = _parseInt(_houseBedrooms);
    final bhk = (bedrooms != null && bedrooms > 0) ? '$bedrooms BHK ' : '';
    final base = '${bhk}Independent House'.trim();
    if (loc.isEmpty) return base.isEmpty ? 'Independent House' : base;
    return '$base in $loc';
  }

  String _generateApartmentTitle() {
    final loc = _apartmentLocation.trim();
    final bedrooms = _parseInt(_apartmentBedrooms);
    final bhk = (bedrooms != null && bedrooms > 0) ? '$bedrooms BHK ' : '';
    final base = '${bhk}Apartment'.trim();
    if (loc.isEmpty) return base.isEmpty ? 'Apartment' : base;
    return '$base in $loc';
  }

  String _generateLandTitle() {
    final loc = _landLocation.trim();
    if (loc.isEmpty) return 'Land';
    return 'Land in $loc';
  }

  String _generateCommercialTitle() {
    final loc = _commercialLocation.trim();
    final space = _commercialSpaceType.trim();
    final base = space.isEmpty ? 'Commercial Space' : space;
    if (loc.isEmpty) return base;
    return '$base in $loc';
  }

  void _applyPlotAutoTitleIfAllowed() {
    final generated = _generatePlotTitle().trim();
    if (generated.isEmpty) return;
    if (_plotTitleManuallyEdited && _plotTitle.trim().isNotEmpty) return;
    _plotTitle = generated;
    _setControllerText(_plotTitleController, generated);
    _errPlotTitle = null;
  }

  void _applyHouseAutoTitleIfAllowed() {
    final generated = _generateHouseTitle().trim();
    if (generated.isEmpty) return;
    if (_houseTitleManuallyEdited && _houseTitle.trim().isNotEmpty) return;
    _houseTitle = generated;
    _setControllerText(_houseTitleController, generated);
    _errHouseTitle = null;
  }

  void _applyApartmentAutoTitleIfAllowed() {
    final generated = _generateApartmentTitle().trim();
    if (generated.isEmpty) return;
    if (_apartmentTitleManuallyEdited && _apartmentTitle.trim().isNotEmpty) {
      return;
    }
    _apartmentTitle = generated;
    _setControllerText(_apartmentTitleController, generated);
  }

  void _applyLandAutoTitleIfAllowed() {
    final generated = _generateLandTitle().trim();
    if (generated.isEmpty) return;
    if (_landTitleManuallyEdited && _landTitle.trim().isNotEmpty) return;
    _landTitle = generated;
    _setControllerText(_landTitleController, generated);
    _errLandTitle = null;
  }

  void _applyCommercialAutoTitleIfAllowed() {
    final generated = _generateCommercialTitle().trim();
    if (generated.isEmpty) return;
    if (_commercialTitleManuallyEdited && _commercialTitle.trim().isNotEmpty) {
      return;
    }
    _commercialTitle = generated;
    _setControllerText(_commercialTitleController, generated);
    _errCommercialTitle = null;
  }

  double? _parseDouble(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned.replaceAll(',', ''));
  }

  String _listingTypeForPayload() {
    final v = _listingType.trim();
    if (v.isEmpty) return 'Sell';
    if (v == 'Buy') return 'Sell';
    return v;
  }

  int? _parseInt(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  String _normalizeContact(String raw) {
    final trimmed = raw.trim();
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return '';
    return trimmed.startsWith('+') ? '+$digitsOnly' : digitsOnly;
  }

  void _showError(String message) {
    ToastMessage.show(context, message);
  }

  int _parseCarParkingCount(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 0;
    if (v.toLowerCase() == 'none') return 0;
    if (v.toLowerCase() == 'available') return 1;
    final cleaned = v.replaceAll('+', '').trim();
    return int.tryParse(cleaned) ?? 0;
  }

  Future<void> _pickFromGallery() async {
    if (_totalPhotoCount >= _maxPhotos) {
      _showError('You can add up to $_maxPhotos photos.');
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

      if (mounted && (beforeCount + picks.length) > _maxPhotos) {
        ToastMessage.show(
            context, 'Only the first $_maxPhotos photos were kept.');
      }
    } catch (e) {
      _showError('Could not open gallery. Please try again.');
      if (kDebugMode) {
        debugPrint('Gallery pick failed: $e');
      }
    }
  }

  Future<void> _captureFromCamera() async {
    if (_totalPhotoCount >= _maxPhotos) {
      _showError('You can add up to $_maxPhotos photos.');
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
        if (_totalPhotoCount >= _maxPhotos) return;
        _photos.add(_wrapPhoto(shot));
      });
    } catch (e) {
      _showError('Could not open camera. Please allow camera permission.');
      if (kDebugMode) {
        debugPrint('Camera capture failed: $e');
      }
    }
  }

  Future<void> _showAddPhotoOptions() async {
    if (_totalPhotoCount >= _maxPhotos) {
      _showError('You can add up to $_maxPhotos photos.');
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

  Future<void> _handleSave() async {
    if (_isSaving || _isPrefilling) return;

    if (_propertyType == 'Commercial Space') {
      setState(() {
        _errCommercialSpaceType = null;
        _errCommercialBuiltUpArea = null;
        _errCommercialPrice = null;
        _errCommercialLocation = null;
        _errCommercialTitle = null;
        _errCommercialContactName = null;
        _errCommercialContactNumber = null;
        _errListingType = null;
      });
    }

    if (_propertyType == 'Independent House') {
      setState(() {
        _errHouseBedrooms = null;
        _errHouseBuiltUpArea = null;
        _errHouseFloors = null;
        _errHouseCarParking = null;
        _errHousePrice = null;
        _errHouseLocation = null;
        _errHouseTitle = null;
        _errHouseContactName = null;
        _errHouseContactNumber = null;
      });
    }

    if (_propertyType == 'Plot') {
      setState(() {
        _errPlotArea = null;
        _errPlotPrice = null;
        _errPlotLocation = null;
        _errPlotTitle = null;
        _errPlotMoreDetails = null;
        _errPlotContactName = null;
        _errPlotContactNumber = null;
      });
    }

    if (_propertyType == 'Apartment') {
      setState(() {
        _errApartmentBedrooms = null;
        _errApartmentArea = null;
        _errApartmentFloor = null;
        _errApartmentTotalFloors = null;
        _errApartmentCarParking = null;
        _errApartmentBuildingAgeYears = null;
        _errApartmentPrice = null;
        _errApartmentLocation = null;
      });
    }

    if (_propertyType == 'Land') {
      setState(() {
        _errLandType = null;
        _errLandArea = null;
        _errLandPrice = null;
        _errLandLocation = null;
        _errLandTitle = null;
        _errLandContactName = null;
        _errLandContactNumber = null;
      });
    }

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      AuthDialog.showLogin(context);
      return;
    }

    final boundaryGeoJson = GeoJson.polygonToGeoJson(widget.boundaryPoints);
    if (boundaryGeoJson == null || boundaryGeoJson.trim().isEmpty) {
      _showError('Draw the property boundary polygon before saving.');
      return;
    }

    Map<String, dynamic> payload;
    String createType;

    if (_propertyType == 'Plot') {
      if (_plotTitle.trim().isEmpty) {
        setState(() {
          _applyPlotAutoTitleIfAllowed();
        });
      }

      final title = _plotTitle.trim();
      final areaRaw = _plotArea.trim();
      final area = _parseDouble(areaRaw);
      final location = _plotLocation.trim();
      final description = _plotMoreDetails.trim();
      final priceRaw = _plotPrice.trim();
      final price = _parseDouble(priceRaw);
      final contactName = _plotContactName.trim();
      final normalizedContact = _normalizeContact(_plotContactNumber);

      var hasError = false;
      if (areaRaw.isEmpty) {
        hasError = true;
        _errPlotArea = 'Plot area is required.';
      } else if (area == null || area <= 0) {
        hasError = true;
        _errPlotArea = 'Plot area must be greater than zero.';
      }
      if (priceRaw.isEmpty) {
        hasError = true;
        _errPlotPrice = 'Price is required.';
      } else if (price == null || price <= 0) {
        hasError = true;
        _errPlotPrice = 'Price must be greater than zero.';
      }
      if (location.isEmpty) {
        hasError = true;
        _errPlotLocation = 'Locality is required.';
      }
      if (title.isEmpty) {
        hasError = true;
        _errPlotTitle = 'Property title is required.';
      }
      if (contactName.isEmpty) {
        hasError = true;
        _errPlotContactName = 'Contact name is required.';
      }
      if (_plotContactNumber.trim().isEmpty) {
        hasError = true;
        _errPlotContactNumber = 'Contact number is required.';
      } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        hasError = true;
        _errPlotContactNumber = 'Enter a valid contact number.';
      }

      if (hasError) {
        setState(() {});
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingTypeForPayload(),
        'propertyTitle': title,
        'areaLabel': areaRaw,
        'price': price,
        'location': location,
        'additionalInformation': description.isEmpty ? null : description,
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'plots': <Map<String, dynamic>>[
          <String, dynamic>{
            'label': 'Plot 1',
            'polygonGeoJson': boundaryGeoJson,
          }
        ],
        'roads': const <Map<String, dynamic>>[],
      };
      createType = 'individual-plots';
    } else if (_propertyType == 'Independent House') {
      if (_houseTitle.trim().isEmpty) {
        setState(() {
          _applyHouseAutoTitleIfAllowed();
        });
      }

      final title = _houseTitle.trim();
      final location = _houseLocation.trim();
      final bedrooms = _parseInt(_houseBedrooms);
      final builtUpArea = _parseDouble(_houseBuiltUpArea);
      final floors = _parseInt(_houseFloors);
      final buildingAge = _parseInt(_houseBuildingAgeYears);
      final carParkingRaw = _houseCarParking.trim();
      final carParkingCount =
          _parseCarParkingCount(carParkingRaw.isEmpty ? 'None' : carParkingRaw);
      final price = _parseDouble(_housePrice);
      final contactName = _houseContactName.trim();
      final normalizedContact = _normalizeContact(_houseContactNumber);

      var hasError = false;
      if (location.isEmpty) {
        hasError = true;
        _errHouseLocation = 'Locality is required.';
      }
      if (_houseBedrooms.trim().isEmpty) {
        hasError = true;
        _errHouseBedrooms = 'Bedrooms is required.';
      } else if (bedrooms == null || bedrooms <= 0) {
        hasError = true;
        _errHouseBedrooms = 'Bedrooms must be a positive whole number.';
      }
      if (_houseBuiltUpArea.trim().isEmpty) {
        hasError = true;
        _errHouseBuiltUpArea = 'Built-up area is required.';
      } else if (builtUpArea == null || builtUpArea <= 0) {
        hasError = true;
        _errHouseBuiltUpArea = 'Built-up area must be greater than zero.';
      }
      if (_houseFloors.trim().isEmpty) {
        hasError = true;
        _errHouseFloors = 'Floors is required.';
      } else if (floors == null || floors <= 0) {
        hasError = true;
        _errHouseFloors = 'Floors must be a positive whole number.';
      }
      if (carParkingRaw.isEmpty) {
        hasError = true;
        _errHouseCarParking = 'Car parking is required.';
      } else if (carParkingCount < 0) {
        hasError = true;
        _errHouseCarParking = 'Invalid car parking value.';
      }
      if (_housePrice.trim().isEmpty) {
        hasError = true;
        _errHousePrice = 'Price is required.';
      } else if (price == null || price <= 0) {
        hasError = true;
        _errHousePrice = 'Price must be greater than zero.';
      }
      if (title.isEmpty) {
        hasError = true;
        _errHouseTitle = 'Property title is required.';
      }
      if (contactName.isEmpty) {
        hasError = true;
        _errHouseContactName = 'Contact name is required.';
      }
      if (_houseContactNumber.trim().isEmpty) {
        hasError = true;
        _errHouseContactNumber = 'Contact number is required.';
      } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        hasError = true;
        _errHouseContactNumber = 'Enter a valid contact number.';
      }

      if (hasError) {
        setState(() {});
        return;
      }

      if (buildingAge != null && buildingAge < 0) {
        _showError('Building age cannot be negative.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingTypeForPayload(),
        'propertyType': _propertyTypeValueMap['Independent House'],
        'propertyTitle': title,
        'bedrooms': bedrooms,
        'builtUpAreaInSquareFeet': builtUpArea,
        'floors': floors,
        'buildingAge': buildingAge,
        'carParkingCount': carParkingCount,
        'price': price,
        'location': location,
        'additionalDetails':
            _houseMoreDetails.trim().isEmpty ? null : _houseMoreDetails.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'houseBoundaryGeoJson': boundaryGeoJson,
      };
      createType = 'independent-houses';
    } else if (_propertyType == 'Apartment') {
      if (_apartmentTitle.trim().isEmpty) {
        setState(() {
          _applyApartmentAutoTitleIfAllowed();
        });
      }

      final title = _apartmentTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final location = _apartmentLocation.trim();
      final bedrooms = _parseInt(_apartmentBedrooms);
      final area = _parseDouble(_apartmentArea);
      final floor = _parseInt(_apartmentFloor);
      final totalFloors = _parseInt(_apartmentTotalFloors);
      final buildingAge = _parseInt(_apartmentBuildingAgeYears);
      final carParkingRaw = _apartmentCarParking.trim();
      final carParkingCount =
          _parseCarParkingCount(carParkingRaw.isEmpty ? 'None' : carParkingRaw);
      final price = _parseDouble(_apartmentPrice);

      var hasError = false;
      if (location.isEmpty) {
        hasError = true;
        _errApartmentLocation = 'Locality is required.';
      }
      if (_apartmentBedrooms.trim().isEmpty) {
        hasError = true;
        _errApartmentBedrooms = 'BHK is required.';
      } else if (bedrooms == null || bedrooms <= 0) {
        hasError = true;
        _errApartmentBedrooms = 'BHK must be a positive whole number.';
      }
      if (_apartmentArea.trim().isEmpty) {
        hasError = true;
        _errApartmentArea = 'Area is required.';
      } else if (area == null || area <= 0) {
        hasError = true;
        _errApartmentArea = 'Area must be greater than zero.';
      }
      if (_apartmentFloor.trim().isEmpty) {
        hasError = true;
        _errApartmentFloor = 'Property floor is required.';
      } else if (floor == null || floor < 0) {
        hasError = true;
        _errApartmentFloor = 'Floor must be zero or greater.';
      }
      if (_apartmentTotalFloors.trim().isEmpty) {
        hasError = true;
        _errApartmentTotalFloors = 'Total floors is required.';
      } else if (totalFloors == null || totalFloors <= 0) {
        hasError = true;
        _errApartmentTotalFloors =
            'Total floors must be a positive whole number.';
      }
      if (carParkingRaw.isEmpty) {
        hasError = true;
        _errApartmentCarParking = 'Car parking is required.';
      } else if (carParkingCount < 0) {
        hasError = true;
        _errApartmentCarParking = 'Invalid car parking value.';
      }
      if (_apartmentBuildingAgeYears.trim().isEmpty) {
        hasError = true;
        _errApartmentBuildingAgeYears = 'Building age is required.';
      } else if (buildingAge == null || buildingAge < 0) {
        hasError = true;
        _errApartmentBuildingAgeYears = 'Building age must be zero or greater.';
      }
      if (_apartmentPrice.trim().isEmpty) {
        hasError = true;
        _errApartmentPrice = 'Price is required.';
      } else if (price == null || price <= 0) {
        hasError = true;
        _errApartmentPrice = 'Price must be greater than zero.';
      }
      if (floor != null && totalFloors != null && floor > totalFloors) {
        hasError = true;
        _errApartmentFloor = 'Floor cannot exceed total floors.';
      }

      if (hasError) {
        setState(() {});
        return;
      }

      final contactName = _apartmentContactName.trim();
      if (contactName.isEmpty) {
        _showError('Contact name is required.');
        return;
      }

      final normalizedContact = _normalizeContact(_apartmentContactNumber);
      if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        _showError('Enter a valid contact number.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingTypeForPayload(),
        'propertyTitle': title,
        'bedrooms': bedrooms,
        'areaInSquareFeet': area,
        'floor': floor,
        'totalFloors': totalFloors,
        'carParkingCount': carParkingCount,
        'buildingAge': buildingAge,
        'price': price,
        'location': location,
        'additionalInformation': _apartmentMoreInfo.trim().isEmpty
            ? null
            : _apartmentMoreInfo.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'boundaryGeoJson': boundaryGeoJson,
      };
      createType = 'apartment-flats';
    } else if (_propertyType == 'Land') {
      if (_landTitle.trim().isEmpty) {
        setState(() {
          _applyLandAutoTitleIfAllowed();
        });
      }

      final title = _landTitle.trim();
      final landType = _landType.trim();
      final landTypeValue = _landTypeValueMap[landType];
      final areaRaw = _landArea.trim();
      final area = _parseDouble(areaRaw);
      final priceRaw = _landPrice.trim();
      final price = _parseDouble(priceRaw);
      final location = _landLocation.trim();
      final contactName = _landContactName.trim();
      final normalizedContact = _normalizeContact(_landContactNumber);

      var hasError = false;
      if (title.isEmpty) {
        hasError = true;
        _errLandTitle = 'Property title is required.';
      }
      if (landTypeValue == null) {
        hasError = true;
        _errLandType = 'Land type is required.';
      }
      if (areaRaw.isEmpty) {
        hasError = true;
        _errLandArea = 'Area is required.';
      } else if (area == null || area <= 0) {
        hasError = true;
        _errLandArea = 'Area must be greater than zero.';
      }
      if (priceRaw.isEmpty) {
        hasError = true;
        _errLandPrice = 'Price is required.';
      } else if (price == null || price <= 0) {
        hasError = true;
        _errLandPrice = 'Price must be greater than zero.';
      }
      if (location.isEmpty) {
        hasError = true;
        _errLandLocation = 'Locality is required.';
      }
      if (contactName.isEmpty) {
        hasError = true;
        _errLandContactName = 'Contact name is required.';
      }
      if (_landContactNumber.trim().isEmpty) {
        hasError = true;
        _errLandContactNumber = 'Contact number is required.';
      } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        hasError = true;
        _errLandContactNumber = 'Enter a valid contact number.';
      }

      if (hasError) {
        setState(() {});
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingTypeForPayload(),
        'propertyTitle': title,
        'landType': landTypeValue,
        'areaLabel': areaRaw,
        'price': price,
        'location': location,
        'additionalInformation':
            _landMoreInfo.trim().isEmpty ? null : _landMoreInfo.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'boundaryGeoJson': boundaryGeoJson,
        'roads': const <Map<String, dynamic>>[],
      };
      createType = 'lands';
    } else {
      if (_commercialTitle.trim().isEmpty) {
        setState(() {
          _applyCommercialAutoTitleIfAllowed();
        });
      }

      final title = _commercialTitle.trim();
      final location = _commercialLocation.trim();
      final builtUpArea = _parseDouble(_commercialBuiltUpArea);
      final price = _parseDouble(_commercialPrice);
      final contactName = _commercialContactName.trim();
      final normalizedContact = _normalizeContact(_commercialContactNumber);
      final spaceTypeValue = _commercialSpaceType.trim();

      final listingLower = _listingType.trim().toLowerCase();
      final priceLabel = listingLower == 'rent'
          ? 'Monthly rent'
          : listingLower == 'lease'
              ? 'Lease amount'
              : 'Price';

      var hasError = false;
      if (_listingType.trim().isEmpty) {
        hasError = true;
        _errListingType = 'Select a transaction type.';
      }
      if (spaceTypeValue.isEmpty) {
        hasError = true;
        _errCommercialSpaceType = 'Select a commercial type.';
      }
      if (title.isEmpty) {
        hasError = true;
        _errCommercialTitle = 'Property title is required.';
      }
      if (location.isEmpty) {
        hasError = true;
        _errCommercialLocation = 'Locality is required.';
      }
      if (_commercialBuiltUpArea.trim().isEmpty) {
        hasError = true;
        _errCommercialBuiltUpArea = 'Built-up area is required.';
      } else if (builtUpArea == null || builtUpArea <= 0) {
        hasError = true;
        _errCommercialBuiltUpArea = 'Built-up area must be greater than zero.';
      }
      if (_commercialPrice.trim().isEmpty) {
        hasError = true;
        _errCommercialPrice = '$priceLabel is required.';
      } else if (price == null || price <= 0) {
        hasError = true;
        _errCommercialPrice = '$priceLabel must be greater than zero.';
      }
      if (contactName.isEmpty) {
        hasError = true;
        _errCommercialContactName = 'Contact name is required.';
      }
      if (_commercialContactNumber.trim().isEmpty) {
        hasError = true;
        _errCommercialContactNumber = 'Contact number is required.';
      } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        hasError = true;
        _errCommercialContactNumber = 'Enter a valid contact number.';
      }

      if (hasError) {
        setState(() {});
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingTypeForPayload(),
        'propertyTitle': title,
        'spaceType': spaceTypeValue.isEmpty ? null : spaceTypeValue,
        'builtUpAreaInSquareFeet': builtUpArea,
        'price': price,
        'location': location,
        'additionalDetails': _commercialAdditionalDetails.trim().isEmpty
            ? null
            : _commercialAdditionalDetails.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'boundaryGeoJson': boundaryGeoJson,
        'roads': const <Map<String, dynamic>>[],
      };
      createType = 'commercial-spaces';
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
          payload: payload,
          bearerToken: token,
        );
        propertyIdForUploads = editPropertyId;
      } else {
        final created = await _api.createPropertyByType(
          propertyType: createType,
          payload: payload,
          bearerToken: token,
        );
        // Images upload + property detail endpoints use the generic PropertyId.
        // Upstream create responses sometimes include both:
        // - id: feature/entity id (type-specific)
        // - propertyId: generic property GUID
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

      final failedUploads = <String>[];
      if (_photos.isNotEmpty) {
        for (var i = 0; i < _photos.length; i += 1) {
          final picked = _photos[i].file;
          try {
            final existingCount = _existingPhotos.length;
            final shouldMakePrimary = existingCount == 0 && i == 0;
            await _api.uploadPropertyImage(
              propertyId: propertyIdForUploads,
              file: File(picked.path),
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
      }

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
            : 'Property saved, but ${failedUploads.length} photo(s) failed to upload. First: ${failedUploads.first}';
      } else {
        toastMessage = 'Property saved';
      }

      // Unfreeze the screen now that the save finished.
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }

      if (!mounted) return;

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

      return;
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

  Widget _textField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    int? minLines,
    String? errorText,
  }) {
    final fieldKey = ValueKey('$label-$_propertyType-$_prefillRevision');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          initialValue: controller == null ? value : null,
          onChanged: onChanged,
          keyboardType: keyboard,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          minLines: minLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        if (errorText != null && errorText.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            errorText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          items: options
              .map((opt) => DropdownMenuItem<String>(
                    value: opt,
                    child: Text(opt),
                  ))
              .toList(growable: false),
          icon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.keyboard_arrow_down),
          ),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        if (errorText != null && errorText.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            errorText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildPhotosSection() {
    final total = _totalPhotoCount;
    final countLabel = '$total/$_maxPhotos';
    final hasAny = _existingPhotos.isNotEmpty || _photos.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Property Photos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Text(
              countLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: _showAddPhotoOptions,
              child: const Text(
                'Add',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0FAD97),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!hasAny && !_isLoadingExistingPhotos)
          DottedBorder(
            color: const Color(0xFFCBD5E1),
            strokeWidth: 1.2,
            dashPattern: const <double>[6, 4],
            borderType: BorderType.RRect,
            radius: const Radius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: InkWell(
                  onTap: _showAddPhotoOptions,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(
                      'No photos added yet.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else ...[
          if (_isLoadingExistingPhotos && !hasAny)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading photos…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          if (_existingPhotos.isNotEmpty) ...[
            SizedBox(
              height: 86,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorder: _reorderExistingPhotos,
                itemCount: _existingPhotos.length,
                proxyDecorator: (child, _, __) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: child,
                  );
                },
                itemBuilder: (context, index) {
                  final img = _existingPhotos[index];
                  final url = _absoluteMediaUrl(img.fileUrl);
                  return Padding(
                    key: ValueKey('existing:${img.id ?? img.fileUrl}'),
                    padding: EdgeInsets.only(
                        right: index == _existingPhotos.length - 1 ? 0 : 10),
                    child: ReorderableDelayedDragStartListener(
                      index: index,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Container(
                              width: 112,
                              height: 86,
                              color: const Color(0xFFF1F5F9),
                              child: url.isEmpty
                                  ? const Center(
                                      child: Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Color(0xFF94A3B8)),
                                    )
                                  : Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                        child: Icon(Icons.broken_image_outlined,
                                            color: Color(0xFF94A3B8)),
                                      ),
                                    ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => _deleteExistingPhoto(index),
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.delete_outline,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  index == 0 ? 'Primary' : '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_photos.isNotEmpty) const SizedBox(height: 10),
          ],
          if (_photos.isNotEmpty) ...[
            SizedBox(
              height: 86,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorder: _reorderPhotos,
                itemCount: _photos.length,
                proxyDecorator: (child, _, __) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: child,
                  );
                },
                itemBuilder: (context, index) {
                  final selected = _photos[index];
                  final photo = selected.file;
                  return Padding(
                    key: ValueKey('photo:${selected.id}'),
                    padding: EdgeInsets.only(
                        right: index == _photos.length - 1 ? 0 : 10),
                    child: ReorderableDelayedDragStartListener(
                      index: index,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Container(
                              width: 112,
                              height: 86,
                              color: const Color(0xFFF1F5F9),
                              child: Image.file(
                                File(photo.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () => _removeImage(index),
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  index == 0 ? 'Primary' : '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_photos.length} new image${_photos.length == 1 ? '' : 's'} added',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _clearNewPhotos,
                  child: const Text(
                    'Clear New Photos',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _buildPropertyFields() {
    const carParkingOptions = <String>['None', '1', '2', '3', '4+'];
    const indianPriceFormatters = <TextInputFormatter>[
      IndianCurrencyInputFormatter(),
    ];
    switch (_propertyType) {
      case 'Plot':
        return [
          _textField(
            label: 'Plot Area (Sq.ft)',
            value: _plotArea,
            onChanged: (v) => setState(() {
              _plotArea = v;
              _errPlotArea = null;
            }),
            hint: 'e.g., 2400',
            keyboard: TextInputType.number,
            errorText: _errPlotArea,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _plotPrice,
            controller: _plotPriceController,
            inputFormatters: indianPriceFormatters,
            onChanged: (v) => setState(() {
              _plotPrice = v;
              _errPlotPrice = null;
            }),
            hint: 'e.g., ₹50,00,000',
            keyboard: TextInputType.number,
            errorText: _errPlotPrice,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Locality',
            value: _plotLocation,
            onChanged: (v) => setState(() {
              _plotLocation = v;
              _errPlotLocation = null;
              _applyPlotAutoTitleIfAllowed();
            }),
            hint: 'e.g., Anna Nagar, Chennai',
            errorText: _errPlotLocation,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Property Title',
            value: _plotTitle,
            controller: _plotTitleController,
            onChanged: (v) => setState(() {
              _plotTitle = v;
              _plotTitleManuallyEdited = v.trim().isNotEmpty;
              _errPlotTitle = null;
            }),
            hint: 'e.g., Residential Plot in Anna Nagar',
            errorText: _errPlotTitle,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Description',
            value: _plotMoreDetails,
            onChanged: (v) => setState(() {
              _plotMoreDetails = v;
              _errPlotMoreDetails = null;
            }),
            hint: 'e.g., East Facing, DTCP Approved',
            maxLines: 3,
            minLines: 3,
            errorText: _errPlotMoreDetails,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Contact Name',
                  value: _plotContactName,
                  controller: _plotContactNameController,
                  onChanged: (v) => setState(() {
                    _plotContactName = v;
                    _errPlotContactName = null;
                  }),
                  errorText: _errPlotContactName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Contact Number',
                  value: _plotContactNumber,
                  controller: _plotContactNumberController,
                  onChanged: (v) => setState(() {
                    _plotContactNumber = v;
                    _errPlotContactNumber = null;
                  }),
                  keyboard: TextInputType.phone,
                  errorText: _errPlotContactNumber,
                ),
              ),
            ],
          ),
        ];
      case 'Independent House':
        return [
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Bedrooms',
                  value: _houseBedrooms,
                  onChanged: (v) => setState(() {
                    _houseBedrooms = v;
                    _errHouseBedrooms = null;
                    _applyHouseAutoTitleIfAllowed();
                  }),
                  hint: 'e.g., 3',
                  keyboard: TextInputType.number,
                  errorText: _errHouseBedrooms,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Built-up Area (Sq.ft)',
                  value: _houseBuiltUpArea,
                  onChanged: (v) => setState(() {
                    _houseBuiltUpArea = v;
                    _errHouseBuiltUpArea = null;
                  }),
                  hint: 'e.g., 1500',
                  keyboard: TextInputType.number,
                  errorText: _errHouseBuiltUpArea,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Floors',
                  value: _houseFloors,
                  onChanged: (v) => setState(() {
                    _houseFloors = v;
                    _errHouseFloors = null;
                  }),
                  hint: 'e.g., 2',
                  keyboard: TextInputType.number,
                  errorText: _errHouseFloors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown(
                  label: 'Car Parking',
                  value: _houseCarParking.isEmpty ? 'None' : _houseCarParking,
                  options: carParkingOptions,
                  onChanged: (v) => setState(() {
                    _houseCarParking = v ?? 'None';
                    _errHouseCarParking = null;
                  }),
                  errorText: _errHouseCarParking,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Building Age (Years)',
            value: _houseBuildingAgeYears,
            onChanged: (v) => setState(() => _houseBuildingAgeYears = v),
            hint: 'e.g., 10',
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _housePrice,
            controller: _housePriceController,
            inputFormatters: indianPriceFormatters,
            onChanged: (v) => setState(() {
              _housePrice = v;
              _errHousePrice = null;
            }),
            hint: 'e.g., 75,00,000',
            keyboard: TextInputType.number,
            errorText: _errHousePrice,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Locality',
            value: _houseLocation,
            onChanged: (v) => setState(() {
              _houseLocation = v;
              _errHouseLocation = null;
              _applyHouseAutoTitleIfAllowed();
            }),
            hint: 'e.g., Anna Nagar, Chennai',
            errorText: _errHouseLocation,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Property Title',
            value: _houseTitle,
            controller: _houseTitleController,
            onChanged: (v) => setState(() {
              _houseTitle = v;
              _houseTitleManuallyEdited = v.trim().isNotEmpty;
              _errHouseTitle = null;
            }),
            hint: 'e.g., 2 BHK Independent House in Anna Nagar',
            errorText: _errHouseTitle,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Description',
            value: _houseMoreDetails,
            onChanged: (v) => setState(() => _houseMoreDetails = v),
            hint: 'e.g., East Facing, Car Parking Available',
            maxLines: 3,
            minLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Contact Name',
                  value: _houseContactName,
                  controller: _houseContactNameController,
                  onChanged: (v) => setState(() {
                    _houseContactName = v;
                    _errHouseContactName = null;
                  }),
                  errorText: _errHouseContactName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Contact Number',
                  value: _houseContactNumber,
                  controller: _houseContactNumberController,
                  onChanged: (v) => setState(() {
                    _houseContactNumber = v;
                    _errHouseContactNumber = null;
                  }),
                  keyboard: TextInputType.phone,
                  errorText: _errHouseContactNumber,
                ),
              ),
            ],
          ),
        ];
      case 'Apartment':
        return [
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'BHK',
                  value: _apartmentBedrooms,
                  onChanged: (v) => setState(() {
                    _apartmentBedrooms = v;
                    _errApartmentBedrooms = null;
                    _applyApartmentAutoTitleIfAllowed();
                  }),
                  hint: 'e.g., 2',
                  keyboard: TextInputType.number,
                  errorText: _errApartmentBedrooms,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Area (sq.ft.)',
                  value: _apartmentArea,
                  onChanged: (v) => setState(() {
                    _apartmentArea = v;
                    _errApartmentArea = null;
                  }),
                  hint: 'e.g., 950',
                  keyboard: TextInputType.number,
                  errorText: _errApartmentArea,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Property Floor',
                  value: _apartmentFloor,
                  onChanged: (v) => setState(() {
                    _apartmentFloor = v;
                    _errApartmentFloor = null;
                  }),
                  hint: 'e.g., 3',
                  keyboard: TextInputType.number,
                  errorText: _errApartmentFloor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Total Floors',
                  value: _apartmentTotalFloors,
                  onChanged: (v) => setState(() {
                    _apartmentTotalFloors = v;
                    _errApartmentTotalFloors = null;
                  }),
                  hint: 'e.g., 10',
                  keyboard: TextInputType.number,
                  errorText: _errApartmentTotalFloors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  label: 'Car Parking',
                  value: _apartmentCarParking.isEmpty
                      ? 'None'
                      : _apartmentCarParking,
                  options: carParkingOptions,
                  onChanged: (v) => setState(() {
                    _apartmentCarParking =
                        (v == null || v.trim().isEmpty) ? 'None' : v;
                    _errApartmentCarParking = null;
                  }),
                  errorText: _errApartmentCarParking,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Building Age (Years)',
                  value: _apartmentBuildingAgeYears,
                  onChanged: (v) => setState(() {
                    _apartmentBuildingAgeYears = v;
                    _errApartmentBuildingAgeYears = null;
                  }),
                  hint: 'e.g., 10',
                  keyboard: TextInputType.number,
                  errorText: _errApartmentBuildingAgeYears,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _apartmentPrice,
            controller: _apartmentPriceController,
            inputFormatters: indianPriceFormatters,
            onChanged: (v) => setState(() {
              _apartmentPrice = v;
              _errApartmentPrice = null;
            }),
            hint: 'e.g., ₹65,00,000',
            keyboard: TextInputType.number,
            errorText: _errApartmentPrice,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Locality',
            value: _apartmentLocation,
            onChanged: (v) => setState(() {
              _apartmentLocation = v;
              _errApartmentLocation = null;
              _applyApartmentAutoTitleIfAllowed();
            }),
            hint: 'e.g., Anna Nagar, Chennai',
            errorText: _errApartmentLocation,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Property Title',
            value: _apartmentTitle,
            controller: _apartmentTitleController,
            onChanged: (v) => setState(() {
              _apartmentTitle = v;
              _apartmentTitleManuallyEdited = v.trim().isNotEmpty;
            }),
            hint: 'e.g., 2 BHK Apartment in Anna Nagar',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Information',
            value: _apartmentMoreInfo,
            onChanged: (v) => setState(() => _apartmentMoreInfo = v),
            hint:
                'e.g., Near metro station, includes covered parking, recently renovated',
            maxLines: 3,
            minLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Contact Name',
                  value: _apartmentContactName,
                  controller: _apartmentContactNameController,
                  onChanged: (v) => setState(() => _apartmentContactName = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Contact Number',
                  value: _apartmentContactNumber,
                  controller: _apartmentContactNumberController,
                  onChanged: (v) => setState(() => _apartmentContactNumber = v),
                  keyboard: TextInputType.phone,
                ),
              ),
            ],
          ),
        ];
      case 'Land':
        return [
          _dropdown(
            label: 'Land Type',
            value: _landType.isEmpty ? 'Select' : _landType,
            options: <String>['Select', ..._landTypeValueMap.keys],
            onChanged: (v) => setState(() {
              final next = (v ?? '').trim();
              _landType = next == 'Select' ? '' : next;
              _errLandType = null;
              _applyLandAutoTitleIfAllowed();
            }),
            errorText: _errLandType,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Area (sq.ft)',
            value: _landArea,
            onChanged: (v) => setState(() {
              _landArea = v;
              _errLandArea = null;
            }),
            hint: 'e.g., 2400 sq.ft',
            keyboard: TextInputType.number,
            errorText: _errLandArea,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _landPrice,
            controller: _landPriceController,
            inputFormatters: indianPriceFormatters,
            onChanged: (v) => setState(() {
              _landPrice = v;
              _errLandPrice = null;
            }),
            hint: 'e.g., ₹50,00,000',
            keyboard: TextInputType.number,
            errorText: _errLandPrice,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Locality',
            value: _landLocation,
            onChanged: (v) => setState(() {
              _landLocation = v;
              _errLandLocation = null;
              _applyLandAutoTitleIfAllowed();
            }),
            hint: 'e.g., Anna Nagar, Chennai',
            errorText: _errLandLocation,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Property Title',
            value: _landTitle,
            controller: _landTitleController,
            onChanged: (v) => setState(() {
              _landTitle = v;
              _landTitleManuallyEdited = v.trim().isNotEmpty;
              _errLandTitle = null;
            }),
            hint: 'e.g., Residential Plot in Anna Nagar',
            errorText: _errLandTitle,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'More Information',
            value: _landMoreInfo,
            onChanged: (v) => setState(() => _landMoreInfo = v),
            hint: 'e.g., Near school, 30 ft road access',
            maxLines: 3,
            minLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Contact Name',
                  value: _landContactName,
                  controller: _landContactNameController,
                  onChanged: (v) => setState(() {
                    _landContactName = v;
                    _errLandContactName = null;
                  }),
                  errorText: _errLandContactName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Contact Number',
                  value: _landContactNumber,
                  controller: _landContactNumberController,
                  onChanged: (v) => setState(() {
                    _landContactNumber = v;
                    _errLandContactNumber = null;
                  }),
                  keyboard: TextInputType.phone,
                  errorText: _errLandContactNumber,
                ),
              ),
            ],
          ),
        ];
      default:
        final listing = _listingType.trim().toLowerCase();
        final commercialPriceLabel = listing == 'rent'
            ? 'Monthly Rent'
            : listing == 'lease'
                ? 'Lease Amount'
                : 'Price';
        final commercialPriceHint = listing == 'rent'
            ? 'e.g., ₹25,000'
            : listing == 'lease'
                ? 'e.g., ₹10,00,000'
                : 'e.g., ₹45,00,000';

        return [
          _dropdown(
            label: 'Commercial Type',
            value:
                _commercialSpaceType.isEmpty ? 'Select' : _commercialSpaceType,
            options: <String>['Select', ..._commercialTypeOptions],
            onChanged: (v) => setState(() {
              final next = (v ?? '').trim();
              _commercialSpaceType = next == 'Select' ? '' : next;
              _errCommercialSpaceType = null;
              _applyCommercialAutoTitleIfAllowed();
            }),
            errorText: _errCommercialSpaceType,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Built-up Area (Sq.ft)',
            value: _commercialBuiltUpArea,
            onChanged: (v) => setState(() {
              _commercialBuiltUpArea = v;
              _errCommercialBuiltUpArea = null;
            }),
            hint: 'e.g., 1200',
            keyboard: TextInputType.number,
            errorText: _errCommercialBuiltUpArea,
          ),
          const SizedBox(height: 12),
          _textField(
            label: commercialPriceLabel,
            value: _commercialPrice,
            controller: _commercialPriceController,
            inputFormatters: indianPriceFormatters,
            onChanged: (v) => setState(() {
              _commercialPrice = v;
              _errCommercialPrice = null;
            }),
            hint: commercialPriceHint,
            keyboard: TextInputType.number,
            errorText: _errCommercialPrice,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Locality',
            value: _commercialLocation,
            onChanged: (v) => setState(() {
              _commercialLocation = v;
              _errCommercialLocation = null;
              _applyCommercialAutoTitleIfAllowed();
            }),
            hint: 'e.g., Anna Nagar, Chennai',
            errorText: _errCommercialLocation,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Property Title',
            value: _commercialTitle,
            controller: _commercialTitleController,
            onChanged: (v) => setState(() {
              _commercialTitle = v;
              _commercialTitleManuallyEdited = v.trim().isNotEmpty;
              _errCommercialTitle = null;
            }),
            hint: 'e.g., Office Space for Rent in T. Nagar',
            errorText: _errCommercialTitle,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Description',
            value: _commercialAdditionalDetails,
            onChanged: (v) => setState(() => _commercialAdditionalDetails = v),
            hint: 'e.g., Ground Floor, Road Facing, Car Parking Available',
            maxLines: 3,
            minLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _textField(
                  label: 'Contact Name',
                  value: _commercialContactName,
                  controller: _commercialContactNameController,
                  onChanged: (v) => setState(() {
                    _commercialContactName = v;
                    _errCommercialContactName = null;
                  }),
                  errorText: _errCommercialContactName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  label: 'Contact Number',
                  value: _commercialContactNumber,
                  controller: _commercialContactNumberController,
                  onChanged: (v) => setState(() {
                    _commercialContactNumber = v;
                    _errCommercialContactNumber = null;
                  }),
                  keyboard: TextInputType.phone,
                  errorText: _errCommercialContactNumber,
                ),
              ),
            ],
          ),
        ];
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
                    _dropdown(
                      label: 'Listing Type',
                      value: _listingType,
                      options: _listingTypes,
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
                  _dropdown(
                    label: 'Property Type',
                    value: _propertyType,
                    options: _propertyTypes,
                    onChanged: (v) =>
                        setState(() => _propertyType = v ?? 'Plot'),
                  ),
                  const SizedBox(height: 10),
                  ..._buildPropertyFields(),
                  const SizedBox(height: 16),
                  _buildPhotosSection(),
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
              if (_isSaving) ...[
                const ModalBarrier(
                  dismissible: false,
                  color: Color(0x1A000000),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Saving…',
                            style: TextStyle(
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
              if (_isPrefilling) ...[
                const ModalBarrier(
                  dismissible: false,
                  color: Color(0x1A000000),
                ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Loading…',
                            style: TextStyle(
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
            ],
          ),
        ),
      ),
    );
  }
}

class IndianCurrencyInputFormatter extends TextInputFormatter {
  const IndianCurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = _formatIndianDigits(digitsOnly);
    final digitsBeforeCursor = _countDigitsBeforeCursor(newValue);
    final cursor = _cursorOffsetForDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  int _countDigitsBeforeCursor(TextEditingValue v) {
    final cursor = v.selection.baseOffset;
    final safe =
        cursor < 0 ? 0 : (cursor > v.text.length ? v.text.length : cursor);
    final before = v.text.substring(0, safe);
    return before.replaceAll(RegExp(r'\D'), '').length;
  }

  int _cursorOffsetForDigits(String formatted, int digitsCount) {
    if (digitsCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i += 1) {
      final ch = formatted.codeUnitAt(i);
      final isDigit = ch >= 48 && ch <= 57;
      if (isDigit) {
        seen += 1;
        if (seen >= digitsCount) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }

  String _formatIndianDigits(String digits) {
    var d = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (d.isEmpty) return '';
    if (d.length <= 3) return d;

    final last3 = d.substring(d.length - 3);
    var rest = d.substring(0, d.length - 3);

    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) {
      parts.insert(0, rest);
    }

    return '${parts.join(',')},$last3';
  }
}
