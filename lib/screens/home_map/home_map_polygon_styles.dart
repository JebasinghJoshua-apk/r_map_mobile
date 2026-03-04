part of '../home_map_screen.dart';

// Keep map overlay styling aligned with the web app.
// Source of truth: r-map-ui/src/constants/drawingStyles.ts
// and r-map-ui/src/components/Map/utils/overlayStyles.ts
const double _layoutFillHideZoom = 17.0;

const Color _layoutBoundaryStroke = Color(0xFF1D4ED8);
const Color _layoutBoundaryFill = Color(0xFF2563EB);
const double _layoutBoundaryStrokeOpacity = 1.0;
const double _layoutBoundaryFillOpacity = 0.12;
const int _layoutBoundaryStrokeWidth = 2;

/// Convert a boundary-opacity level (1-5, from metadata) to a fill opacity
/// value. Null or out-of-range means use the default [_layoutBoundaryFillOpacity].
double _boundaryOpacityFromLevel(String? raw) {
  if (raw == null) return _layoutBoundaryFillOpacity;
  final level = int.tryParse(raw);
  if (level == null) return _layoutBoundaryFillOpacity;
  switch (level) {
    case 1:
      return 0.50;
    case 2:
      return 0.59;
    case 3:
      return 0.68;
    case 4:
      return 0.76;
    case 5:
      return 0.85;
    default:
      return _layoutBoundaryFillOpacity;
  }
}

/// Road-specific opacity — slightly darker than plots at every level.
double _roadOpacityFromLevel(String? raw) {
  if (raw == null) return _roadFillOpacity;
  final level = int.tryParse(raw);
  if (level == null) return _roadFillOpacity;
  switch (level) {
    case 1:
      return 0.68;
    case 2:
      return 0.74;
    case 3:
      return 0.80;
    case 4:
      return 0.86;
    case 5:
      return 0.92;
    default:
      return _roadFillOpacity;
  }
}

// Layout preview polygon (shown while full data loads from nearby dialog).
// Teal colors match web: strokeColor #0d9488 (teal-600), fillColor #99f6e4 (teal-200).
const Color _layoutPreviewStroke = Color(0xFF0D9488);
const Color _layoutPreviewFill = Color(0xFF99F6E4);
const double _layoutPreviewStrokeOpacity = 1.0;
const double _layoutPreviewFillOpacity = 0.40;
const int _layoutPreviewStrokeWidth = 3;
const int _layoutPreviewZIndex = 1000000;

const Color _plotStroke = Color(0xFF0F766E);
const Color _plotFill = Color(0xFF16A34A);
// Match web: r-map-ui/src/constants/drawingStyles.ts (plot.fillOpacity=0.3, strokeOpacity=0.95)
const double _plotStrokeOpacity = 0.95;
const double _plotFillOpacity = 0.30;
const int _plotStrokeWidth = 2;

// Keep plot outlines readable at very high zoom.
const double _extraThickPlotStrokeZoomThreshold = 19.0;
const int _extraThickPlotStrokeBump = 2;

const Color _soldPlotStroke = Color(0xFF4B5563);
const Color _soldPlotFill = Color(0xFFC0392B);
const double _soldPlotStrokeOpacity = 0.70;
const double _soldPlotFillOpacity = 0.55;

// Booked plots: amber fill per design spec.
const Color _bookedPlotStroke = Color(0xFF4B5563);
const Color _bookedPlotFill = Color(0xFFF4B400);
const double _bookedPlotStrokeOpacity = 0.75;
const double _bookedPlotFillOpacity = 0.42;

// Selected plot highlight overlay (mobile-only UX affordance).
// Match selected property UX: keep same base colors, but add a white outline
// so the selection reads clearly over adjacent polygons.
const Color _selectedPlotOutlineStroke = Color(0xFFFFFFFF);
const double _selectedPlotOutlineOpacity = 0.95;
const int _selectedPlotStrokeWidthBump = 2;
const int _selectedPlotOutlineStrokeWidthExtra = 3;
const int _selectedPlotZIndex = 999999;
const int _selectedPlotOutlineZIndex = 999998;

