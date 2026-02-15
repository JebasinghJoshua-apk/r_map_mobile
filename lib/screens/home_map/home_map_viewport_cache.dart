part of '../home_map_screen.dart';

class _ViewportRenderCacheEntry {
  _ViewportRenderCacheEntry({
    required this.markers,
    required this.plotLabelMarkers,
    required this.roadLabelMarkers,
    required this.amenityLabelMarkers,
    required this.layoutPolygons,
    required this.propertyPolygons,
    required this.plotPolygons,
    required this.amenityPolygons,
    required this.roadPolygons,
    required this.roadPolylines,
    required this.ownedLayoutIds,
    required this.propertyByFeatureId,
    this.plots = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final Set<Marker> markers;
  final Set<Marker> plotLabelMarkers;
  final Set<Marker> roadLabelMarkers;
  final Set<Marker> amenityLabelMarkers;
  final Set<Polygon> layoutPolygons;
  final Set<Polygon> propertyPolygons;
  final Set<Polygon> plotPolygons;
  final Set<Polygon> amenityPolygons;
  final Set<Polygon> roadPolygons;
  final Set<Polyline> roadPolylines;
  final Set<String> ownedLayoutIds;
  final Map<String, MapPropertyFeature> propertyByFeatureId;
  /// Raw plot features for deep-link auto-selection from cached viewport.
  final List<MapPlotFeature> plots;
  final DateTime createdAt;

  _ViewportRenderCacheEntry copyWith({
    Set<Marker>? markers,
    Set<Marker>? plotLabelMarkers,
    Set<Marker>? roadLabelMarkers,
    Set<Marker>? amenityLabelMarkers,
  }) {
    return _ViewportRenderCacheEntry(
      markers: markers ?? this.markers,
      plotLabelMarkers: plotLabelMarkers ?? this.plotLabelMarkers,
      roadLabelMarkers: roadLabelMarkers ?? this.roadLabelMarkers,
      amenityLabelMarkers: amenityLabelMarkers ?? this.amenityLabelMarkers,
      layoutPolygons: layoutPolygons,
      propertyPolygons: propertyPolygons,
      plotPolygons: plotPolygons,
      amenityPolygons: amenityPolygons,
      roadPolygons: roadPolygons,
      roadPolylines: roadPolylines,
      ownedLayoutIds: ownedLayoutIds,
      propertyByFeatureId: propertyByFeatureId,
      plots: plots,
      createdAt: createdAt,
    );
  }
}

extension _HomeMapViewportCache on _HomeMapScreenState {
  MapViewportResponse _applyClientFilters(MapViewportResponse response) {
    final type = _selectedPropertyType?.trim();
    final listingType = _selectedListingType?.trim();

    int? parseIntFromMetadata(
        Map<String, String?> metadata, List<String> keys) {
      final raw = _getMetadataValue(metadata, keys);
      if (raw == null) return null;
      final numericText = raw
          .trim()
          .toLowerCase()
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^0-9]'), '');
      if (numericText.isEmpty) return null;
      return int.tryParse(numericText);
    }

    bool parseBoolTruthy(String raw) {
      final v = raw.trim().toLowerCase();
      return v == 'true' ||
          v == 'yes' ||
          v == 'y' ||
          v == '1' ||
          v == 'available';
    }

    int? parseBuildingAgeYears(Map<String, String?> metadata) {
      final raw = _getMetadataValue(
        metadata,
        const <String>[
          'buildingAge',
          'building_age',
          'propertyAge',
          'property_age',
          'constructionAge',
          'construction_age',
          'age',
        ],
      );
      if (raw == null) return null;
      final lower = raw.trim().toLowerCase();
      if (lower.isEmpty) return null;
      if (lower.contains('new')) return 0;
      // Accept ranges like "0-5", "0–5" and pick the max as a conservative estimate.
      final range = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(lower);
      if (range != null) {
        final a = int.tryParse(range.group(1) ?? '');
        final b = int.tryParse(range.group(2) ?? '');
        if (a != null && b != null) return b;
      }

      final years = RegExp(r'(\d+)').firstMatch(lower);
      final value = years == null ? null : int.tryParse(years.group(1) ?? '');
      return value;
    }

    int? parseSqft(Map<String, String?> metadata) {
      final raw = _getMetadataValue(
        metadata,
        const <String>[
          'builtUpAreaInSquareFeet',
          'builtUpAreaSqFt',
          'builtUpAreaSqft',
          'areaSqFt',
          'areaSqft',
          'area_sqft',
          'sqft',
          'area',
        ],
      );
      if (raw == null) return null;
      final numericText = raw.trim().replaceAll(',', '');
      final value = double.tryParse(numericText);
      if (value == null || !value.isFinite) return null;
      if (value <= 0) return null;
      return value.round();
    }

    bool matchesSuitableFor(Map<String, String?> metadata, String selected) {
      final raw = _getMetadataValue(
        metadata,
        const <String>[
          'spaceType',
          'commercialSpaceType',
          'suitableFor',
          'suitable_for',
          'useType',
          'use_type',
        ],
      );
      if (raw == null) return false;

      String norm(String s) => s
          .trim()
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll(RegExp(r'\s+'), ' ');

      final selectedNorm = norm(selected);
      final rawParts = raw
          .split(RegExp(r'[,/|]'))
          .map((p) => norm(p))
          .where((p) => p.isNotEmpty)
          .toList(growable: false);

      if (rawParts.contains(selectedNorm)) return true;

      // Handle common variants.
      const aliases = <String, List<String>>{
        'office space': <String>['office', 'officespace'],
        'co working': <String>['coworking', 'co-working', 'co working'],
        'godown': <String>['warehouse', 'store', 'storage'],
      };

      final selectedAlternates = <String>{selectedNorm};
      if (aliases.containsKey(selectedNorm)) {
        selectedAlternates.addAll(aliases[selectedNorm]!.map(norm));
      }
      // Also map "Co-working" label to "co working" normalized key.
      if (selectedNorm == 'co working' || selectedNorm == 'co-working') {
        selectedAlternates.addAll(aliases['co working']!.map(norm));
      }

      for (final part in rawParts) {
        for (final alt in selectedAlternates) {
          if (part == alt) return true;
        }
      }
      return false;
    }

    if ((type == null || type.isEmpty) &&
        (listingType == null || listingType.isEmpty)) {
      return response;
    }

    var filteredProperties = response.properties;
    var didFilter = false;

    if (listingType != null && listingType.isNotEmpty) {
      final selectedNorm = listingType.toLowerCase();
      filteredProperties = filteredProperties.where((feature) {
        final raw = feature.listingType?.trim();

        // Some feature types are effectively Buy-only and may not carry an
        // explicit listingType in the payload (e.g., Layout groups).
        if (raw == null || raw.isEmpty) {
          final pt = feature.propertyType.trim().toLowerCase();
          final isBuyOnlyType = pt == 'layout' || pt == 'individualplots';
          final isBuySelected = selectedNorm == 'sell' || selectedNorm == 'buy';
          return isBuyOnlyType && isBuySelected;
        }
        final rawNorm = raw.toLowerCase();

        if (rawNorm == selectedNorm) return true;
        // Some backends/clients use Buy/Sell interchangeably.
        if (selectedNorm == 'sell' && rawNorm == 'buy') return true;
        if (selectedNorm == 'buy' && rawNorm == 'sell') return true;
        return false;
      }).toList(growable: false);
      didFilter = true;
    }

    if (type == null || type.isEmpty) {
      if (!didFilter) return response;

      final allowedIds = filteredProperties
          .map((p) => p.propertyId.trim())
          .where((p) => p.isNotEmpty)
          .toSet();

      final filteredPlots = response.plots.where((plot) {
        final id = plot.individualPlotsId?.trim();
        if (id == null || id.isEmpty) return true;
        return allowedIds.contains(id);
      }).toList(growable: false);

      final filteredRoads = response.roads.where((road) {
        final ip = road.individualPlotsId?.trim();
        if (ip != null && ip.isNotEmpty) {
          return allowedIds.contains(ip);
        }
        final land = road.landId?.trim();
        if (land != null && land.isNotEmpty) {
          return allowedIds.contains(land);
        }
        final comm = road.commercialSpaceId?.trim();
        if (comm != null && comm.isNotEmpty) {
          return allowedIds.contains(comm);
        }
        return true;
      }).toList(growable: false);

      return MapViewportResponse(
        detailLevel: response.detailLevel,
        properties: filteredProperties.toList(growable: false),
        plots: filteredPlots,
        roads: filteredRoads,
        amenities: response.amenities,
      );
    }

    if (type == 'Layout') {
      return didFilter
          ? MapViewportResponse(
              detailLevel: response.detailLevel,
              properties: filteredProperties.toList(growable: false),
              plots: response.plots,
              roads: response.roads,
              amenities: response.amenities,
            )
          : response;
    }

    if (type == 'Land') {
      final selectedLandType = _selectedLandType?.trim();
      if (selectedLandType != null && selectedLandType.isNotEmpty) {
        filteredProperties = filteredProperties.where((feature) {
          final raw = _getMetadataValue(
            feature.metadata,
            const <String>[
              'landType',
              'land_type',
              'landTypeId',
              'landTypeValue',
            ],
          );
          if (raw == null) return false;

          final selectedNorm = selectedLandType.toLowerCase();
          final rawNorm = raw.trim().toLowerCase();
          if (rawNorm == selectedNorm) return true;

          final numeric = int.tryParse(rawNorm);
          if (numeric == null) return false;
          const mapping = <int, String>{
            1: 'residential',
            2: 'commercial',
            3: 'agricultural',
          };
          return mapping[numeric] == selectedNorm;
        }).toList(growable: false);
        didFilter = true;
      }
    }

    if (type == 'CommercialSpace') {
      final selectedSuitableFor = _selectedCommercialSuitableFor?.trim();
      if (selectedSuitableFor != null && selectedSuitableFor.isNotEmpty) {
        filteredProperties = filteredProperties.where((feature) {
          return matchesSuitableFor(feature.metadata, selectedSuitableFor);
        }).toList(growable: false);
        didFilter = true;
      }

      final area = _selectedAreaRange;
      if (area != null) {
        final min = area.minSqft;
        final max = area.maxSqft;
        filteredProperties = filteredProperties.where((feature) {
          final sqft = parseSqft(feature.metadata);
          if (sqft == null) return false;
          if (sqft < min) return false;
          if (sqft > max) return false;
          return true;
        }).toList(growable: false);
        didFilter = true;
      }
    }

    if (type == 'IndependentHouse') {
      final minBedrooms = _selectedMinBedrooms;
      if (minBedrooms != null) {
        filteredProperties = filteredProperties.where((feature) {
          final bedrooms = parseIntFromMetadata(
            feature.metadata,
            const <String>[
              'bedrooms',
              'bedroom',
              'bhk',
              'noOfBedrooms',
              'no_of_bedrooms',
            ],
          );
          if (bedrooms == null) return false;
          return bedrooms >= minBedrooms;
        }).toList(growable: false);
        didFilter = true;
      }

      final carParking = _selectedCarParking;
      if (carParking == true) {
        filteredProperties = filteredProperties.where((feature) {
          final raw = _getMetadataValue(
            feature.metadata,
            const <String>[
              'carParking',
              'car_parking',
              'parking',
              'carParkingAvailable',
              'car_parking_available',
              'hasParking',
              'has_parking',
            ],
          );
          if (raw == null) return false;
          return parseBoolTruthy(raw);
        }).toList(growable: false);
        didFilter = true;
      }

      final minFloors = _selectedMinFloors;
      if (minFloors != null) {
        filteredProperties = filteredProperties.where((feature) {
          final floors = parseIntFromMetadata(
            feature.metadata,
            const <String>[
              'totalFloors',
              'total_floors',
              'floors',
              'floorCount',
              'floor_count',
            ],
          );
          if (floors == null) return false;
          return floors >= minFloors;
        }).toList(growable: false);
        didFilter = true;
      }

      final buildingAge = _selectedBuildingAge?.trim();
      if (buildingAge != null && buildingAge.isNotEmpty) {
        bool matchesAgeBucket(int years, String bucket) {
          switch (bucket) {
            case 'New':
              return years <= 1;
            case '0–5 yrs':
              return years >= 0 && years <= 5;
            case '5–10 yrs':
              return years > 5 && years <= 10;
            case '10–20 yrs':
              return years > 10 && years <= 20;
            case '20+ yrs':
              return years > 20;
            default:
              return false;
          }
        }

        filteredProperties = filteredProperties.where((feature) {
          final years = parseBuildingAgeYears(feature.metadata);
          if (years == null) {
            // If backend stores the same label, allow exact match.
            final rawLabel = _getMetadataValue(
              feature.metadata,
              const <String>['buildingAgeLabel', 'building_age_label'],
            );
            if (rawLabel == null) return false;
            return rawLabel.trim() == buildingAge;
          }
          return matchesAgeBucket(years, buildingAge);
        }).toList(growable: false);
        didFilter = true;
      }
    }

    if (type == 'ApartmentFlat') {
      final minBedrooms = _selectedApartmentMinBedrooms;
      if (minBedrooms != null) {
        filteredProperties = filteredProperties.where((feature) {
          final bedrooms = parseIntFromMetadata(
            feature.metadata,
            const <String>[
              'bedrooms',
              'bedroom',
              'bhk',
              'noOfBedrooms',
              'no_of_bedrooms',
            ],
          );
          if (bedrooms == null) return false;
          return bedrooms >= minBedrooms;
        }).toList(growable: false);
        didFilter = true;
      }

      final carParking = _selectedApartmentCarParking;
      if (carParking == true) {
        filteredProperties = filteredProperties.where((feature) {
          final count = parseIntFromMetadata(
            feature.metadata,
            const <String>[
              'carParkingCount',
              'car_parking_count',
              'parkingCount',
              'parking_count',
              'carParking',
              'car_parking',
              'parking',
              'hasParking',
              'has_parking',
            ],
          );
          if (count != null) {
            return count > 0;
          }

          final raw = _getMetadataValue(
            feature.metadata,
            const <String>[
              'carParking',
              'car_parking',
              'parking',
              'carParkingAvailable',
              'car_parking_available',
              'hasParking',
              'has_parking',
            ],
          );
          if (raw == null) return false;
          return parseBoolTruthy(raw);
        }).toList(growable: false);
        didFilter = true;
      }

      final buildingAge = _selectedApartmentBuildingAge?.trim();
      if (buildingAge != null && buildingAge.isNotEmpty) {
        bool matchesAgeBucket(int years, String bucket) {
          switch (bucket) {
            case 'New':
              return years <= 1;
            case '0–5 yrs':
              return years >= 0 && years <= 5;
            case '5–10 yrs':
              return years > 5 && years <= 10;
            case '10–20 yrs':
              return years > 10 && years <= 20;
            case '20+ yrs':
              return years > 20;
            default:
              return false;
          }
        }

        filteredProperties = filteredProperties.where((feature) {
          final years = parseBuildingAgeYears(feature.metadata);
          if (years == null) {
            final rawLabel = _getMetadataValue(
              feature.metadata,
              const <String>['buildingAgeLabel', 'building_age_label'],
            );
            if (rawLabel == null) return false;
            return rawLabel.trim() == buildingAge;
          }
          return matchesAgeBucket(years, buildingAge);
        }).toList(growable: false);
        didFilter = true;
      }

      final selectedFloor = _selectedApartmentFloor?.trim();
      if (selectedFloor != null && selectedFloor.isNotEmpty) {
        filteredProperties = filteredProperties.where((feature) {
          final floor = parseIntFromMetadata(
            feature.metadata,
            const <String>[
              'floor',
              'apartmentFloor',
              'apartment_floor',
              'propertyFloor',
              'property_floor',
            ],
          );
          if (floor == null) return false;

          if (selectedFloor == 'Ground') {
            // Be lenient: some backends use 0 for ground, some use 1.
            return floor == 0 || floor == 1;
          }

          if (selectedFloor == 'Top Floor') {
            final totalFloors = parseIntFromMetadata(
              feature.metadata,
              const <String>[
                'totalFloors',
                'total_floors',
                'floorsInBuilding',
                'floors_in_building',
              ],
            );
            if (totalFloors == null) return false;
            // Handle both 1-based and 0-based floor encodings.
            if (floor == totalFloors) return true;
            if (floor == totalFloors - 1) return true;
            return false;
          }

          if (selectedFloor == '5+') {
            return floor >= 5;
          }

          final exact = int.tryParse(selectedFloor);
          if (exact != null) {
            return floor == exact;
          }

          return false;
        }).toList(growable: false);
        didFilter = true;
      }

      final totalFloorsBucket = _selectedApartmentTotalFloors?.trim();
      if (totalFloorsBucket != null && totalFloorsBucket.isNotEmpty) {
        final normalized = totalFloorsBucket.replaceAll('–', '-');

        int? minAllowed;
        int? maxAllowed;
        if (normalized.startsWith('Low-rise')) {
          minAllowed = 1;
          maxAllowed = 3;
        } else if (normalized.startsWith('Mid-rise')) {
          minAllowed = 4;
          maxAllowed = 7;
        } else if (normalized.startsWith('High-rise')) {
          minAllowed = 8;
          maxAllowed = null;
        }

        if (minAllowed != null) {
          final int minAllowedValue = minAllowed;
          final int? maxAllowedValue = maxAllowed;
          filteredProperties = filteredProperties.where((feature) {
            final totalFloors = parseIntFromMetadata(
              feature.metadata,
              const <String>[
                'totalFloors',
                'total_floors',
                'floorsInBuilding',
                'floors_in_building',
              ],
            );
            if (totalFloors == null) return false;
            if (totalFloors < minAllowedValue) return false;
            if (maxAllowedValue != null && totalFloors > maxAllowedValue) {
              return false;
            }
            return true;
          }).toList(growable: false);
          didFilter = true;
        }
      }
    }

    if (_isPriceFilterEligiblePropertyType(type)) {
      final range = _selectedPriceRange;
      if (range != null) {
        final min = range.minRupees;
        final max = range.maxRupees;

        final priceFiltered = <MapPropertyFeature>[];
        for (final feature in filteredProperties) {
          final rawPrice = _getMetadataValue(
            feature.metadata,
            const <String>[
              'price',
              'listingPrice',
              'salePrice',
              'amount',
              // Common alternates (seen across different sources/backends).
              'totalPrice',
              'total_price',
              'plotPrice',
              'plot_price',
              'priceRupees',
              'price_rupees',
              'amountRupees',
              'amount_rupees',
              'priceInRupees',
              'price_in_rupees',
            ],
          );
          final rupees =
              rawPrice == null ? null : _parsePriceToRupees(rawPrice);
          if (rupees == null) {
            continue;
          }
          if (min != null && rupees < min) continue;
          if (max != null && rupees > max) continue;
          priceFiltered.add(feature);
        }

        filteredProperties = priceFiltered.toList(growable: false);
        didFilter = true;
      }
    }

    if (!didFilter) {
      return response;
    }

    final allowedIds = filteredProperties
        .map((p) => p.propertyId.trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    final filteredPlots = response.plots.where((plot) {
      final id = plot.individualPlotsId?.trim();
      if (id == null || id.isEmpty) return true;
      return allowedIds.contains(id);
    }).toList(growable: false);

    final filteredRoads = response.roads.where((road) {
      final ip = road.individualPlotsId?.trim();
      if (ip != null && ip.isNotEmpty) {
        return allowedIds.contains(ip);
      }
      final land = road.landId?.trim();
      if (land != null && land.isNotEmpty) {
        return allowedIds.contains(land);
      }
      final comm = road.commercialSpaceId?.trim();
      if (comm != null && comm.isNotEmpty) {
        return allowedIds.contains(comm);
      }
      return true;
    }).toList(growable: false);

    return MapViewportResponse(
      detailLevel: response.detailLevel,
      properties: filteredProperties.toList(growable: false),
      plots: filteredPlots,
      roads: filteredRoads,
      amenities: response.amenities,
    );
  }

  _ViewportRenderCacheEntry _renderViewport({
    required MapViewportResponse response,
    required double zoom,
  }) {
    final propertyByFeatureId = <String, MapPropertyFeature>{};
    final ownedLayoutIds = <String>{};
    final nextLayoutPolygons = <Polygon>{};
    final nextPropertyPolygons = <Polygon>{};
    final styleZoom = zoom;

    var layoutFeatureCount = 0;
    var layoutPolygonCount = 0;

    for (final feature in response.properties) {
      final id = feature.featureId.trim();
      if (id.isNotEmpty) {
        propertyByFeatureId[id] = feature;
      }

      if (feature.propertyType.trim() == 'Layout' &&
          feature.isOwnedByCurrentUser) {
        final layoutId = feature.featureId.trim();
        if (layoutId.isNotEmpty) {
          ownedLayoutIds.add(layoutId);
        }
      }

      final normalizedType = feature.propertyType.trim().toLowerCase();
      final isLayout = normalizedType == 'layout';
      if (isLayout) {
        layoutFeatureCount++;
        final fillOpacity =
            zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
        final polygons = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          layoutPolygonCount++;
          nextLayoutPolygons.add(
            Polygon(
              polygonId: PolygonId('layout:${feature.featureId}:$i'),
              points: points,
              strokeWidth: _layoutBoundaryStrokeWidth,
              strokeColor: _layoutBoundaryStroke
                  .withOpacity(_layoutBoundaryStrokeOpacity),
              fillColor: _layoutBoundaryFill.withOpacity(fillOpacity),
              consumeTapEvents: false,
              zIndex: _propertyStyleForType('Layout').zIndex,
            ),
          );
        }
      } else {
        final polygons = GeoJson.tryParsePolygons(feature.boundaryGeoJson);
        if (polygons.isEmpty) continue;

        final style = _propertyStyleForType(feature.propertyType);
        final isDetailedPlotGroup =
            feature.propertyType.trim() == 'IndividualPlots' &&
                response.detailLevel == MapDetailLevel.detailed;

        final strokeOpacity =
            isDetailedPlotGroup ? 0.92 : _propertyStrokeOpacity;
        final fillOpacity = isDetailedPlotGroup
            ? 0.0
            : _adjustFillOpacityForZoom(styleZoom, _propertyBaseFillOpacity);
        final strokeWidth = isDetailedPlotGroup
            ? _propertyBaseStrokeWidth
            : _adjustStrokeWidthForZoom(styleZoom, _propertyBaseStrokeWidth);

        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextPropertyPolygons.add(
            Polygon(
              polygonId: PolygonId(
                'prop:${feature.propertyType}:${feature.featureId}:$i',
              ),
              points: points,
              strokeWidth: strokeWidth,
              strokeColor: style.stroke.withOpacity(strokeOpacity),
              fillColor: style.fill.withOpacity(fillOpacity),
              consumeTapEvents: false,
              zIndex: style.zIndex,
            ),
          );
        }
      }
    }

    final shouldShowPolygons = zoom >= _minPlotPolygonZoom;
    final shouldShowRoads = zoom >= _minRoadOverlayZoom;
    final nextPlotPolygons = <Polygon>{};
    final nextAmenityPolygons = <Polygon>{};
    final nextRoadPolygons = <Polygon>{};
    final nextRoadPolylines = <Polyline>{};

    if (shouldShowPolygons) {
      for (final plot in response.plots) {
        final polygons = GeoJson.tryParsePolygons(plot.boundaryGeoJson);
        if (polygons.isEmpty) continue;
        final kind = _plotElementKind(plot);
        final isSold = plot.layoutId != null && _isSoldPlot(plot);
        final isBooked =
            !isSold && plot.layoutId != null && _isBookedPlot(plot);

        Color stroke;
        Color fill;
        int strokeWidth;
        double strokeOpacity;
        double fillOpacity;
        int zIndex;

        if (kind == 'road') {
          stroke = _roadStroke;
          fill = _roadFill;
          strokeWidth = _roadStrokeWidth;
          strokeOpacity = _roadStrokeOpacity;
          fillOpacity = _roadFillOpacity;
          zIndex = 58;
        } else if (kind == 'boundary') {
          stroke = _layoutBoundaryStroke;
          fill = _layoutBoundaryFill;
          strokeWidth = _layoutBoundaryStrokeWidth;
          strokeOpacity = _layoutBoundaryStrokeOpacity;
          fillOpacity =
              zoom >= _layoutFillHideZoom ? 0.0 : _layoutBoundaryFillOpacity;
          zIndex = 45;
        } else if (isSold) {
          stroke = _soldPlotStroke;
          fill = _soldPlotFill;
          strokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
          strokeOpacity = _soldPlotStrokeOpacity;
          fillOpacity = _soldPlotFillOpacity;
          zIndex = 60;
        } else if (isBooked) {
          stroke = _bookedPlotStroke;
          fill = _bookedPlotFill;
          strokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
          strokeOpacity = _bookedPlotStrokeOpacity;
          fillOpacity = _bookedPlotFillOpacity;
          zIndex = 60;
        } else {
          stroke = _plotStroke;
          fill = _plotFill;
          strokeWidth = _bumpPlotStrokeWidthForHighZoom(zoom, _plotStrokeWidth);
          strokeOpacity = _plotStrokeOpacity;
          fillOpacity = _plotFillOpacity;
          zIndex = 60;
        }

        // If this plot is focused from a deep link, apply highlight style.
        final focusedId = _focusedPlotIdFromDeepLink;
        final isFocused = focusedId != null && focusedId == plot.plotId;
        if (isFocused) {
          stroke = Colors.white;
          strokeWidth = 4;
          zIndex = 9999;
        }

        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextPlotPolygons.add(
            Polygon(
              polygonId: PolygonId('plot:${plot.plotId}:$i'),
              points: points,
              strokeWidth: strokeWidth,
              strokeColor: stroke.withOpacity(strokeOpacity),
              fillColor: fill.withOpacity(fillOpacity),
              consumeTapEvents: true,
              zIndex: zIndex,
              onTap: () => _handlePlotTapped(plot),
            ),
          );
        }
      }

      for (final amenity in response.amenities) {
        final polygons = GeoJson.tryParsePolygons(amenity.boundaryGeoJson);
        for (var i = 0; i < polygons.length; i++) {
          final points = polygons[i];
          if (points.length < 3) continue;
          nextAmenityPolygons.add(
            Polygon(
              polygonId: PolygonId('amenity:${amenity.amenityId}:$i'),
              points: points,
              strokeWidth: _amenityStrokeWidth,
              strokeColor: _amenityStroke.withOpacity(_amenityStrokeOpacity),
              fillColor: _amenityFill.withOpacity(_amenityFillOpacity),
              consumeTapEvents: false,
              zIndex: 64,
            ),
          );
        }
      }
    }

