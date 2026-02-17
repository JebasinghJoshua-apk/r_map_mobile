import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/map_viewport_models.dart';
import '../services/analytics_service.dart';
import '../services/mobile_bff_map_api.dart';
import '../services/mobile_bff_saved_properties_api.dart';
import '../state/auth_scope.dart';
import '../utils/pending_property_selection.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/delimited_bullet_list.dart';
import '../widgets/property_details_panel.dart';
import '../widgets/share_property_sheet.dart';
import '../widgets/toast_message.dart';

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({
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

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  int _activeIndex = 0;
  final PageController _pageController = PageController();

  late final MobileBffSavedPropertiesApi _savedPropertiesApi;
  late final MobileBffMapApi _mapApi;
  bool _isSaved = false;
  bool _isSaving = false;
  String? _lastAuthKey;

  /// Local image state – initialized from widget props, then fetched if needed.
  List<String>? _imageUrls;
  bool _isLoadingImages = false;
  String? _imagesError;

  String get _propertyId => widget.feature.propertyId.trim();

  @override
  void initState() {
    super.initState();
    _savedPropertiesApi = MobileBffSavedPropertiesApi();
    _mapApi = MobileBffMapApi();

    // Initialize image state from widget props.
    _imageUrls = widget.imageUrls;
    _isLoadingImages = widget.isLoadingImages;
    _imagesError = widget.imagesError;

    // If no images provided and not already loading, fetch them.
    final hasImages = widget.imageUrls != null && widget.imageUrls!.isNotEmpty;
    if (!hasImages && !widget.isLoadingImages) {
      unawaited(_fetchImages());
    }

    AnalyticsService.instance.logScreenView('PropertyDetail');
    AnalyticsService.instance.logPropertyViewed(
      propertyId: widget.feature.propertyId,
      propertyType: widget.feature.propertyType,
      propertyName: widget.feature.name,
    );
  }

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

    if (authKey == _lastAuthKey) return;
    _lastAuthKey = authKey;

    // Refresh saved state when auth changes.
    if (authKey == null) {
      if (mounted) {
        setState(() {
          _isSaved = false;
          _isSaving = false;
        });
      }
      return;
    }

    // Best-effort background refresh.
    unawaited(_refreshSavedStateFromIds());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Fetch images from MobileBff if not already provided by parent.
  Future<void> _fetchImages() async {
    final propertyType = widget.feature.propertyType.trim();
    final entityId = widget.feature.featureId.trim();
    if (propertyType.isEmpty || entityId.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _isLoadingImages = true;
      _imagesError = null;
    });

    try {
      final token = AuthScope.of(context).session?.token;
      final images = await _mapApi.getPropertyMedia(
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
        _imageUrls = urls;
        _isLoadingImages = false;
        _imagesError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageUrls = const <String>[];
        _isLoadingImages = false;
        _imagesError = e.toString();
      });
    }
  }

  Future<void> _refreshSavedStateFromIds() async {
    final pid = _propertyId;
    if (pid.isEmpty) {
      if (mounted) setState(() => _isSaved = false);
      return;
    }

    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      if (mounted) setState(() => _isSaved = false);
      return;
    }

    try {
      final ids = await _savedPropertiesApi.getSavedPropertyIds(
        bearerToken: token,
      );
      if (!mounted) return;

      final normalizedPid = pid.toLowerCase();
      final set = ids
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      setState(() => _isSaved = set.contains(normalizedPid));
    } catch (_) {
      // Best-effort only; don't block details screen.
    }
  }

  Future<void> _toggleSaved() async {
    final pid = _propertyId;
    if (pid.isEmpty) {
      ToastMessage.show(context, 'This listing cannot be saved');
      return;
    }

    final token = AuthScope.of(context).session?.token;
    if (token == null || token.trim().isEmpty) {
      await AuthDialog.showLogin(context);
      return;
    }

    if (_isSaving) return;

    final wasSaved = _isSaved;
    setState(() {
      _isSaving = true;
      _isSaved = !wasSaved; // optimistic
    });

    try {
      if (wasSaved) {
        await _savedPropertiesApi.unsaveProperty(
          propertyId: pid,
          bearerToken: token,
        );
      } else {
        await _savedPropertiesApi.saveProperty(
          propertyId: pid,
          bearerToken: token,
        );
      }
    } on SavedPropertiesApiException catch (ex) {
      if (!mounted) return;
      setState(() => _isSaved = wasSaved);
      ToastMessage.show(context, ex.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaved = wasSaved);
      ToastMessage.show(context, 'Failed to update shortlist');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _circleIconButton({
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

  Widget _favoriteButton() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _isSaving ? null : _toggleSaved,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.50),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Icon(
                    _isSaved ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: _isSaved ? const Color(0xFFE11D48) : Colors.white,
                  ),
          ),
        ),
      ),
    );
  }

  String _trimOrEmpty(String? value) => (value ?? '').trim();

  String _formatListingType(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.toLowerCase() == 'sell') return 'Sale';
    return trimmed;
  }

  /// Convert "INR 45,00,000" → "₹45,00,000"
  String? _formatPrice(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceFirst(RegExp(r'^INR\s*', caseSensitive: false), '₹');
  }

  String? _meta(Map<String, String?> metadata, List<String> keys) {
    for (final k in keys) {
      final v = metadata[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final metadata = feature.metadata;

    final title = feature.name.trim().isEmpty
        ? (feature.propertyType.trim().isEmpty
            ? 'Property Details'
            : feature.propertyType.trim())
        : feature.name.trim();

    final propertyTypeLabel = feature.propertyType.trim().isEmpty
        ? 'Property'
        : feature.propertyType.trim();

    final price = _formatPrice(_meta(
      metadata,
      const <String>['price', 'listingPrice', 'salePrice', 'amount'],
    ));
    final location = _meta(
      metadata,
      const <String>['location', 'locality', 'city', 'area'],
    );
    final facing = _meta(
      metadata,
      const <String>['facing', 'direction', 'plotFacing'],
    );
    final additionalInfo = _meta(
      metadata,
      const <String>[
        'additionalDetails',
        'additionalInfo',
        'description',
        'notes',
        'details',
      ],
    );

    final listingType = _formatListingType(feature.listingType);
    final plotsCount = _meta(
      metadata,
      const <String>['plotsCount', 'plotCount', 'numberOfPlots', 'plots'],
    );
    final contactName = _meta(
      metadata,
      const <String>['contactName'],
    );
    final phoneNumber = _meta(
      metadata,
      const <String>['contactNumbers'],
    );

    final resolvedOverride = (_imageUrls ?? const <String>[])
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .map(PropertyDetailsPanel.resolveMediaUrl)
        .toList(growable: false);

    final extracted = PropertyDetailsPanel.extractImageUrls(metadata);
    final effectiveImageUrls =
        resolvedOverride.isNotEmpty ? resolvedOverride : extracted;

    final images = effectiveImageUrls
        .where((u) => u.trim().isNotEmpty)
        .map((u) => _HeroImage(url: u.trim(), alt: title))
        .toList(growable: false);

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
      'additionalDetails',
      'additionalInfo',
      'description',
      'notes',
      'details',
      'plotsCount',
      'plotCount',
      'numberOfPlots',
      'plots',
    };

    final remaining = metadata.entries
        .where((e) => e.key.trim().isNotEmpty)
        .where((e) => !excludedMetaKeys.contains(e.key.trim()))
        .map((e) => MapEntry(e.key.trim(), _trimOrEmpty(e.value)))
        .where((e) => e.value.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    String labelOrDash(String? value) =>
        (value ?? '').trim().isEmpty ? '—' : (value ?? '').trim();

    final canCopyLink = feature.propertyType.trim().isNotEmpty &&
        feature.featureId.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop && widget.fromDeepLink) {
            // Schedule pending selection so HomeMapScreen can show the property
            // in its bottom panel when it becomes visible again.
            PendingPropertySelection.set(widget.feature);
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Builder(
            builder: (context) {
              final bottomInset = MediaQuery.of(context).padding.bottom;
              final topInset = MediaQuery.of(context).padding.top;
              return ListView(
                padding:
                    EdgeInsets.only(top: topInset, bottom: 24 + bottomInset),
                children: [
                  Stack(
                    children: [
                      _HeroCarousel(
                        aspectRatio: 1.3,
                        images: images,
                        loading: _isLoadingImages,
                        error: _imagesError,
                        onIndexChanged: (idx) =>
                            setState(() => _activeIndex = idx),
                        controller: _pageController,
                        activeIndex: _activeIndex,
                      ),
                      // Overlay icons on top of the image
                      Positioned(
                        top: 16,
                        left: 12,
                        child: _circleIconButton(
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
                              _circleIconButton(
                                icon: Icons.share_outlined,
                                onTap: () {
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
                                      listingType: listingType.isNotEmpty
                                          ? listingType
                                          : null,
                                      heroImageUrl: heroUrl,
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(width: 8),
                            _favoriteButton(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (location != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'PRICE',
                                    value: labelOrDash(price),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'LISTING',
                                    value: labelOrDash(listingType),
                                  ),
                                ),
                              ],
                            ),
                            if (additionalInfo != null) ...[
                              const SizedBox(height: 14),
                              _SectionCard(
                                title: 'ADDITIONAL INFO',
                                child: DelimitedBulletList(
                                  text: additionalInfo,
                                  delimiter: '~~',
                                  textStyle: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _SectionCard(
                              title: 'PROPERTY OVERVIEW',
                              child: Column(
                                children: [
                                  _KeyValueRow(
                                    label: 'Type',
                                    value: labelOrDash(propertyTypeLabel),
                                  ),
                                  if (plotsCount != null) ...[
                                    const SizedBox(height: 10),
                                    _KeyValueRow(
                                      label: 'Plots',
                                      value: plotsCount,
                                    ),
                                  ],
                                  if (location != null) ...[
                                    const SizedBox(height: 10),
                                    _KeyValueRow(
                                      label: 'Location',
                                      value: location,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (contactName != null || phoneNumber != null) ...[
                              const SizedBox(height: 14),
                              _SectionCard(
                                title: 'CONTACT DETAILS',
                                child: Column(
                                  children: [
                                    if (contactName != null)
                                      _KeyValueRow(
                                        label: 'Name',
                                        value: contactName,
                                      ),
                                    if (contactName != null &&
                                        phoneNumber != null)
                                      const SizedBox(height: 10),
                                    if (phoneNumber != null)
                                      _KeyValueRow(
                                        label: 'Phone',
                                        value: phoneNumber,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroImage {
  const _HeroImage({required this.url, required this.alt});

  final String url;
  final String alt;
}

class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({
    required this.aspectRatio,
    required this.images,
    required this.loading,
    required this.error,
    required this.onIndexChanged,
    required this.controller,
    required this.activeIndex,
  });

  final double aspectRatio;
  final List<_HeroImage> images;
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
                                    builder: (_) => _FullScreenImageGallery(
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

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

class _FullScreenImageGallery extends StatefulWidget {
  const _FullScreenImageGallery({
    required this.images,
    required this.initialIndex,
  });

  final List<_HeroImage> images;
  final int initialIndex;

  @override
  State<_FullScreenImageGallery> createState() =>
      _FullScreenImageGalleryState();
}

class _FullScreenImageGalleryState extends State<_FullScreenImageGallery> {
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
                  child: _RoundIconButton(
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
                  child: _RoundIconButton(
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

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

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

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