// Selected property highlight overlay (mobile-only UX affordance).
// Keep the same color as the property type, but increase stroke width and add
// a white outline so the selection is obvious without changing the palette.
const Color _selectedPropertyOutlineStroke = Color(0xFFFFFFFF);
const double _selectedPropertyOutlineOpacity = 0.95;
const double _selectedPropertyStrokeOpacity = 1.0;
const double _selectedPropertyFillOpacityBump = 0.06;
const int _selectedPropertyStrokeWidthBump = 2;
const int _selectedPropertyOutlineStrokeWidthExtra = 3;
const int _selectedPropertyZIndex = 999998;
const int _selectedPropertyOutlineZIndex = 999997;

// Camera behavior when selecting a plot.
const double _selectedPlotMaxFocusZoom = 20.5;

const Color _amenityStroke = Color(0xFF0F766E);
const Color _amenityFill = Color(0xFF65A30D);
const double _amenityStrokeOpacity = 0.95;
const double _amenityFillOpacity = 0.30;
const int _amenityStrokeWidth = 1;

const Color _roadStroke = Color(0xFF374151);
const Color _roadFill = Color(0xFF2B3139);
const double _roadStrokeOpacity = 0.95;
const double _roadFillOpacity = 0.80;
const int _roadStrokeWidth = 2;

const Color _roadLineStroke = Color(0xFF4B5563);
const double _roadLineStrokeOpacity = 0.70;
const int _roadLineStrokeWidth = 2;

// Property polygon styles (non-layout). Keep aligned with web.
// Source of truth: r-map-ui/src/components/Map/utils/overlayStyles.ts
const Color _propertyDefaultStroke = Color(0xFF005F5A);
const Color _propertyDefaultFill = Color(0xFF60A5FA);

const Color _propertyIndividualPlotsStroke = Color(0xFF166534);
const Color _propertyIndividualPlotsFill = Color(0xFF48BB78);

const Color _propertyLandStroke = Color(0xFF4D7C0F);
const Color _propertyLandFill = Color(0xFF84CC16);

const Color _propertyCommercialStroke = Color(0xFF7C3AED);
const Color _propertyCommercialFill = Color(0xFFA855F7);

const Color _propertyIndependentHouseStroke = Color(0xFF115E59);
const Color _propertyIndependentHouseFill = Color(0xFF5EEAD4);

const Color _propertyApartmentStroke = Color(0xFF0E7490);
const Color _propertyApartmentFill = Color(0xFF22D3EE);

const double _propertyStrokeOpacity = 0.9;
const double _propertyBaseFillOpacity = 0.18;
const int _propertyBaseStrokeWidth = 2;

class _PropertyPolygonStyle {
  const _PropertyPolygonStyle({
    required this.stroke,
    required this.fill,
    required this.zIndex,
  });

  final Color stroke;
  final Color fill;
  final int zIndex;
}

double _adjustFillOpacityForZoom(double zoom, double base) {
  if (zoom >= 18) return math.min(base + 0.22, 0.6);
  if (zoom >= 16) return math.min(base + 0.16, 0.5);
  if (zoom >= 14) return math.min(base + 0.10, 0.42);
  if (zoom >= 12) return math.min(base + 0.05, 0.35);
  return base;
}

int _adjustStrokeWidthForZoom(double zoom, int base) {
  double value;
  if (zoom > _extraThickPlotStrokeZoomThreshold) {
    value = base + 3.0;
  } else if (zoom >= 18) {
    value = base + 2.2;
  } else if (zoom >= 16) {
    value = base + 1.6;
  } else if (zoom >= 14) {
    value = base + 0.8;
  } else if (zoom >= 12) {
    value = base + 0.3;
  } else {
    value = base.toDouble();
  }
  final rounded = value.round();
  return rounded < 1 ? 1 : rounded;
}

