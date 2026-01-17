import 'package:flutter/material.dart';

import '../models/map_viewport_models.dart';
import '../widgets/property_details_panel.dart';

class PropertyDetailScreen extends StatelessWidget {
  const PropertyDetailScreen({
    super.key,
    required this.feature,
    this.imageUrls,
    this.isLoadingImages = false,
    this.imagesError,
  });

  final MapPropertyFeature feature;
  final List<String>? imageUrls;
  final bool isLoadingImages;
  final String? imagesError;

  String _trimOrEmpty(String? value) => (value ?? '').trim();

  String? _meta(List<String> keys) {
    for (final k in keys) {
      final v = feature.metadata[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = feature.name.trim().isEmpty
        ? (feature.propertyType.trim().isEmpty
            ? 'Property Details'
            : feature.propertyType.trim())
        : feature.name.trim();

    final price =
        _meta(const <String>['price', 'listingPrice', 'salePrice', 'amount']);
    final location =
        _meta(const <String>['location', 'locality', 'city', 'area']);
    final facing = _meta(const <String>['facing', 'direction', 'plotFacing']);

    final resolvedOverride = (imageUrls ?? const <String>[])
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .map(PropertyDetailsPanel.resolveMediaUrl)
        .toList(growable: false);

    final extracted = PropertyDetailsPanel.extractImageUrls(feature.metadata);
    final effectiveImageUrls =
        resolvedOverride.isNotEmpty ? resolvedOverride : extracted;

    final excludedMetaKeys = <String>{
      'primaryImageUrl',
      'heroImageUrl',
      'thumbnailUrl',
      'imageUrl',
      'photoUrl',
      'image',
      'photo',
      'images',
      'imageUrls',
      'photos',
      'gallery',
      'media',
      'price',
      'listingPrice',
      'salePrice',
      'amount',
      'location',
      'locality',
      'city',
      'area',
      'facing',
      'direction',
      'plotFacing',
    };

    final remaining = feature.metadata.entries
        .where((e) => e.key.trim().isNotEmpty)
        .where((e) => !excludedMetaKeys.contains(e.key.trim()))
        .map((e) => MapEntry(e.key.trim(), _trimOrEmpty(e.value)))
        .where((e) => e.value.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    Widget kv(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget imageSection() {
      if (effectiveImageUrls.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PropertyImageCarousel(urls: effectiveImageUrls),
          ),
        );
      }

      if (isLoadingImages) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      if (imagesError != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            imagesError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const SizedBox(
            height: 160,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 26,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imageSection(),
                const SizedBox(height: 14),
                Text(
                  feature.propertyType.trim().isEmpty
                      ? 'Property'
                      : feature.propertyType.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (price != null) kv('Price', price),
                if (location != null) kv('Location', location),
                if (facing != null) kv('Facing', facing),
                if (feature.listingType != null &&
                    feature.listingType!.trim().isNotEmpty)
                  kv('Listing', feature.listingType!.trim()),
                if (feature.propertyId.trim().isNotEmpty)
                  kv('Property ID', feature.propertyId.trim()),
                if (feature.featureId.trim().isNotEmpty)
                  kv('Feature ID', feature.featureId.trim()),
                if (remaining.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 24),
                  const Text(
                    'More details',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  for (final e in remaining) kv(e.key, e.value),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