    if (shouldShowRoads) {
      for (final road in response.roads) {
        final lines = GeoJson.tryParseLineStrings(road.roadGeoJson);

        if (lines.isNotEmpty) {
          for (var i = 0; i < lines.length; i++) {
            final points = lines[i];
            if (points.length < 2) continue;

            // Rough width scaling: keep readable at common zooms.
            final width = (road.widthInFeet ?? 12) >= 20
                ? _roadLineStrokeWidth + 2
                : _roadLineStrokeWidth;
            nextRoadPolylines.add(
              Polyline(
                polylineId: PolylineId('road:${road.roadId}:$i'),
                points: points,
                width: width,
                color: _roadLineStroke.withOpacity(_roadLineStrokeOpacity),
                geodesic: true,
              ),
            );
          }
          continue;
        }

        // Fallback: some datasets may encode roads as Polygon/MultiPolygon.
        final roadPolygons = GeoJson.tryParsePolygons(road.roadGeoJson);
        for (var i = 0; i < roadPolygons.length; i++) {
          final points = roadPolygons[i];
          if (points.length < 3) continue;
          nextRoadPolygons.add(
            Polygon(
              polygonId: PolygonId('roadpoly:${road.roadId}:$i'),
              points: points,
              strokeWidth: _roadStrokeWidth,
              strokeColor: _roadStroke.withOpacity(_roadStrokeOpacity),
              fillColor: _roadFill.withOpacity(_roadFillOpacity),
              consumeTapEvents: false,
            ),
          );
        }
      }
    }

