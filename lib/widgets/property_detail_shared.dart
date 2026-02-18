import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/map_viewport_models.dart';
import '../services/analytics_service.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_saved_properties_api.dart';
import '../state/auth_scope.dart';
import '../utils/pending_property_selection.dart';
import 'auth_dialog.dart';
import 'property_details_panel.dart';
import 'share_property_sheet.dart';
import 'toast_message.dart';

/// Data class for hero carousel images.
class HeroImage {
  const HeroImage({required this.url, required this.alt});

  final String url;
  final String alt;
}

/// Mixin providing common helper methods for property detail screens.
mixin PropertyDetailHelpers<T extends StatefulWidget> on State<T> {
  String trimOrEmpty(String? value) => (value ?? '').trim();

  String formatListingType(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.toLowerCase() == 'sell') return 'Sale';
    return trimmed;
  }

  /// Convert "INR 45,00,000" → "₹45,00,000"
  String? formatPrice(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceFirst(RegExp(r'^INR\s*', caseSensitive: false), '₹');
  }

  String? meta(Map<String, String?> metadata, List<String> keys) {
    for (final k in keys) {
      final v = metadata[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String labelOrDash(String? value) =>
      (value ?? '').trim().isEmpty ? '—' : (value ?? '').trim();
}

/// Base class for property detail screens with shared state management.
abstract class BasePropertyDetailScreen extends StatefulWidget {
  const BasePropertyDetailScreen({
    super.key,
    required this.feature,
    this.imageUrls,
    this.isLoadingImages = false,
    this.imagesError,
    this.fromDeepLink = false,
  });

  final MapPropertyFeature feature;
  final List<String>? imageUrls;
  final bool isLoadingImages;
  final String? imagesError;

  /// When true, popping this screen will set a pending property selection
  /// so HomeMapScreen can select the property and show the bottom panel.
  final bool fromDeepLink;
}

/// Common state class for property detail screens.
abstract class BasePropertyDetailScreenState<T extends BasePropertyDetailScreen>
    extends State<T> with PropertyDetailHelpers {
  int activeIndex = 0;
  final PageController pageController = PageController();

  late final MobileBffSavedPropertiesApi savedPropertiesApi;
  late final MobileBffMapApi mapApi;
  bool isSaved = false;
  bool isSaving = false;
  String? lastAuthKey;

  /// Local image state – initialized from widget props, then fetched if needed.
  List<String>? imageUrls;
  bool isLoadingImages = false;
  String? imagesError;

  String get propertyId => widget.feature.propertyId.trim();

  @override
  void initState() {
    super.initState();
    savedPropertiesApi = MobileBffSavedPropertiesApi();
    mapApi = MobileBffMapApi();

    // Initialize image state from widget props.
    imageUrls = widget.imageUrls;
    isLoadingImages = widget.isLoadingImages;
    imagesError = widget.imagesError;

    // If no images provided and not already loading, fetch them.
    final hasImages = widget.imageUrls != null && widget.imageUrls!.isNotEmpty;
    if (!hasImages && !widget.isLoadingImages) {
      unawaited(fetchImages());
    }

    logAnalytics();
  }

  void logAnalytics() {
    AnalyticsService.instance.logScreenView(screenName);
    AnalyticsService.instance.logPropertyViewed(
      propertyId: widget.feature.propertyId,
      propertyType: widget.feature.propertyType,
      propertyName: widget.feature.name,
    );
  }

  String get screenName => 'PropertyDetail';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final session = AuthScope.of(context).session;
    final token = session?.token.trim();
    final userId = session?.user.id.trim();

    final authKey = (token != null &&
            token.isNotEmpty &&
            userId != null &&
            userId.isNotEmpty)
        ? '$userId:$token'
        : null;

    if (authKey == lastAuthKey) return;
    lastAuthKey = authKey;

    if (authKey != null) {
      unawaited(_checkSaved(token!));
    } else {
      if (mounted) setState(() => isSaved = false);
    }
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  Future<void> _checkSaved(String bearerToken) async {
    final pid = propertyId;
    if (pid.isEmpty) return;

    try {
      final savedIds = await savedPropertiesApi.getSavedPropertyIds(
        bearerToken: bearerToken,
      );
      if (!mounted) return;
      setState(() => isSaved = savedIds.contains(pid));
    } catch (_) {
      // Silently ignore – non-critical
    }
  }

  Future<void> fetchImages() async {
    final propertyType = widget.feature.propertyType.trim();
    final entityId = widget.feature.featureId.trim();

    if (propertyType.isEmpty || entityId.isEmpty) return;

    if (mounted) setState(() => isLoadingImages = true);

    try {
      final token = AuthScope.of(context).session?.token;
      final images = await mapApi.getPropertyMedia(
        propertyType: propertyType,
        entityId: entityId,
        bearerToken: token,
      );
      if (!mounted) return;

      final urls = <String>[];
      for (final img in images) {
        final u = img.fileUrl.trim();
        if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
      }

      setState(() {
        imageUrls = urls;
        imagesError = null;
        isLoadingImages = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        imagesError = e.toString();
        isLoadingImages = false;
      });
    }
  }

  Future<void> toggleSaved() async {
    final pid = propertyId;
    if (pid.isEmpty) {
      ToastMessage.show(context, 'Unable to save this property');
      return;
    }

    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      await AuthDialog.showLogin(context);
      return;
    }

    if (isSaving) return;

    final wasSaved = isSaved;
    setState(() {
      isSaving = true;
      isSaved = !wasSaved; // optimistic
    });

    try {
      if (wasSaved) {
        await savedPropertiesApi.unsaveProperty(
          propertyId: pid,
          bearerToken: token,
        );
      } else {
        await savedPropertiesApi.saveProperty(
          propertyId: pid,
          bearerToken: token,
        );
      }
    } on SavedPropertiesApiException catch (ex) {
      if (!mounted) return;
      setState(() => isSaved = wasSaved);
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => isSaved = wasSaved);
      ToastMessage.show(context, 'Failed to update shortlist');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  /// Builds a circular icon button.
  Widget circleIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.50),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget favoriteButton() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isSaving ? null : toggleSaved,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.50),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: isSaved ? const Color(0xFFE11D48) : Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  /// Returns common metadata values.
  Map<String, String?> extractCommonMeta(Map<String, String?> metadata) {
    return {
      'price': formatPrice(
          meta(metadata, ['price', 'listingPrice', 'salePrice', 'amount'])),
      'location': meta(metadata, ['location', 'locality', 'city']),
      'area': meta(metadata,
          ['area', 'areaLabel', 'areaSqFt', 'totalArea', 'builtUpSqFt']),
      'facing': meta(metadata, ['facing', 'direction', 'plotFacing']),
      'additionalInfo': meta(metadata, [
        'additionalInformation',
        'additionalDetails',
        'additionalInfo',
        'description',
        'notes',
        'details',
      ]),
      'plotsCount':
          meta(metadata, ['plotsCount', 'plotCount', 'numberOfPlots', 'plots']),
      'plotNumbers': meta(metadata, ['plotNumbers']),
      'contactName': meta(metadata, ['contactName']),
      'phoneNumber': meta(metadata, ['contactNumbers']),
    };
  }

  /// Format area with sq ft suffix if not already present.
  String? formatAreaDisplay(String? areaLabel) {
    if (areaLabel == null) return null;
    return RegExp(r'sq\s*\.?\s*ft|sqft', caseSensitive: false)
            .hasMatch(areaLabel)
        ? areaLabel
        : '$areaLabel sq ft';
  }

  /// Build common scaffold wrapper.
  Widget buildScaffold({required Widget body}) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop && widget.fromDeepLink) {
            PendingPropertySelection.set(widget.feature);
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: body,
        ),
      ),
    );
  }

  /// Build hero header with carousel and overlay buttons.
  Widget buildHeroHeader({
    required List<HeroImage> images,
    required String title,
    required String? location,
    required String? price,
    required String listingType,
  }) {
    final feature = widget.feature;
    final canCopyLink = feature.propertyType.trim().isNotEmpty &&
        feature.featureId.trim().isNotEmpty;

    return Stack(
      children: [
        HeroCarousel(
          aspectRatio: 1.3,
          images: images,
          loading: isLoadingImages,
          error: imagesError,
          onIndexChanged: (idx) => setState(() => activeIndex = idx),
          controller: pageController,
          activeIndex: activeIndex,
        ),
        // Overlay icons on top of the image
        Positioned(
          top: 16,
          left: 12,
          child: circleIconButton(
            icon: Icons.arrow_back,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          top: 16,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canCopyLink)
                circleIconButton(
                  icon: Icons.share_outlined,
                  onTap: () {
                    final effectiveImageUrls = resolveEffectiveImageUrls();
                    final heroUrl = effectiveImageUrls.isNotEmpty
                        ? effectiveImageUrls.first
                        : null;
                    showSharePropertySheet(
                      context,
                      SharePropertyInfo(
                        title: title,
                        propertyType: feature.propertyType.trim(),
                        featureId: feature.featureId.trim(),
                        location: location,
                        priceLabel: price,
                        listingType:
                            listingType.isNotEmpty ? listingType : null,
                        heroImageUrl: heroUrl,
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),
              favoriteButton(),
            ],
          ),
        ),
      ],
    );
  }

  List<String> resolveEffectiveImageUrls() {
    final metadata = widget.feature.metadata;
    final resolvedOverride = (imageUrls ?? const <String>[])
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .map(PropertyDetailsPanel.resolveMediaUrl)
        .toList(growable: false);
    final extracted = PropertyDetailsPanel.extractImageUrls(metadata);
    return resolvedOverride.isNotEmpty ? resolvedOverride : extracted;
  }

  List<HeroImage> buildHeroImages(String title) {
    final effectiveImageUrls = resolveEffectiveImageUrls();
    return effectiveImageUrls
        .where((u) => u.trim().isNotEmpty)
        .map((u) => HeroImage(url: u.trim(), alt: title))
        .toList(growable: false);
  }
}

