import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../utils/geojson.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/toast_message.dart';

class PropertyDetailsFormScreen extends StatefulWidget {
  const PropertyDetailsFormScreen({
    super.key,
    required this.boundaryPoints,
    this.initialPropertyType,
  });

  final List<LatLng> boundaryPoints;
  final String? initialPropertyType;

  @override
  State<PropertyDetailsFormScreen> createState() =>
      _PropertyDetailsFormScreenState();
}

class _PropertyDetailsFormScreenState extends State<PropertyDetailsFormScreen> {
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
  String _apartmentPrice = '';
  String _apartmentLocation = '';
  String _apartmentMoreInfo = '';

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

  final List<XFile> _photos = <XFile>[];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPropertyType?.trim();
    _propertyType = _propertyTypes.contains(initial) ? initial! : 'Plot';
    _landType = _landTypeValueMap.keys.first;
  }

  double? _parseDouble(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned.replaceAll(',', ''));
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

  Future<void> _pickImages() async {
    final picks = await _imagePicker.pickMultiImage(imageQuality: 85);
    if (picks.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _photos.addAll(picks);
    });
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= _photos.length) return;
    setState(() {
      _photos.removeAt(index);
    });
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

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
      final title = _plotTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final location = _plotLocation.trim();
      if (location.isEmpty) {
        _showError('Provide a location or neighborhood description.');
        return;
      }

      final price = _parseDouble(_plotPrice);
      if (price == null || price <= 0) {
        _showError('Price must be greater than zero.');
        return;
      }

      final contactName = _plotContactName.trim();
      if (contactName.isEmpty) {
        _showError('Contact name is required.');
        return;
      }

      final normalizedContact = _normalizeContact(_plotContactNumber);
      if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        _showError('Enter a valid contact number.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingType,
        'propertyTitle': title,
        'areaLabel': _plotArea.trim().isEmpty ? null : _plotArea.trim(),
        'price': price,
        'location': location,
        'additionalInformation':
            _plotMoreDetails.trim().isEmpty ? null : _plotMoreDetails.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'plots': <Map<String, dynamic>>[
          <String, dynamic>{
            'label': 'Plot 1',
            'polygonGeoJson': boundaryGeoJson,
          }
        ],
      };
      createType = 'individual-plots';
    } else if (_propertyType == 'Independent House') {
      final title = _houseTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final location = _houseLocation.trim();
      if (location.isEmpty) {
        _showError('Provide a location or neighborhood description.');
        return;
      }

      final bedrooms = _parseInt(_houseBedrooms);
      if (bedrooms == null || bedrooms <= 0) {
        _showError('Bedrooms must be a positive whole number.');
        return;
      }

      final builtUpArea = _parseDouble(_houseBuiltUpArea);
      if (builtUpArea == null || builtUpArea <= 0) {
        _showError('Built-up area must be greater than zero.');
        return;
      }

      final price = _parseDouble(_housePrice);
      if (price == null || price <= 0) {
        _showError('Price must be greater than zero.');
        return;
      }

      final contactName = _houseContactName.trim();
      if (contactName.isEmpty) {
        _showError('Contact name is required.');
        return;
      }

      final normalizedContact = _normalizeContact(_houseContactNumber);
      if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        _showError('Enter a valid contact number.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingType,
        'propertyType': _propertyTypeValueMap['Independent House'],
        'propertyTitle': title,
        'bedrooms': bedrooms,
        'builtUpAreaInSquareFeet': builtUpArea,
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
      final title = _apartmentTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final location = _apartmentLocation.trim();
      if (location.isEmpty) {
        _showError('Provide a location or neighborhood description.');
        return;
      }

      final bedrooms = _parseInt(_apartmentBedrooms);
      if (bedrooms == null || bedrooms <= 0) {
        _showError('Bedrooms must be a positive whole number.');
        return;
      }

      final area = _parseDouble(_apartmentArea);
      if (area == null || area <= 0) {
        _showError('Floor area must be greater than zero.');
        return;
      }

      final floor = _parseInt(_apartmentFloor);
      if (floor == null || floor < 0) {
        _showError('Floor must be zero or greater.');
        return;
      }

      final totalFloors = _parseInt(_apartmentTotalFloors);
      if (totalFloors == null || totalFloors <= 0) {
        _showError('Total floors must be a positive whole number.');
        return;
      }

      if (floor > totalFloors) {
        _showError('Floor cannot exceed total floors.');
        return;
      }

      final price = _parseDouble(_apartmentPrice);
      if (price == null || price <= 0) {
        _showError('Price must be greater than zero.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingType,
        'propertyTitle': title,
        'bedrooms': bedrooms,
        'areaInSquareFeet': area,
        'floor': floor,
        'totalFloors': totalFloors,
        'price': price,
        'location': location,
        'additionalInformation': _apartmentMoreInfo.trim().isEmpty
            ? null
            : _apartmentMoreInfo.trim(),
        'boundaryGeoJson': boundaryGeoJson,
      };
      createType = 'apartment-flats';
    } else if (_propertyType == 'Land') {
      final title = _landTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final landType = _landType.trim();
      final landTypeValue = _landTypeValueMap[landType];
      if (landTypeValue == null) {
        _showError('Select a land type.');
        return;
      }

      final price = _parseDouble(_landPrice);
      if (price == null || price <= 0) {
        _showError('Price must be greater than zero.');
        return;
      }

      final location = _landLocation.trim();
      if (location.isEmpty) {
        _showError('Enter the land location.');
        return;
      }

      final contactName = _landContactName.trim();
      if (contactName.isEmpty) {
        _showError('Contact name is required.');
        return;
      }

      final normalizedContact = _normalizeContact(_landContactNumber);
      if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        _showError('Enter a valid contact number.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingType,
        'propertyTitle': title,
        'landType': landTypeValue,
        'areaLabel': _landArea.trim().isEmpty ? null : _landArea.trim(),
        'price': price,
        'location': location,
        'additionalInformation':
            _landMoreInfo.trim().isEmpty ? null : _landMoreInfo.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'boundaryGeoJson': boundaryGeoJson,
      };
      createType = 'lands';
    } else {
      final title = _commercialTitle.trim();
      if (title.isEmpty) {
        _showError('Enter a property title.');
        return;
      }

      final location = _commercialLocation.trim();
      if (location.isEmpty) {
        _showError('Provide a location or neighborhood description.');
        return;
      }

      final builtUpArea = _parseDouble(_commercialBuiltUpArea);
      if (builtUpArea == null || builtUpArea <= 0) {
        _showError('Built-up area must be greater than zero.');
        return;
      }

      final price = _parseDouble(_commercialPrice);
      if (price == null || price <= 0) {
        _showError('Price must be greater than zero.');
        return;
      }

      final contactName = _commercialContactName.trim();
      if (contactName.isEmpty) {
        _showError('Contact name is required.');
        return;
      }

      final normalizedContact = _normalizeContact(_commercialContactNumber);
      if (normalizedContact.isEmpty || normalizedContact.length < 6) {
        _showError('Enter a valid contact number.');
        return;
      }

      payload = <String, dynamic>{
        'listingType': _listingType,
        'propertyTitle': title,
        'spaceType': _commercialSpaceType.trim().isEmpty
            ? null
            : _commercialSpaceType.trim(),
        'builtUpAreaInSquareFeet': builtUpArea,
        'price': price,
        'location': location,
        'additionalDetails': _commercialAdditionalDetails.trim().isEmpty
            ? null
            : _commercialAdditionalDetails.trim(),
        'contactName': contactName,
        'contactNumber': normalizedContact,
        'boundaryGeoJson': boundaryGeoJson,
      };
      createType = 'commercial-spaces';
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final created = await _api.createPropertyByType(
        propertyType: createType,
        payload: payload,
        bearerToken: token,
      );
      final createdId = (created['id'] ?? created['propertyId'])?.toString();
      if (createdId == null || createdId.trim().isEmpty) {
        throw const MapApiException(
            'Created property response was missing an id.');
      }

      if (_photos.isNotEmpty) {
        for (var i = 0; i < _photos.length; i += 1) {
          final file = _photos[i];
          await _api.uploadPropertyImage(
            propertyId: createdId,
            file: File(file.path),
            bearerToken: token,
            isPrimary: i == 0,
            displayOrder: i + 1,
          );
        }
      }

      try {
        await _api.getPropertyDetail(
          propertyId: createdId,
          bearerToken: token,
        );
      } catch (_) {
        if (mounted) {
          ToastMessage.show(
            context,
            'Property saved, but failed to refresh details.',
          );
        }
      }

      if (!mounted) return;
      ToastMessage.show(context, 'Property saved');
      Navigator.of(context).pop(createdId);
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
    String? hint,
    TextInputType? keyboard,
  }) {
    final fieldKey = ValueKey('$label-$_propertyType');
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
          initialValue: value,
          onChanged: onChanged,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
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
          value: value,
          items: options
              .map((opt) => DropdownMenuItem<String>(
                    value: opt,
                    child: Text(opt),
                  ))
              .toList(growable: false),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Property Photos'),
        const SizedBox(height: 4),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Add photos'),
            ),
            const SizedBox(width: 12),
            Text(
              _photos.isEmpty
                  ? 'No photos selected'
                  : '${_photos.length} selected',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(
              _photos.length,
              (index) => Chip(
                label: Text(
                  _photos[index].name,
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: () => _removeImage(index),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildPropertyFields() {
    switch (_propertyType) {
      case 'Plot':
        return [
          _sectionTitle('Plot Details'),
          _textField(
            label: 'Property Title',
            value: _plotTitle,
            onChanged: (v) => setState(() => _plotTitle = v),
            hint: 'e.g., Residential plot in Anna Nagar',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Area (optional)',
            value: _plotArea,
            onChanged: (v) => setState(() => _plotArea = v),
            hint: 'e.g., 2400 sqft',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _plotPrice,
            onChanged: (v) => setState(() => _plotPrice = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Location',
            value: _plotLocation,
            onChanged: (v) => setState(() => _plotLocation = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Information',
            value: _plotMoreDetails,
            onChanged: (v) => setState(() => _plotMoreDetails = v),
            hint: 'Optional',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Name',
            value: _plotContactName,
            onChanged: (v) => setState(() => _plotContactName = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Number',
            value: _plotContactNumber,
            onChanged: (v) => setState(() => _plotContactNumber = v),
            keyboard: TextInputType.phone,
          ),
        ];
      case 'Independent House':
        return [
          _sectionTitle('House Details'),
          _textField(
            label: 'Property Title',
            value: _houseTitle,
            onChanged: (v) => setState(() => _houseTitle = v),
            hint: 'e.g., 3 BHK Independent House',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Bedrooms',
            value: _houseBedrooms,
            onChanged: (v) => setState(() => _houseBedrooms = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Built-up Area (sq.ft.)',
            value: _houseBuiltUpArea,
            onChanged: (v) => setState(() => _houseBuiltUpArea = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _housePrice,
            onChanged: (v) => setState(() => _housePrice = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Location',
            value: _houseLocation,
            onChanged: (v) => setState(() => _houseLocation = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Details',
            value: _houseMoreDetails,
            onChanged: (v) => setState(() => _houseMoreDetails = v),
            hint: 'Optional',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Name',
            value: _houseContactName,
            onChanged: (v) => setState(() => _houseContactName = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Number',
            value: _houseContactNumber,
            onChanged: (v) => setState(() => _houseContactNumber = v),
            keyboard: TextInputType.phone,
          ),
        ];
      case 'Apartment':
        return [
          _sectionTitle('Apartment Details'),
          _textField(
            label: 'Property Title',
            value: _apartmentTitle,
            onChanged: (v) => setState(() => _apartmentTitle = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Bedrooms',
            value: _apartmentBedrooms,
            onChanged: (v) => setState(() => _apartmentBedrooms = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Area (sq.ft.)',
            value: _apartmentArea,
            onChanged: (v) => setState(() => _apartmentArea = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Floor',
            value: _apartmentFloor,
            onChanged: (v) => setState(() => _apartmentFloor = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Total Floors',
            value: _apartmentTotalFloors,
            onChanged: (v) => setState(() => _apartmentTotalFloors = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _apartmentPrice,
            onChanged: (v) => setState(() => _apartmentPrice = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Location',
            value: _apartmentLocation,
            onChanged: (v) => setState(() => _apartmentLocation = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Information',
            value: _apartmentMoreInfo,
            onChanged: (v) => setState(() => _apartmentMoreInfo = v),
            hint: 'Optional',
          ),
        ];
      case 'Land':
        return [
          _sectionTitle('Land Details'),
          _textField(
            label: 'Property Title',
            value: _landTitle,
            onChanged: (v) => setState(() => _landTitle = v),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: 'Land Type',
            value: _landType.isEmpty ? 'Residential' : _landType,
            options: _landTypeValueMap.keys.toList(growable: false),
            onChanged: (v) => setState(() => _landType = v ?? ''),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Area (optional)',
            value: _landArea,
            onChanged: (v) => setState(() => _landArea = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _landPrice,
            onChanged: (v) => setState(() => _landPrice = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Location',
            value: _landLocation,
            onChanged: (v) => setState(() => _landLocation = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Information',
            value: _landMoreInfo,
            onChanged: (v) => setState(() => _landMoreInfo = v),
            hint: 'Optional',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Name',
            value: _landContactName,
            onChanged: (v) => setState(() => _landContactName = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Number',
            value: _landContactNumber,
            onChanged: (v) => setState(() => _landContactNumber = v),
            keyboard: TextInputType.phone,
          ),
        ];
      default:
        return [
          _sectionTitle('Commercial Space Details'),
          _textField(
            label: 'Property Title',
            value: _commercialTitle,
            onChanged: (v) => setState(() => _commercialTitle = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Space Type (optional)',
            value: _commercialSpaceType,
            onChanged: (v) => setState(() => _commercialSpaceType = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Built-up Area (sq.ft.)',
            value: _commercialBuiltUpArea,
            onChanged: (v) => setState(() => _commercialBuiltUpArea = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Price',
            value: _commercialPrice,
            onChanged: (v) => setState(() => _commercialPrice = v),
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Location',
            value: _commercialLocation,
            onChanged: (v) => setState(() => _commercialLocation = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Additional Details',
            value: _commercialAdditionalDetails,
            onChanged: (v) => setState(() => _commercialAdditionalDetails = v),
            hint: 'Optional',
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Name',
            value: _commercialContactName,
            onChanged: (v) => setState(() => _commercialContactName = v),
          ),
          const SizedBox(height: 12),
          _textField(
            label: 'Contact Number',
            value: _commercialContactNumber,
            onChanged: (v) => setState(() => _commercialContactNumber = v),
            keyboard: TextInputType.phone,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              onPressed: _isSaving ? null : _handleSave,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0FAD97),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(_isSaving ? 'Saving...' : 'Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _dropdown(
              label: 'Property Type',
              value: _propertyType,
              options: _propertyTypes,
              onChanged: (v) => setState(() => _propertyType = v ?? 'Plot'),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Listing Type',
              value: _listingType,
              options: _listingTypes,
              onChanged: (v) => setState(() => _listingType = v ?? 'Sell'),
            ),
            const SizedBox(height: 10),
            ..._buildPropertyFields(),
            const SizedBox(height: 16),
            _buildPhotosSection(),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _handleSave,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Saving...' : 'Save Property'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: const Color(0xFF0FAD97),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