    assert(() {
      if (layoutFeatureCount > 0 && layoutPolygonCount == 0) {
        debugPrint(
          'Viewport: found $layoutFeatureCount Layout properties but parsed 0 polygons. boundaryGeoJson may be empty/unsupported.',
        );
      }
      return true;
    }());

    return _ViewportRenderCacheEntry(
      markers: const <Marker>{},
      plotLabelMarkers: const <Marker>{},
      roadLabelMarkers: const <Marker>{},
      amenityLabelMarkers: const <Marker>{},
      layoutPolygons: Set<Polygon>.unmodifiable(nextLayoutPolygons),
      propertyPolygons: Set<Polygon>.unmodifiable(nextPropertyPolygons),
      plotPolygons: Set<Polygon>.unmodifiable(nextPlotPolygons),
      amenityPolygons: Set<Polygon>.unmodifiable(nextAmenityPolygons),
      roadPolygons: Set<Polygon>.unmodifiable(nextRoadPolygons),
      roadPolylines: Set<Polyline>.unmodifiable(nextRoadPolylines),
      ownedLayoutIds: Set<String>.unmodifiable(ownedLayoutIds),
      propertyByFeatureId:
          Map<String, MapPropertyFeature>.unmodifiable(propertyByFeatureId),
    );
  }

  String _buildViewportSignature(
    LatLngBounds bounds,
    double zoom,
    List<String> propertyTypes,
    bool isAuthenticated, {
    String? clientFilters,
  }) {
    final minLat = bounds.southwest.latitude < bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final maxLat = bounds.southwest.latitude > bounds.northeast.latitude
        ? bounds.southwest.latitude
        : bounds.northeast.latitude;
    final minLng = bounds.southwest.longitude < bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;
    final maxLng = bounds.southwest.longitude > bounds.northeast.longitude
        ? bounds.southwest.longitude
        : bounds.northeast.longitude;

    final filterSignature = propertyTypes
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return [
      minLat.toStringAsFixed(5),
      maxLat.toStringAsFixed(5),
      minLng.toStringAsFixed(5),
      maxLng.toStringAsFixed(5),
      zoom.toStringAsFixed(2),
      filterSignature.join(','),
      (clientFilters ?? '').trim(),
      isAuthenticated ? 'auth' : 'anon',
    ].join('|');
  }
}
