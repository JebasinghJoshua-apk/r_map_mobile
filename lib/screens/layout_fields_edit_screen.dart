import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/api_constants.dart';
import '../models/image_summary.dart';
import '../services/mobile_bff_layouts_api.dart';
import '../services/mobile_bff_map_api.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/property_form/property_form.dart';
import '../widgets/toast_message.dart';

class LayoutFieldsEditScreen extends StatefulWidget {
  const LayoutFieldsEditScreen({
    super.key,
    required this.layoutId,
  });

  final String layoutId;

  @override
  State<LayoutFieldsEditScreen> createState() => _LayoutFieldsEditScreenState();
}

class _LayoutFieldsEditScreenState extends State<LayoutFieldsEditScreen> {
  final MobileBffLayoutsApi _layoutsApi = MobileBffLayoutsApi();
  final MobileBffMapApi _mapApi = MobileBffMapApi();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _plotsCountController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _additionalDetailsController =
      TextEditingController();
  final TextEditingController _contactNumberController = TextEditingController();

  String? _currentDescription;
  final List<ImageSummary> _existingPhotos = <ImageSummary>[];
  final List<SelectedPhoto> _photos = <SelectedPhoto>[];
  bool _isLoadingExistingPhotos = false;
  bool _didLoadExistingPhotos = false;
  int _photoSequence = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _plotsCountController.dispose();
    _locationController.dispose();
    _additionalDetailsController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadLayout() async {
    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      AuthDialog.showLogin(context);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final detail = await _layoutsApi.getLayoutDetail(
        layoutId: widget.layoutId,
        bearerToken: token,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _nameController.text = detail.name;
        _areaController.text = detail.area ?? '';
        _plotsCountController.text = detail.plotsCount?.toString() ?? '';
        _locationController.text = detail.locationDetails ?? '';
        _additionalDetailsController.text =
            MobileBffLayoutsApi.additionalDetailsForInput(
          detail.additionalDetails,
        );
        _contactNumberController.text = detail.contactNumbers ?? '';
        _currentDescription = detail.description;
        _isLoading = false;
      });

