part of 'home_map_screen.dart';

// Shared constants / helpers extracted from the main screen to keep
// `home_map_screen.dart` focused on state + UI wiring.

const int _viewportCacheMaxEntries = 24;
const Duration _viewportCacheTtl = Duration(seconds: 30);

const double _styleZoomMinDelta = 0.25;
const double _overlayRetentionMultiplier = 1.75;

const double _hybridZoomEnter = 17.5;
const double _hybridZoomExit = 17.5;

const String _lightMapStyleAssetPath = 'assets/map_light.json';

const CameraPosition _initialCameraPosition = CameraPosition(
  target: LatLng(9.508604738700296, 78.09598717263208),
  zoom: 16,
);

const double _minPlotPolygonZoom = 16.2;
const double _minRoadOverlayZoom = 16.0;

// Keep label behavior aligned with the web app.
// Source: r-map-ui/src/components/Map/MapViewportLayer/constants.ts
const double _minPlotLabelZoom = 17.5;
const double _minRoadLabelZoom = 17.0;
const double _minAmenityLabelZoom = 17.0;

// Keep aligned with web marker icon colors:
// r-map-ui/src/components/Map/utils/markerIcons.ts (LAYOUT_MARKER_COLORS)
const Color _layoutMarkerOuterFill = Color.fromRGBO(55, 48, 163, 0.3);
const Color _layoutMarkerOuterStroke = Color.fromRGBO(55, 48, 163, 0.55);
const Color _layoutMarkerInnerFill = Color(0xFF3730A3);
const Color _layoutMarkerInnerStroke = Color(0xFFC7D2FE);

const int _maxLabelMarkers = 550;

const int _labelIconCacheMaxEntries = 5000;
const int _badgeIconCacheMaxEntries = 2500;

// Keep badge marker styling aligned with the web app.
// Source of truth: r-map-ui/src/components/Map/utils/markerIcons.ts
const double _layoutBadgeMaxZoom = 17.0;

const Color _priceBadgeDefaultBackground = Color(0xFF0F766E);
const Color _priceBadgeDefaultStroke = Color(0xFFFFFFFF);
const Color _priceBadgeDefaultText = Color(0xFFF8FAFC);

const Color _priceBadgeCommercialBackground = Color(0xFF6B21A8);
const Color _priceBadgeCommercialStroke = Color(0xFFE9D5FF);
const Color _priceBadgeCommercialText = Color(0xFFFDF4FF);

const Color _priceBadgeLandBackground = Color(0xFF3F6212);
const Color _priceBadgeLandStroke = Color(0xFFD9F99D);
const Color _priceBadgeLandText = Color(0xFFF7FEE7);

const Color _priceBadgeApartmentBackground = Color(0xFF155E75);
const Color _priceBadgeApartmentStroke = Color(0xFFBAE6FD);
const Color _priceBadgeApartmentText = Color(0xFFECFEFF);

const Color _priceBadgePlotBackground = Color(0xFF22543D);
const Color _priceBadgePlotStroke = Color(0xFFBAE6FD);
const Color _priceBadgePlotText = Color(0xFFF8FAFC);

// Selected badge marker (mobile-only): used when a property is actively selected
// (e.g. independent house via bottom carousel) so its badge stands out.

const Color _layoutBadgeBackground = Color(0xFF3730A3);
const Color _layoutBadgeStroke = Color(0xFFEEF2FF);
const Color _layoutBadgeTitle = Color(0xFFF8FAFC);
const Color _layoutBadgeSubtitle = Color(0xFFC7D2FE);

const Color _badgeShadowColor = Color(0x590F172A);

int _layoutMarkerSizeForZoom(double zoom) {
  // Keep aligned with computeMarkerSizeForZoom in web markerIcons.ts
  if (zoom >= 18.5) return 29;
  if (zoom >= 17.2) return 27;
  if (zoom >= 16.5) return 24;
  if (zoom >= 15.5) return 20;
  return 14;
}

double _priceBadgeFocusZoomTarget(String propertyType) {
  // Keep aligned with web: r-map-ui/src/components/Map/MapViewportLayer/constants.ts
  switch (propertyType.trim()) {
    case 'Land':
      return 18.5;
    case 'IndependentHouse':
    case 'ApartmentFlat':
    case 'CommercialSpace':
    case 'IndividualPlots':
      return 20.0;
    default:
      return 20.0;
  }
}

