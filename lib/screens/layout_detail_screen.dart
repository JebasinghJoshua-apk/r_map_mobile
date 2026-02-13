import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import '../models/map_viewport_models.dart';
import '../services/analytics_service.dart';
import '../services/mobile_bff_layouts_api.dart';
import '../state/auth_scope.dart';
import '../utils/pending_layout_focus.dart';
import '../widgets/delimited_bullet_list.dart';
import '../widgets/share_property_sheet.dart';
import '../widgets/toast_message.dart';

class LayoutDetailScreen extends StatefulWidget {
  const LayoutDetailScreen({
    super.key,
    required this.layoutId,
    this.fallbackFeature,
    this.fromDeepLink = false,
  });

  final String layoutId;
  final MapPropertyFeature? fallbackFeature;

  /// If true, popping this screen schedules a [PendingLayoutFocus] so the home
  /// map can focus on this layout.
  final bool fromDeepLink;

  @override
  State<LayoutDetailScreen> createState() => _LayoutDetailScreenState();
}

class _LayoutDetailScreenState extends State<LayoutDetailScreen> {
  late final MobileBffLayoutsApi _api;

  LayoutDetailDto? _detail;
  String? _error;
  bool _loading = false;

  bool _hasTriggeredInitialLoad = false;
  String? _lastSeenToken;

  int _activeIndex = 0;
  final PageController _pageController = PageController();

  String? _extractPrimaryPhoneNumber(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == '—' ||
        trimmed == '-') {
      return null;
    }

    // Pick the first phone-like token. Contact strings sometimes contain
    // multiple numbers or labels.
    final match = RegExp(r'\+?\d[\d\s\-()]{6,}').firstMatch(trimmed)?.group(0);
    final candidate = (match ?? trimmed).trim();
    if (candidate.isEmpty) return null;

    // Keep leading +, strip everything else to digits.
    final normalized = candidate
        .replaceAll(RegExp(r'(?!^)\+'), '')
        .replaceAll(RegExp(r'[^\d+]'), '');

    // Require at least 7 digits to avoid launching on junk.
    final digits = normalized.replaceAll('+', '');
    if (digits.length < 7) return null;

