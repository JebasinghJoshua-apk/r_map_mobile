import 'dart:convert';

import 'package:flutter/material.dart';

import '../constants/api_constants.dart';
import '../models/map_viewport_models.dart';

class PropertyDetailsPanel extends StatelessWidget {
  const PropertyDetailsPanel({
    super.key,
    required this.feature,
    this.imageUrls,
    this.isLoadingImages = false,
    this.imagesError,
    required this.onClose,
  });

  final MapPropertyFeature feature;
  final List<String>? imageUrls;
  final bool isLoadingImages;
  final String? imagesError;
  final VoidCallback onClose;

  static String resolveMediaUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;

    final uploadsBase = ApiConstants.effectiveUploadsBaseUrl;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      final parsed = Uri.tryParse(url);
      if (parsed == null) return url;

      final host = parsed.host.toLowerCase();
      final isDevHost =
          host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
      if (!isDevHost) return url;

      final baseUri = Uri.tryParse(uploadsBase);
      if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
        return url;
      }

      final rewritten = Uri(
        scheme: baseUri.scheme,
        userInfo: baseUri.userInfo,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        path: parsed.path,
        query: parsed.query,
      );
      return rewritten.toString();
    }

    final base = uploadsBase.endsWith('/')
        ? uploadsBase.substring(0, uploadsBase.length - 1)
        : uploadsBase;

    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  static List<String> extractImageUrls(Map<String, String?> metadata) {
    final candidates = <String?>[
      metadata['primaryImageUrl'],
      metadata['heroImageUrl'],
      metadata['thumbnailUrl'],
      metadata['imageUrl'],
      metadata['photoUrl'],
      metadata['image'],
      metadata['photo'],
      metadata['images'],
      metadata['imageUrls'],
      metadata['photos'],
      metadata['gallery'],
      metadata['media'],
    ]
        .map((v) => v?.trim())
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>();

    final urls = <String>[];

    void addUrl(String u) {
      final t = u.trim();
      if (t.isEmpty) return;
      final resolved = resolveMediaUrl(t);
      if (!urls.contains(resolved)) {
        urls.add(resolved);
      }
    }

    for (final raw in candidates) {
      // JSON array of strings or objects (common shapes).
      if ((raw.startsWith('[') && raw.endsWith(']')) ||
          (raw.startsWith('{') && raw.endsWith('}'))) {
        try {
          final decoded = json.decode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is String) {
                addUrl(item);
              } else if (item is Map) {
                final fileUrl = item['fileUrl'] ?? item['url'] ?? item['src'];
                if (fileUrl != null) addUrl(fileUrl.toString());
              }
            }
            continue;
          }
          if (decoded is Map) {
            final fileUrl =
                decoded['fileUrl'] ?? decoded['url'] ?? decoded['src'];
            if (fileUrl != null) {
              addUrl(fileUrl.toString());
              continue;
            }
          }
        } catch (_) {
          // Fallthrough to splitting heuristics.
        }
      }

      // Comma/newline separated.
      for (final part in raw.split(RegExp(r'[\n,;|]+'))) {
        final p = part.trim();
        if (p.isEmpty) continue;
        addUrl(p);
      }
    }

    return urls;
  }

  String? _meta(List<String> keys) {
    for (final k in keys) {
      final v = feature.metadata[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title =
        feature.name.trim().isEmpty ? 'Independent House' : feature.name;

    final price =
        _meta(const <String>['price', 'listingPrice', 'salePrice', 'amount']);
    final location =
        _meta(const <String>['location', 'locality', 'city', 'area']);
    final facing = _meta(const <String>['facing', 'direction', 'plotFacing']);

    final resolvedOverride = (imageUrls ?? const <String>[])
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .map(resolveMediaUrl)
        .toList(growable: false);

    final extracted = extractImageUrls(feature.metadata);
    final effectiveImageUrls =
        resolvedOverride.isNotEmpty ? resolvedOverride : extracted;

    Widget infoLine(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
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

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (effectiveImageUrls.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      effectiveImageUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) {
                        return const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFE2E8F0),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 22,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        );
                      },
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFF1F5F9),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (effectiveImageUrls.isEmpty && isLoadingImages)
                const ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFF1F5F9),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              if (effectiveImageUrls.isEmpty &&
                  !isLoadingImages &&
                  imagesError != null)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            imagesError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: onClose,
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    if (effectiveImageUrls.length > 1) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 58,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: effectiveImageUrls.length > 6
                              ? 6
                              : effectiveImageUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final url = effectiveImageUrls[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, _, __) {
                                    return const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    );
                                  },
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFFF1F5F9),
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (price != null) infoLine('Price', price),
                    if (location != null) infoLine('Location', location),
                    if (facing != null) infoLine('Facing', facing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