// Keep aligned with web: LAYOUT_AUTO_FOCUS_ZOOM_TARGET in
// r-map-ui/src/components/Map/MapViewportLayer/constants.ts
const double _layoutFocusZoomTarget = 18.5;

_PriceBadgeColors _priceBadgeColorsForPropertyType(String propertyType) {
  switch (propertyType.trim()) {
    case 'CommercialSpace':
      return const _PriceBadgeColors(
        background: _priceBadgeCommercialBackground,
        stroke: _priceBadgeCommercialStroke,
        text: _priceBadgeCommercialText,
      );
    case 'Land':
      return const _PriceBadgeColors(
        background: _priceBadgeLandBackground,
        stroke: _priceBadgeLandStroke,
        text: _priceBadgeLandText,
      );
    case 'ApartmentFlat':
      return const _PriceBadgeColors(
        background: _priceBadgeApartmentBackground,
        stroke: _priceBadgeApartmentStroke,
        text: _priceBadgeApartmentText,
      );
    case 'IndividualPlots':
      return const _PriceBadgeColors(
        background: _priceBadgePlotBackground,
        stroke: _priceBadgePlotStroke,
        text: _priceBadgePlotText,
      );
    default:
      return const _PriceBadgeColors(
        background: _priceBadgeDefaultBackground,
        stroke: _priceBadgeDefaultStroke,
        text: _priceBadgeDefaultText,
      );
  }
}