    return normalized;
  }

  Future<void> _callPhoneNumber(String? raw) async {
    final number = _extractPrimaryPhoneNumber(raw);
    if (number == null) {
      if (!mounted) return;
      ToastMessage.show(context, 'No valid phone number');
      return;
    }

    final uri = Uri(scheme: 'tel', path: number);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ToastMessage.show(context, 'Unable to open dialer');
    }
  }

  List<String> _splitContactNumbers(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == '—' ||
        trimmed == '-') {
      return const <String>[];
    }

    // Common separators we see in free-form contact strings.
    final parts = trimmed.split(RegExp(r'[,;/\n]'));
    final cleaned = parts.map((p) => p.trim()).where((p) => p.isNotEmpty);

    // De-dupe while preserving order.
    final seen = <String>{};
    final result = <String>[];
    for (final item in cleaned) {
      if (seen.add(item)) result.add(item);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _api = MobileBffLayoutsApi();
    AnalyticsService.instance.logScreenView('LayoutDetail');
    AnalyticsService.instance.logLayoutViewed(layoutId: widget.layoutId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // AuthState.initialize() is async; on cold start the token may not be
    // available yet during initState. Trigger the first load here instead.
    if (!_hasTriggeredInitialLoad) {
      _hasTriggeredInitialLoad = true;
      _load();
      return;
    }

    // If the token becomes available later (e.g. after async init or login),
    // retry loading details/images.
    final token = AuthScope.of(context).session?.token;
    final normalized = token?.trim();
    final hasToken = normalized != null && normalized.isNotEmpty;

    if (hasToken && normalized != _lastSeenToken) {
      _lastSeenToken = normalized;

      if (_detail == null && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _load();
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = AuthScope.of(context).session?.token;

    _lastSeenToken = token?.trim();

    setState(() {
      _loading = true;
      _error = null;
      _detail = null;
      _activeIndex = 0;
    });

    try {
      final detail = await _api.getLayoutDetail(
        layoutId: widget.layoutId,
        bearerToken: token,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _trimOrEmpty(String? value) => (value ?? '').trim();

  String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final t = _trimOrEmpty(c);
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  String? _meta(MapPropertyFeature? feature, List<String> keys) {
    final meta = feature?.metadata;
    if (meta == null) return null;
    for (final k in keys) {
      final v = meta[k];
      if (v != null && v.trim().isNotEmpty) {
        return v.trim();
      }
    }
    return null;
  }

  String resolveMediaUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;

    final uploadsBase = ApiConstants.effectiveUploadsBaseUrl;

    // If the backend returns absolute URLs like http://localhost:5132/uploads/...
    // that will break on physical devices (localhost == the phone). Rewrite
    // common dev-hosts to the configured uploads base.
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

      // Keep path/query from upstream URL, but point at uploadsBase.
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

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallbackFeature;

    final title = _firstNonEmpty([
          _detail?.name,
          fallback?.name,
        ]) ??
        'Layout';

    final location = _firstNonEmpty([
      _detail?.locationDetails,
      _meta(fallback, const ['location', 'locality', 'city', 'area']),
    ]);

    final plotsCountLabel = _detail?.plotsCount != null
        ? _detail!.plotsCount!.toString()
        : _meta(fallback, const ['plotsCount', 'totalPlots', 'plots']);

    final areaLabel = _firstNonEmpty([
      _detail?.area,
      _meta(fallback, const ['area', 'totalArea', 'areaLabel']),
    ]);

    final surveyNumber = _firstNonEmpty([
      _detail?.surveyNumber,
      _meta(fallback, const ['surveyNumber', 'surveyNo', 'survey']),
    ]);

    final approvalNumber = _firstNonEmpty([
      _detail?.approvalNumber,
      _meta(fallback, const ['approvalNumber', 'approvalNo', 'approval']),
    ]);

    final additionalInfo = _firstNonEmpty([
      _detail?.additionalDetails,
      _meta(fallback, const ['additionalDetails', 'otherInformation']),
    ]);

    final contactNumbers = _firstNonEmpty([
      _detail?.contactNumbers,
      _meta(fallback, const ['contactNumbers', 'contact', 'phone']),
    ]);

    final images = (_detail?.images ?? const <LayoutImageDto>[])
        .where((img) => img.fileUrl.trim().isNotEmpty)
        .toList(growable: false);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.fromDeepLink) {
          // Schedule pending focus so HomeMapScreen can focus this layout
          // when it becomes visible again.
          PendingLayoutFocus.set(widget.layoutId);
        }
      },
      child: Scaffold(
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
            IconButton(
              tooltip: 'Share',
              onPressed: () {
                final heroUrl = images.isNotEmpty
                    ? resolveMediaUrl(images.first.fileUrl)
                    : null;
                showSharePropertySheet(
                  context,
                  SharePropertyInfo(
                    title: title,
                    propertyType: 'Layout',
                    featureId: widget.layoutId,
                    location: location,
                    priceLabel: null,
                    listingType: null,
                    heroImageUrl: heroUrl,
                  ),
                );
              },
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final bottomInset = MediaQuery.of(context).padding.bottom;
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.only(bottom: 24 + bottomInset),
                children: [
                  _HeroCarousel(
                    height: 360,
                    images: images
                        .map((img) => _HeroImage(
                              url: resolveMediaUrl(img.fileUrl),
                              alt: _trimOrEmpty(img.altText).isEmpty
                                  ? title
                                  : img.altText!,
                            ))
                        .toList(growable: false),
                    loading: _loading,
                    error: _error,
                    onIndexChanged: (idx) => setState(() => _activeIndex = idx),
                    controller: _pageController,
                    activeIndex: _activeIndex,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                                label: 'TOTAL PLOTS',
                                value:
                                    plotsCountLabel?.trim().isNotEmpty ?? false
                                        ? plotsCountLabel!.trim()
                                        : '—',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: 'TOTAL AREA',
                                value: (areaLabel ?? '').trim().isEmpty
                                    ? '—'
                                    : areaLabel!,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _SectionCard(
                          title: 'LAYOUT OVERVIEW',
                          child: Column(
                            children: [
                              _KeyValueRow(
                                label: 'Approval No',
                                value: (approvalNumber ?? '').trim().isEmpty
                                    ? '—'
                                    : approvalNumber!,
                              ),
                              const SizedBox(height: 10),
                              _KeyValueRow(
                                label: 'Survey No',
                                value: (surveyNumber ?? '').trim().isEmpty
                                    ? '—'
                                    : surveyNumber!,
                              ),
                              const SizedBox(height: 10),
                              _KeyValueRow(
                                label: 'Location',
                                value: location ?? '—',
                              ),
                              if (contactNumbers != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Contact',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Builder(
                                        builder: (context) {
                                          final numbers = _splitContactNumbers(
                                              contactNumbers);
                                          if (numbers.isEmpty) {
                                            return const Text(
                                              '—',
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                color: Color(0xFF0F172A),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            );
                                          }

                                          return Align(
                                            alignment: Alignment.centerRight,
                                            child: Wrap(
                                              alignment: WrapAlignment.end,
                                              spacing: 12,
                                              runSpacing: 6,
                                              children: [
                                                for (final number in numbers)
                                                  GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: () =>
                                                        _callPhoneNumber(
                                                            number),
                                                    child: Text(
                                                      number,
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                        decorationThickness:
                                                            1.5,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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
                        if (_error != null && _detail == null) ...[
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'ERROR',
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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
                                tag: 'layout_image_${img.url}',
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
                      tag: 'layout_image_${img.url}',
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
