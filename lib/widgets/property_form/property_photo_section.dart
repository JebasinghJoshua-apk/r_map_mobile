import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/image_summary.dart';
import 'property_form_constants.dart';

/// Wrapper for a newly selected photo with a unique ID.
class SelectedPhoto {
  const SelectedPhoto({required this.id, required this.file});

  final String id;
  final XFile file;
}

/// Displays and manages property photos (existing + new).
class PropertyPhotoSection extends StatelessWidget {
  const PropertyPhotoSection({
    required this.existingPhotos,
    required this.newPhotos,
    required this.isLoadingExistingPhotos,
    required this.onAddPhotoPressed,
    required this.onDeleteExistingPhoto,
    required this.onRemoveNewPhoto,
    required this.onReorderExistingPhotos,
    required this.onReorderNewPhotos,
    required this.onClearNewPhotos,
    required this.absoluteMediaUrl,
    super.key,
  });

  final List<ImageSummary> existingPhotos;
  final List<SelectedPhoto> newPhotos;
  final bool isLoadingExistingPhotos;
  final VoidCallback onAddPhotoPressed;
  final void Function(int index) onDeleteExistingPhoto;
  final void Function(int index) onRemoveNewPhoto;
  final void Function(int oldIndex, int newIndex) onReorderExistingPhotos;
  final void Function(int oldIndex, int newIndex) onReorderNewPhotos;
  final VoidCallback onClearNewPhotos;
  final String Function(String rawUrl) absoluteMediaUrl;

  int get _totalPhotoCount => existingPhotos.length + newPhotos.length;

  @override
  Widget build(BuildContext context) {
    final total = _totalPhotoCount;
    final countLabel = '$total/$kMaxPropertyPhotos';
    final hasAny = existingPhotos.isNotEmpty || newPhotos.isNotEmpty;

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
              onTap: onAddPhotoPressed,
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
        if (!hasAny && !isLoadingExistingPhotos) _buildEmptyState(),
        if (isLoadingExistingPhotos && !hasAny) _buildLoadingState(),
        if (existingPhotos.isNotEmpty) ...[
          _buildExistingPhotosList(),
          if (newPhotos.isNotEmpty) const SizedBox(height: 10),
        ],
        if (newPhotos.isNotEmpty) ...[
          _buildNewPhotosList(),
          const SizedBox(height: 8),
          _buildNewPhotosFooter(),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return DottedBorder(
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
            onTap: onAddPhotoPressed,
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
    );
  }

  Widget _buildLoadingState() {
    return Container(
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
    );
  }

  Widget _buildExistingPhotosList() {
    return SizedBox(
      height: 86,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorder: onReorderExistingPhotos,
        itemCount: existingPhotos.length,
        proxyDecorator: (child, _, __) {
          return Material(
            elevation: 6,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final img = existingPhotos[index];
          final url = absoluteMediaUrl(img.fileUrl);
          return Padding(
            key: ValueKey('existing:${img.id ?? img.fileUrl}'),
            padding: EdgeInsets.only(
                right: index == existingPhotos.length - 1 ? 0 : 10),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: _buildPhotoTile(
                imageWidget: url.isEmpty
                    ? const Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            color: Color(0xFF94A3B8)),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Color(0xFF94A3B8)),
                        ),
                      ),
                index: index,
                isPrimary: index == 0,
                onDelete: () => onDeleteExistingPhoto(index),
                deleteIcon: Icons.delete_outline,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewPhotosList() {
    return SizedBox(
      height: 86,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        onReorder: onReorderNewPhotos,
        itemCount: newPhotos.length,
        proxyDecorator: (child, _, __) {
          return Material(
            elevation: 6,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final selected = newPhotos[index];
          final photo = selected.file;
          return Padding(
            key: ValueKey('photo:${selected.id}'),
            padding:
                EdgeInsets.only(right: index == newPhotos.length - 1 ? 0 : 10),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: _buildPhotoTile(
                imageWidget: Image.file(
                  File(photo.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Color(0xFF94A3B8)),
                  ),
                ),
                index: index,
                isPrimary: existingPhotos.isEmpty && index == 0,
                onDelete: () => onRemoveNewPhoto(index),
                deleteIcon: Icons.close,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoTile({
    required Widget imageWidget,
    required int index,
    required bool isPrimary,
    required VoidCallback onDelete,
    required IconData deleteIcon,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            width: 112,
            height: 86,
            color: const Color(0xFFF1F5F9),
            child: imageWidget,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(deleteIcon, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                isPrimary ? 'Primary' : '${index + 1}',
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
    );
  }

  Widget _buildNewPhotosFooter() {
    return Row(
      children: [
        Text(
          '${newPhotos.length} new image${newPhotos.length == 1 ? '' : 's'} added',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onClearNewPhotos,
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
    );
  }
}
