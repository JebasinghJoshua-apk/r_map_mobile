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
    this.isSaved,
    this.isSaving = false,
    this.onToggleSaved,
    this.onOpenDetails,
    this.outerPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    required this.onClose,
  });

  final MapPropertyFeature feature;
  final List<String>? imageUrls;
  final bool isLoadingImages;
  final String? imagesError;
  final bool? isSaved;
  final bool isSaving;
  final VoidCallback? onToggleSaved;
  final VoidCallback? onOpenDetails;
  final EdgeInsetsGeometry outerPadding;
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
    final canOpenDetails = onOpenDetails != null;

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

    final imageBorderRadius = BorderRadius.circular(10);

    Widget imagePanelChild() {
      if (effectiveImageUrls.isNotEmpty) {
        return PropertyImageCarousel(urls: effectiveImageUrls);
      }

      if (isLoadingImages) {
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }

      if (imagesError != null) {
        return Center(
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
        );
      }

      return const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 22,
          color: Color(0xFF64748B),
        ),
      );
    }

    Widget infoLine(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackVertically = constraints.maxWidth < 220;

            final labelWidget = Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            );

            final valueWidget = Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            );

            if (stackVertically) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelWidget,
                  const SizedBox(height: 2),
                  valueWidget,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 76, child: labelWidget),
                const SizedBox(width: 8),
                Expanded(child: valueWidget),
              ],
            );
          },
        ),
      );
    }

    Widget iconLine(IconData icon, String value) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 16,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget imagePanel(double aspectRatio) {
      final canToggleSaved = onToggleSaved != null;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: imageBorderRadius,
        ),
        child: ClipRRect(
          borderRadius: imageBorderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              children: [
                Positioned.fill(child: imagePanelChild()),
                if (canToggleSaved)
                  Positioned(
                    top: 4,
                    right: 6,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: isSaving ? null : onToggleSaved,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : ((isSaved ?? false)
                                  ? const Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          Icons.favorite,
                                          size: 28,
                                          color: Colors.white54,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white54,
                                              blurRadius: 7,
                                            ),
                                          ],
                                        ),
                                        Icon(
                                          Icons.favorite,
                                          size: 24,
                                          color: Color(0xFFE11D48),
                                          shadows: [
                                            Shadow(
                                              color: Color(0x80000000),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          Icons.favorite,
                                          size: 24,
                                          color: const Color(0xFF0F172A)
                                              .withOpacity(0.18),
                                        ),
                                        const Icon(
                                          Icons.favorite_border,
                                          size: 23,
                                          color: Colors.white,
                                          shadows: [
                                            Shadow(
                                              color: Color(0x80000000),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ],
                                    )),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget detailsPanel() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: canOpenDetails ? onOpenDetails : null,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: canOpenDetails
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF0F172A),
                    ),
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
          if (price != null) iconLine(Icons.currency_rupee, price),
          if (location != null) iconLine(Icons.location_on_outlined, location),
          if (facing != null) infoLine('Facing', facing),
          if (canOpenDetails)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onOpenDetails,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF2563EB),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('View details →'),
                ),
              ),
            ),
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: outerPadding,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 16,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: canOpenDetails ? onOpenDetails : null,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // The panel itself is width-constrained; keep the left/right
                          // layout for typical phone widths and only stack on very
                          // small widths.
                          final isNarrow = constraints.maxWidth < 340;

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                            child: isNarrow
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Slightly taller than 16:9 to give the panel
                                      // more presence without adding extra padding.
                                      imagePanel(3 / 2),
                                      const SizedBox(height: 8),
                                      detailsPanel(),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Make the side thumbnail a bit taller.
                                      Expanded(child: imagePanel(5 / 4)),
                                      const SizedBox(width: 10),
                                      Expanded(child: detailsPanel()),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PropertyImageCarousel extends StatefulWidget {
  const PropertyImageCarousel({super.key, required this.urls});

  final List<String> urls;

  @override
  State<PropertyImageCarousel> createState() => _PropertyImageCarouselState();
}

class _PropertyImageCarouselState extends State<PropertyImageCarousel> {
  late final PageController _controller;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final hasMultiple = urls.length > 1;

    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _activeIndex = i),
            itemBuilder: (context, index) {
              final url = urls[index];
              return Image.network(
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
                        size: 22,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  final expected = progress.expectedTotalBytes;
                  final loaded = progress.cumulativeBytesLoaded;
                  final value = expected != null && expected > 0
                      ? loaded / expected
                      : null;
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: value,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (hasMultiple)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(urls.length, (i) {
                      final isActive = i == _activeIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isActive ? 1 : 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
