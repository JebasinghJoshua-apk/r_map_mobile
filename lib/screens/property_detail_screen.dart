import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/map_viewport_models.dart';
import '../services/mobile_bff_saved_properties_api.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_dialog.dart';
import '../widgets/property_details_panel.dart';
import '../widgets/toast_message.dart';

class PropertyDetailScreen extends StatefulWidget {
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

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  int _activeIndex = 0;
  final PageController _pageController = PageController();

  late final MobileBffSavedPropertiesApi _savedPropertiesApi;
  bool _isSaved = false;
  bool _isSaving = false;
  String? _lastAuthKey;

  String get _propertyId => widget.feature.propertyId.trim();

  @override
  void initState() {
    super.initState();
    _savedPropertiesApi = MobileBffSavedPropertiesApi();
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

  Widget _favoriteButton() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _isSaving ? null : _toggleSaved,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : (_isSaved
                  ? const Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.favorite,
                          size: 36,
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
                          size: 32,
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
                          size: 32,
                          color: const Color(0xFF0F172A).withOpacity(0.18),
                        ),
                        const Icon(
                          Icons.favorite_border,
                          size: 31,
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
    );
  }

  String _trimOrEmpty(String? value) => (value ?? '').trim();

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

    final price = _meta(
      metadata,
      const <String>['price', 'listingPrice', 'salePrice', 'amount'],
    );
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

    final listingType = _trimOrEmpty(feature.listingType);

    final resolvedOverride = (widget.imageUrls ?? const <String>[])
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (canCopyLink)
            IconButton(
              tooltip: 'Copy link',
              onPressed: () async {
                final link =
                    '/property/${feature.propertyType.trim()}/${feature.featureId.trim()}';
                await Clipboard.setData(ClipboardData(text: link));
                if (!context.mounted) return;
                ToastMessage.show(context, 'Copied link');
              },
              icon: const Icon(Icons.share_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Stack(
            children: [
              _HeroCarousel(
                height: 360,
                images: images,
                loading: widget.isLoadingImages,
                error: widget.imagesError,
                onIndexChanged: (idx) => setState(() => _activeIndex = idx),
                controller: _pageController,
                activeIndex: _activeIndex,
              ),
              Positioned(
                top: 14,
                right: 6,
                child: _favoriteButton(),
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
                        child: Text(
                          additionalInfo,
                          style: const TextStyle(
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
                          const SizedBox(height: 10),
                          _KeyValueRow(
                            label: 'Price',
                            value: labelOrDash(price),
                          ),
                          const SizedBox(height: 10),
                          _KeyValueRow(
                            label: 'Facing',
                            value: labelOrDash(facing),
                          ),
                          if (location != null) ...[
                            const SizedBox(height: 10),
                            _KeyValueRow(
                              label: 'Location',
                              value: location,
                            ),
                          ],
                          if (listingType.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _KeyValueRow(
                              label: 'Listing',
                              value: listingType,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (remaining.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'MORE DETAILS',
                        child: Column(
                          children: [
                            for (var i = 0; i < remaining.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _KeyValueRow(
                                label: remaining[i].key,
                                value: remaining[i].value,
                              ),
                            ],
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
    required this.height,
    required this.images,
    required this.loading,
    required this.error,
    required this.onIndexChanged,
    required this.controller,
    required this.activeIndex,
  });

  final double height;
  final List<_HeroImage> images;
  final bool loading;
  final String? error;
  final ValueChanged<int> onIndexChanged;
  final PageController controller;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final hasImages = images.isNotEmpty;

    return SizedBox(
      height: height,
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
                                child: InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 3,
                                  child: Image.network(
                                    img.url,
                                    fit: BoxFit.contain,
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
                              ),
                            );
                          },
                        )),
            ),
          ),
          if (hasImages && images.length > 1) ...[
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundIconButton(
                  icon: Icons.chevron_left,
                  onPressed: () {
                    final prev =
                        (activeIndex - 1 + images.length) % images.length;
                    controller.animateToPage(
                      prev,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundIconButton(
                  icon: Icons.chevron_right,
                  onPressed: () {
                    final next = (activeIndex + 1) % images.length;
                    controller.animateToPage(
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
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == activeIndex
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFCBD5E1),
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
      color: Colors.white.withOpacity(0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF0F172A)),
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
                left: 12,
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
                right: 12,
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
        color: const Color(0xFFF1F5F9),
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