/// Hero image carousel widget.
class HeroCarousel extends StatelessWidget {
  const HeroCarousel({
    super.key,
    required this.aspectRatio,
    required this.images,
    required this.loading,
    required this.error,
    required this.onIndexChanged,
    required this.controller,
    required this.activeIndex,
  });

  final double aspectRatio;
  final List<HeroImage> images;
  final bool loading;
  final String? error;
  final ValueChanged<int> onIndexChanged;
  final PageController controller;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final hasImages = images.isNotEmpty;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
              ),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (!hasImages
                      ? Center(
                          child: Text(
                            error != null
                                ? 'Unable to load images'
                                : 'No images',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: controller,
                          itemCount: images.length,
                          onPageChanged: onIndexChanged,
                          itemBuilder: (context, index) {
                            final img = images[index];
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FullScreenImageGallery(
                                      images: images,
                                      initialIndex: index,
                                    ),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: 'property_image_${img.url}',
                                child: Image.network(
                                  img.url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    final expected =
                                        progress.expectedTotalBytes;
                                    final loaded =
                                        progress.cumulativeBytesLoaded;
                                    final value =
                                        expected != null && expected > 0
                                            ? loaded / expected
                                            : null;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: value,
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Color(0xFF94A3B8),
                                        size: 36,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        )),
            ),
          ),
          if (hasImages && images.length > 1) ...[
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      images.length,
                      (index) => Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == activeIndex
                              ? Colors.white
                              : Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full screen image gallery with pinch-to-zoom.
class FullScreenImageGallery extends StatefulWidget {
  const FullScreenImageGallery({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  final List<HeroImage> images;
  final int initialIndex;

  @override
  State<FullScreenImageGallery> createState() => _FullScreenImageGalleryState();
}

class _FullScreenImageGalleryState extends State<FullScreenImageGallery> {
  late final PageController _controller;
  late int _activeIndex;

  @override
  void initState() {
    super.initState();
    final safeInitial = widget.initialIndex.clamp(0, widget.images.length - 1);
    _activeIndex = safeInitial;
    _controller = PageController(initialPage: safeInitial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (idx) => setState(() => _activeIndex = idx),
                itemBuilder: (context, index) {
                  final img = widget.images[index];
                  return Center(
                    child: Hero(
                      tag: 'property_image_${img.url}',
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Image.network(
                          img.url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            final expected = progress.expectedTotalBytes;
                            final loaded = progress.cumulativeBytesLoaded;
                            final value = expected != null && expected > 0
                                ? loaded / expected
                                : null;
                            return Center(
                              child: CircularProgressIndicator(
                                value: value,
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 48,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (total > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: RoundIconButton(
                    icon: Icons.chevron_left,
                    onPressed: () {
                      final prev = (total + _activeIndex - 1) % total;
                      _controller.animateToPage(
                        prev,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: RoundIconButton(
                    icon: Icons.chevron_right,
                    onPressed: () {
                      final next = (_activeIndex + 1) % total;
                      _controller.animateToPage(
                        next,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      total,
                      (index) => Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _activeIndex
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Spacer(),
                    if (total > 1)
                      Text(
                        '${_activeIndex + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round icon button used in galleries.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(
      {super.key, required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.50),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// Stat card showing label and value.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section card with title and child widget.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Key-value row for property details.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