int _bumpPlotStrokeWidthForHighZoom(double zoom, int base) {
  if (zoom > _extraThickPlotStrokeZoomThreshold) {
    return base + _extraThickPlotStrokeBump;
  }
  return base;
}

_PropertyPolygonStyle _propertyStyleForType(String propertyType) {
  switch (propertyType.trim()) {
    case 'IndividualPlots':
      return const _PropertyPolygonStyle(
        stroke: _propertyIndividualPlotsStroke,
        fill: _propertyIndividualPlotsFill,
        zIndex: 50,
      );
    case 'Land':
      return const _PropertyPolygonStyle(
        stroke: _propertyLandStroke,
        fill: _propertyLandFill,
        zIndex: 30,
      );
    case 'CommercialSpace':
      return const _PropertyPolygonStyle(
        stroke: _propertyCommercialStroke,
        fill: _propertyCommercialFill,
        zIndex: 55,
      );
    case 'IndependentHouse':
      return const _PropertyPolygonStyle(
        stroke: _propertyIndependentHouseStroke,
        fill: _propertyIndependentHouseFill,
        zIndex: 35,
      );
    case 'ApartmentFlat':
      return const _PropertyPolygonStyle(
        stroke: _propertyApartmentStroke,
        fill: _propertyApartmentFill,
        zIndex: 35,
      );
    case 'Layout':
      return const _PropertyPolygonStyle(
        stroke: _layoutBoundaryStroke,
        fill: _layoutBoundaryFill,
        zIndex: 40,
      );
    case 'Road':
    case 'LayoutRoad':
      return const _PropertyPolygonStyle(
        stroke: _roadStroke,
        fill: _roadFill,
        zIndex: 38,
      );
    default:
      return const _PropertyPolygonStyle(
        stroke: _propertyDefaultStroke,
        fill: _propertyDefaultFill,
        zIndex: 25,
      );
  }
}

bool _isSoldPlot(MapPlotFeature plot) {
  final statusKey = _plotStatusKey(plot);
  if (statusKey == 'sold') return true;

  // Backward compatibility: older datasets mark sold with a separate flag.
  final meta = plot.metadata;
  final rawSold =
      (meta['sold'] ?? meta['isSold'] ?? meta['is_sold'])?.trim().toLowerCase();
  return rawSold == 'true' || rawSold == '1' || rawSold == 'yes';
}

bool _isBookedPlot(MapPlotFeature plot) {
  return _plotStatusKey(plot) == 'booked';
}

String _plotStatusKey(MapPlotFeature plot) {
  final meta = plot.metadata;
  final raw = (meta['plotStatus'] ??
          meta['plot_status'] ??
          meta['status'] ??
          meta['availability'])
      ?.trim()
      .toLowerCase();
  if (raw == null || raw.isEmpty) return 'available';

  // Backend enum values: Available=0, Booked=1, Sold=2, Blocked=3
  if (raw == '1') return 'booked';
  if (raw == '2') return 'sold';
  if (raw == '3') return 'blocked';

  if (raw == 'available' ||
      raw == 'booked' ||
      raw == 'sold' ||
      raw == 'blocked') {
    return raw;
  }

  return 'available';
}

String _plotElementKind(MapPlotFeature plot) {
  final meta = plot.metadata;
  final candidates = <String?>[
    meta['elementType'],
    meta['element_type'],
    meta['type'],
    meta['category'],
    meta['kind'],
  ]
      .map((v) => v?.trim().toLowerCase())
      .where((v) => v != null && v.isNotEmpty)
      .cast<String>()
      .toList(growable: false);

  final isRoad = candidates.any((v) => v.contains('road')) ||
      (meta['roadName']?.trim().isNotEmpty ?? false);
  if (isRoad) return 'road';
  if (candidates.any((v) => v.contains('boundary'))) return 'boundary';
  return 'plot';
}