String? _getMetadataValue(Map<String, String?> metadata, List<String> keys) {
  for (final key in keys) {
    final v = metadata[key]?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

const double _rupeeCrore = 10000000;
const double _rupeeLakh = 100000;
const double _rupeeThousand = 1000;

class _PropertyTypeOption {
  const _PropertyTypeOption({required this.id, required this.label});

  final String? id; // null => All properties
  final String label;
}

const List<_PropertyTypeOption> _propertyTypeOptions = <_PropertyTypeOption>[
  _PropertyTypeOption(id: null, label: 'All properties'),
  _PropertyTypeOption(id: 'Layout', label: 'Layouts'),
  _PropertyTypeOption(id: 'IndividualPlots', label: 'Individual Plots'),
  _PropertyTypeOption(id: 'Land', label: 'Land'),
  _PropertyTypeOption(id: 'CommercialSpace', label: 'Commercial'),
  _PropertyTypeOption(id: 'IndependentHouse', label: 'Independent Houses'),
  _PropertyTypeOption(id: 'ApartmentFlat', label: 'Apartments'),
];

class _PriceRangeFilter {
  const _PriceRangeFilter({
    required this.label,
    this.minRupees,
    this.maxRupees,
  });

  final String label;
  final int? minRupees;
  final int? maxRupees;
}

class _AreaRangeFilter {
  const _AreaRangeFilter({
    required this.minSqft,
    required this.maxSqft,
  });

  final int minSqft;
  final int maxSqft;
}

const List<String> _commercialSuitableForOptions = <String>[
  'Office Space',
  'Showroom',
  'Shop',
  'Godown',
  'Industrial',
  'Co-working',
  'Restaurant',
];

const List<int> _bedroomMinOptions = <int>[1, 2, 3, 4, 5];
const List<int> _floorMinOptions = <int>[1, 2, 3];

const List<String> _buildingAgeOptions = <String>[
  'New',
  '0–5 yrs',
  '5–10 yrs',
  '10–20 yrs',
  '20+ yrs',
];

const List<String> _apartmentPropertyFloorOptions = <String>[
  'Ground',
  '1',
  '2',
  '3',
  '4',
  '5+',
  'Top Floor',
];

const List<String> _apartmentTotalFloorsOptions = <String>[
  'Low-rise (1–3)',
  'Mid-rise (4–7)',
  'High-rise (8+)',
];

const _PriceRangeFilter _anyPriceRange =
    _PriceRangeFilter(label: 'Any', minRupees: null, maxRupees: null);

const List<_PriceRangeFilter> _priceRangeOptions = <_PriceRangeFilter>[
  _anyPriceRange,
  _PriceRangeFilter(label: '≤ ₹25L', minRupees: null, maxRupees: 2500000),
  _PriceRangeFilter(label: '₹25L–₹50L', minRupees: 2500000, maxRupees: 5000000),
  _PriceRangeFilter(
      label: '₹50L–₹1Cr', minRupees: 5000000, maxRupees: 10000000),
  _PriceRangeFilter(label: '≥ ₹1Cr', minRupees: 10000000, maxRupees: null),
];

String? _formatPriceBadgeLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final match = RegExp(r'([\d.,]+)(?:\s*([a-zA-Z]+))?').firstMatch(trimmed);
  if (match == null) return null;

  final numericText = match.group(1)?.replaceAll(',', '');
  final numericValue =
      numericText == null ? null : double.tryParse(numericText);
  if (numericValue == null || !numericValue.isFinite) return null;

  final suffix = (match.group(2) ?? '').toLowerCase();
  final lower = trimmed.toLowerCase();

  double multiplier = 1;
  const suffixMultipliers = <String, double>{
    'c': _rupeeCrore,
    'cr': _rupeeCrore,
    'crore': _rupeeCrore,
    'crores': _rupeeCrore,
    'l': _rupeeLakh,
    'lac': _rupeeLakh,
    'lacs': _rupeeLakh,
    'lakh': _rupeeLakh,
    'lakhs': _rupeeLakh,
    'k': _rupeeThousand,
    'thousand': _rupeeThousand,
  };

  if (suffix.isNotEmpty && suffixMultipliers.containsKey(suffix)) {
    multiplier = suffixMultipliers[suffix]!;
  } else {
    if (lower.contains('crore') || RegExp(r'\bcr\b').hasMatch(lower)) {
      multiplier = _rupeeCrore;
    } else if (lower.contains('lakh') ||
        lower.contains('lac') ||
        RegExp(r'\bl\b').hasMatch(lower)) {
      multiplier = _rupeeLakh;
    } else if (lower.contains('thousand') || RegExp(r'\bk\b').hasMatch(lower)) {
      multiplier = _rupeeThousand;
    }
  }

  final amount = numericValue * multiplier;
  if (!amount.isFinite || amount <= 0) return null;

  String compact(double value) {
    if (value >= 10) return value.round().toString();
    final rounded = (value * 10).round() / 10;
    return (rounded % 1 == 0)
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  if (amount >= _rupeeCrore) {
    return '₹${compact(amount / _rupeeCrore)}C';
  }
  if (amount >= _rupeeLakh) {
    return '₹${compact(amount / _rupeeLakh)}L';
  }
  if (amount >= _rupeeThousand) {
    return '₹${compact(amount / _rupeeThousand)}K';
  }
  return '₹${amount.round()}';
}

int? _parsePriceToRupees(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final lower = trimmed.toLowerCase();

  final match = RegExp(r'([\d.,]+)(?:\s*([a-zA-Z]+))?').firstMatch(trimmed);
  if (match == null) return null;

  final numericText = match.group(1)?.replaceAll(',', '');
  final numericValue =
      numericText == null ? null : double.tryParse(numericText);
  if (numericValue == null || !numericValue.isFinite) return null;

  final suffix = (match.group(2) ?? '').toLowerCase();

  double multiplier = 1;
  const suffixMultipliers = <String, double>{
    'c': _rupeeCrore,
    'cr': _rupeeCrore,
    'crore': _rupeeCrore,
    'crores': _rupeeCrore,
    'l': _rupeeLakh,
    'lac': _rupeeLakh,
    'lacs': _rupeeLakh,
    'lakh': _rupeeLakh,
    'lakhs': _rupeeLakh,
    'k': _rupeeThousand,
    'thousand': _rupeeThousand,
  };

  if (suffix.isNotEmpty && suffixMultipliers.containsKey(suffix)) {
    multiplier = suffixMultipliers[suffix]!;
  } else {
    if (lower.contains('crore') || RegExp(r'\bcr\b').hasMatch(lower)) {
      multiplier = _rupeeCrore;
    } else if (lower.contains('lakh') ||
        lower.contains('lac') ||
        RegExp(r'\bl\b').hasMatch(lower)) {
      multiplier = _rupeeLakh;
    } else if (lower.contains('thousand') || RegExp(r'\bk\b').hasMatch(lower)) {
      multiplier = _rupeeThousand;
    }
  }

  final amount = numericValue * multiplier;
  if (!amount.isFinite || amount <= 0) return null;
  return amount.round();
}

class _HomeMapIconFactory {
  final LinkedHashMap<String, BitmapDescriptor> _labelIconCache =
      LinkedHashMap<String, BitmapDescriptor>();
  final LinkedHashMap<String, BitmapDescriptor> _badgeIconCache =
      LinkedHashMap<String, BitmapDescriptor>();

  Future<BitmapDescriptor> getLayoutMarkerDotIcon({
    required double zoom,
    required double pixelRatio,
  }) async {
    final size = _layoutMarkerSizeForZoom(zoom);

    final cacheKey = [
      'layout-dot',
      size,
      zoom.toStringAsFixed(2),
      pixelRatio.toStringAsFixed(2),
    ].join('|');

    final cached = _badgeIconCache.remove(cacheKey);
    if (cached != null) {
      _badgeIconCache[cacheKey] = cached;
      return cached;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    final outerRadius = size / 2;
    final innerRadius = math.max(outerRadius - 4.0, 1.0);
    final center = outerRadius;

    final outerFillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = _layoutMarkerOuterFill;
    final outerStrokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _layoutMarkerOuterStroke;

    final innerFillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = _layoutMarkerInnerFill;
    final innerStrokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _layoutMarkerInnerStroke;

    canvas.drawCircle(ui.Offset(center, center), outerRadius, outerFillPaint);
    canvas.drawCircle(ui.Offset(center, center), outerRadius, outerStrokePaint);
    canvas.drawCircle(ui.Offset(center, center), innerRadius, innerFillPaint);
    canvas.drawCircle(ui.Offset(center, center), innerRadius, innerStrokePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size * pixelRatio).ceil(),
      (size * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: pixelRatio,
    );

    if (_badgeIconCache.length >= _badgeIconCacheMaxEntries) {
      _badgeIconCache.remove(_badgeIconCache.keys.first);
    }
    _badgeIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> getPriceBadgeIcon({
    required String label,
    required double zoom,
    required double pixelRatio,
    required Color background,
    required Color stroke,
    required Color text,
    bool emphasize = false,
  }) async {
    final scale = emphasize ? 1.18 : 1.0;

    final fontSize = (zoom >= 18.2
            ? 14.0
            : zoom >= 17.0
                ? 12.0
                : 10.0) *
        scale;
    final charWidth = fontSize * 0.52;
    final paddingX = math.max(8.0 * scale, fontSize * 0.6);
    final minWidth = (fontSize * 2.6).ceilToDouble();
    final badgeWidth =
        math.max(minWidth, label.length * charWidth + paddingX * 2);
    final paddingY = math.max(4.0 * scale, fontSize * 0.35);
    final badgeHeight = (fontSize + paddingY * 2);
    final pointerHeight = 6.0 * scale;
    final totalHeight = badgeHeight + pointerHeight;
    final radius = 6.0 * scale;
    final triangleHalfWidth = math.max(6.0 * scale, fontSize * 0.55);
    final borderWidth = math.max(0.9 * scale, fontSize * 0.1);

    final cacheKey = [
      'price',
      label,
      zoom.toStringAsFixed(2),
      pixelRatio.toStringAsFixed(2),
      background.value.toRadixString(16),
      stroke.value.toRadixString(16),
      text.value.toRadixString(16),
      emphasize ? '1' : '0',
    ].join('|');

    final cached = _badgeIconCache.remove(cacheKey);
    if (cached != null) {
      _badgeIconCache[cacheKey] = cached;
      return cached;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    final bubblePath = ui.Path()
      ..moveTo(radius, 0)
      ..lineTo(badgeWidth - radius, 0)
      ..quadraticBezierTo(badgeWidth, 0, badgeWidth, radius)
      ..lineTo(badgeWidth, badgeHeight - radius)
      ..quadraticBezierTo(
          badgeWidth, badgeHeight, badgeWidth - radius, badgeHeight)
      ..lineTo(badgeWidth / 2 + triangleHalfWidth, badgeHeight)
      ..lineTo(badgeWidth / 2, totalHeight)
      ..lineTo(badgeWidth / 2 - triangleHalfWidth, badgeHeight)
      ..lineTo(radius, badgeHeight)
      ..quadraticBezierTo(0, badgeHeight, 0, badgeHeight - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();

    // Default subtle shadow.
    canvas.drawShadow(bubblePath, _badgeShadowColor, 4.0, true);
    // Selected badge: slightly stronger shadow using the same badge color.
    if (emphasize) {
      canvas.drawShadow(bubblePath, background.withOpacity(0.55), 7.0, true);
    }

    final fillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = background;
    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = stroke;

    if (emphasize) {
      final outlinePaint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = borderWidth + 1.9
        ..color = const Color(0xFFFFFFFF).withOpacity(0.92);
      canvas.drawPath(bubblePath, outlinePaint);
    }

    canvas.drawPath(bubblePath, fillPaint);
    canvas.drawPath(bubblePath, strokePaint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: text,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    )..layout(minWidth: 0, maxWidth: badgeWidth);

    final textOffset = ui.Offset(
      (badgeWidth - textPainter.width) / 2,
      (badgeHeight - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (badgeWidth * pixelRatio).ceil(),
      (totalHeight * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor =
        BitmapDescriptor.bytes(bytes, imagePixelRatio: pixelRatio);

    if (_badgeIconCache.length >= _badgeIconCacheMaxEntries) {
      _badgeIconCache.remove(_badgeIconCache.keys.first);
    }
    _badgeIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> getLayoutBadgeIcon({
    required String title,
    required String? subtitle,
    required double zoom,
    required double pixelRatio,
  }) async {
    final clampedZoom = zoom.clamp(12.0, 20.0);
    final isBig = clampedZoom >= 16.8;

    final titleFont = isBig ? 13.0 : 11.0;
    final subtitleFont = isBig ? 10.0 : 9.0;
    final paddingX = isBig ? 10.0 : 8.0;
    final paddingY = isBig ? 7.0 : 6.0;
    final radius = isBig ? 8.0 : 7.0;

    final effectiveSubtitle = (subtitle ?? '').trim();
    final hasSubtitle = effectiveSubtitle.isNotEmpty;

    final cacheKey = [
      'layout-badge',
      title,
      effectiveSubtitle,
      isBig ? '1' : '0',
      clampedZoom.toStringAsFixed(2),
      pixelRatio.toStringAsFixed(2),
    ].join('|');

    final cached = _badgeIconCache.remove(cacheKey);
    if (cached != null) {
      _badgeIconCache[cacheKey] = cached;
      return cached;
    }

    final titlePainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: _layoutBadgeTitle,
          fontSize: titleFont,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    );

    final subtitlePainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      text: TextSpan(
        text: hasSubtitle ? effectiveSubtitle : '',
        style: TextStyle(
          color: _layoutBadgeSubtitle,
          fontSize: subtitleFont,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );

    // Keep it reasonably compact; we can expand later if needed.
    const maxTextWidth = 160.0;
    titlePainter.layout(maxWidth: maxTextWidth);
    if (hasSubtitle) {
      subtitlePainter.layout(maxWidth: maxTextWidth);
    }

    final contentWidth =
        math.max(titlePainter.width, hasSubtitle ? subtitlePainter.width : 0);
    final bubbleWidth = contentWidth + paddingX * 2;

    final contentHeight =
        titlePainter.height + (hasSubtitle ? subtitlePainter.height + 2.0 : 0);
    final bubbleHeight = contentHeight + paddingY * 2;

    const pointerHeight = 7.0;
    const pointerWidth = 16.0;
    final totalHeight = bubbleHeight + pointerHeight;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    final bubble = ui.Path()
      ..addRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
          ui.Radius.circular(radius),
        ),
      )
      ..moveTo((bubbleWidth - pointerWidth) / 2, bubbleHeight)
      ..lineTo(bubbleWidth / 2, totalHeight)
      ..lineTo((bubbleWidth + pointerWidth) / 2, bubbleHeight)
      ..close();

    canvas.drawShadow(bubble, _badgeShadowColor, 4.0, true);

    final fillPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = _layoutBadgeBackground;
    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = isBig ? 1.2 : 1.0
      ..color = _layoutBadgeStroke;

    canvas.drawPath(bubble, fillPaint);
    canvas.drawPath(bubble, strokePaint);

    var textY = paddingY;
    titlePainter.paint(canvas,
        ui.Offset(paddingX + (contentWidth - titlePainter.width) / 2, textY));
    textY += titlePainter.height;
    if (hasSubtitle) {
      textY += 2.0;
      subtitlePainter.paint(
        canvas,
        ui.Offset(paddingX + (contentWidth - subtitlePainter.width) / 2, textY),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (bubbleWidth * pixelRatio).ceil(),
      (totalHeight * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor =
        BitmapDescriptor.bytes(bytes, imagePixelRatio: pixelRatio);

    if (_badgeIconCache.length >= _badgeIconCacheMaxEntries) {
      _badgeIconCache.remove(_badgeIconCache.keys.first);
    }
    _badgeIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> getTextLabelIcon({
    required String text,
    required double pixelRatio,
    required double fontSize,
    required Color textColor,
    Color? backgroundColor,
    required EdgeInsets padding,
    required double borderRadius,
    List<Shadow>? shadows,
  }) async {
    final cacheKey = [
      'label',
      text,
      fontSize.toStringAsFixed(1),
      textColor.value.toRadixString(16),
      backgroundColor?.value.toRadixString(16) ?? 'none',
      padding.horizontal.toStringAsFixed(1),
      padding.vertical.toStringAsFixed(1),
      borderRadius.toStringAsFixed(1),
      _shadowsSignature(shadows),
      pixelRatio.toStringAsFixed(2),
    ].join('|');

    final cached = _labelIconCache.remove(cacheKey);
    if (cached != null) {
      _labelIconCache[cacheKey] = cached;
      return cached;
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: shadows,
        ),
      ),
    )..layout();

    final width =
        (textPainter.width + padding.left + padding.right).ceil().toDouble();
    final height =
        (textPainter.height + padding.top + padding.bottom).ceil().toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(pixelRatio);

    if (backgroundColor != null) {
      final rect = ui.Rect.fromLTWH(0, 0, width, height);
      final rrect = ui.RRect.fromRectAndRadius(
        rect,
        ui.Radius.circular(borderRadius),
      );
      final bgPaint = ui.Paint()..color = backgroundColor;
      canvas.drawRRect(rrect, bgPaint);
    }

    textPainter.paint(
      canvas,
      ui.Offset(padding.left, padding.top),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * pixelRatio).ceil(),
      (height * pixelRatio).ceil(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List() ?? Uint8List(0);
    final descriptor = BitmapDescriptor.bytes(
      bytes,
      imagePixelRatio: pixelRatio,
    );

    if (_labelIconCache.length >= _labelIconCacheMaxEntries) {
      _labelIconCache.remove(_labelIconCache.keys.first);
    }
    _labelIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  String _shadowsSignature(List<Shadow>? shadows) {
    if (shadows == null || shadows.isEmpty) return 'none';
    return shadows
        .map(
          (s) => [
            s.color.value.toRadixString(16),
            s.blurRadius.toStringAsFixed(2),
            s.offset.dx.toStringAsFixed(2),
            s.offset.dy.toStringAsFixed(2),
          ].join(','),
        )
        .join(';');
  }
}

class _PriceBadgeColors {
  const _PriceBadgeColors({
    required this.background,
    required this.stroke,
    required this.text,
  });

  final Color background;
  final Color stroke;
  final Color text;
}

class _LabelMarkerResult {
  const _LabelMarkerResult({
    required this.plotLabelMarkers,
    required this.roadLabelMarkers,
    required this.amenityLabelMarkers,
  });

  final Set<Marker> plotLabelMarkers;
  final Set<Marker> roadLabelMarkers;
  final Set<Marker> amenityLabelMarkers;
}

class _LineLabelPlacement {
  const _LineLabelPlacement({
    required this.position,
    required this.rotationDegrees,
  });

  final LatLng position;
  final double rotationDegrees;
}