      await _loadExistingPhotosIfNeeded(token);
    } on LayoutsApiException catch (ex) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ToastMessage.show(context, ex.message);
      Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ToastMessage.show(context, 'Failed to load layout details.');
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _loadExistingPhotosIfNeeded(String bearerToken) async {
    if (_didLoadExistingPhotos) return;

    if (mounted) {
      setState(() {
        _isLoadingExistingPhotos = true;
      });
    }

    try {
      final images = await _mapApi.getPropertyMedia(
        propertyType: 'layout',
        entityId: widget.layoutId,
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

  int get _totalPhotoCount => _existingPhotos.length + _photos.length;

  int get _remainingPhotoSlots {
    final remaining = kMaxPropertyPhotos - _totalPhotoCount;
    return remaining < 0 ? 0 : remaining;
  }

  SelectedPhoto _wrapPhoto(XFile file) {
    _photoSequence += 1;
    final id = '${DateTime.now().microsecondsSinceEpoch}_$_photoSequence';
    return SelectedPhoto(id: id, file: file);
  }

  String _absoluteMediaUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    const base = ApiConstants.mobileBffBaseUrl;
    if (base.trim().isEmpty) return trimmed;

    final normalizedBase = base.endsWith('/') ? base : '$base/';
    final baseUri = Uri.parse(normalizedBase);
    final relative = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return baseUri.resolve(relative).toString();
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

  void _reorderNewPhotos(int oldIndex, int newIndex) {
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

  Future<void> _removeNewPhoto(int index) async {
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
    if (index < 0 || index >= _existingPhotos.length) return;
    if (_isSaving || _isLoading) return;

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
      await _mapApi.deleteImage(imageId: id, bearerToken: token);
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
    if (_existingPhotos.isEmpty) return;

    for (var i = 0; i < _existingPhotos.length; i += 1) {
      final img = _existingPhotos[i];
      final id = img.id?.trim() ?? '';
      if (id.isEmpty) continue;

      try {
        await _mapApi.updateImage(
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

  Future<List<String>> _uploadNewPhotos(String token) async {
    final failedUploads = <String>[];
    if (_photos.isEmpty) return failedUploads;

    for (var i = 0; i < _photos.length; i += 1) {
      final picked = _photos[i].file;
      try {
        final existingCount = _existingPhotos.length;
        final shouldMakePrimary = existingCount == 0 && i == 0;
        final fileToUpload = await _ensureUploadableFormat(File(picked.path));
        await _mapApi.uploadPropertyImage(
          propertyId: widget.layoutId,
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
      if (byteData == null) return file;

      final convertedPath = file.path.replaceAll(RegExp(r'\.(heic|heif)$', caseSensitive: false), '.png');
      final converted = File(convertedPath);
      await converted.writeAsBytes(byteData.buffer.asUint8List());
      return converted;
    } catch (_) {
      return file;
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final session = AuthScope.of(context).session;
    final token = session?.token;
    if (token == null || token.trim().isEmpty) {
      AuthDialog.showLogin(context);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ToastMessage.show(context, 'Layout name is required.');
      return;
    }

    final plotsText = _plotsCountController.text.trim();
    int? plotsCount;
    if (plotsText.isNotEmpty) {
      plotsCount = int.tryParse(plotsText);
      if (plotsCount == null || plotsCount <= 0) {
        ToastMessage.show(context, 'Plots Count must be a positive number.');
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _layoutsApi.updateLayout(
        layoutId: widget.layoutId,
        name: name,
        area: _areaController.text,
        plotsCount: plotsCount,
        locationDetails: _locationController.text,
        additionalDetails: _additionalDetailsController.text,
        contactNumbers: _contactNumberController.text,
        description: _currentDescription,
        bearerToken: token,
      );

      await _persistExistingPhotoOrder(token);
      final failedUploads = await _uploadNewPhotos(token);

      if (!mounted) {
        return;
      }

      setState(() {
        _photos.clear();
        _isSaving = false;
      });

      final message = failedUploads.isEmpty
          ? 'Layout updated successfully.'
          : 'Layout updated, but ${failedUploads.length} photo(s) failed to upload.';
      ToastMessage.show(context, message);
      Navigator.of(context).pop(true);
    } on LayoutsApiException catch (ex) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      ToastMessage.show(context, 'Failed to update layout.');
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Layout'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: (_isLoading || _isSaving) ? null : _save,
              child: Text(_isSaving ? 'Saving...' : 'Save'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildField(
                    controller: _nameController,
                    label: 'Layout Name',
                  ),
                  _buildField(
                    controller: _areaController,
                    label: 'Area',
                  ),
                  _buildField(
                    controller: _plotsCountController,
                    label: 'Plots Count',
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(
                    controller: _locationController,
                    label: 'Location',
                  ),
                  _buildField(
                    controller: _additionalDetailsController,
                    label: 'Additional Details',
                    minLines: 7,
                    maxLines: 9,
                  ),
                  _buildField(
                    controller: _contactNumberController,
                    label: 'Contact Number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 4),
                  PropertyPhotoSection(
                    existingPhotos: _existingPhotos,
                    newPhotos: _photos,
                    isLoadingExistingPhotos: _isLoadingExistingPhotos,
                    onAddPhotoPressed: _showAddPhotoOptions,
                    onDeleteExistingPhoto: _deleteExistingPhoto,
                    onRemoveNewPhoto: _removeNewPhoto,
                    onReorderExistingPhotos: _reorderExistingPhotos,
                    onReorderNewPhotos: _reorderNewPhotos,
                    onClearNewPhotos: _clearNewPhotos,
                    absoluteMediaUrl: _absoluteMediaUrl,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: (_isLoading || _isSaving) ? null : _save,
                    child: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  ),
                ],
              ),
            ),
    );
  }
}
