part of '../home_map_screen.dart';

extension _HomeMapFiltersFixed on _HomeMapScreenState {
  bool _isPriceFilterEligiblePropertyType(String? type) {
    final t = type?.trim();
    if (t == null || t.isEmpty) return false;
    return const <String>{
      'IndependentHouse',
      'CommercialSpace',
      'Land',
      'ApartmentFlat',
      'IndividualPlots',
    }.contains(t);
  }

  String _clientFilterSignature() {
    final parts = <String>[];

    final listingType = _selectedListingType?.trim();
    if (listingType != null && listingType.isNotEmpty) {
      parts.add('listing:$listingType');
    }

    final type = _selectedPropertyType?.trim();
    if (type == null || type.isEmpty) {
      return parts.join('|');
    }
    parts.add('type:$type');

    if (type == 'CommercialSpace') {
      final suitableFor = _selectedCommercialSuitableFor?.trim();
      if (suitableFor != null && suitableFor.isNotEmpty) {
        parts.add('suitableFor:$suitableFor');
      }

      final area = _selectedAreaRange;
      if (area != null) {
        parts.add('area:${area.minSqft}-${area.maxSqft}');
      }
    }

    if (type == 'IndependentHouse') {
      final minBedrooms = _selectedMinBedrooms;
      if (minBedrooms != null) {
        parts.add('bedroomsMin:$minBedrooms');
      }

      final carParking = _selectedCarParking;
      if (carParking != null) {
        parts.add('carParking:$carParking');
      }

      final minFloors = _selectedMinFloors;
      if (minFloors != null) {
        parts.add('floorsMin:$minFloors');
      }

      final buildingAge = _selectedBuildingAge?.trim();
      if (buildingAge != null && buildingAge.isNotEmpty) {
        parts.add('buildingAge:$buildingAge');
      }
    }

    if (_isPriceFilterEligiblePropertyType(type)) {
      final f = _selectedPriceRange;
      if (f != null) {
        parts.add('price:${f.minRupees ?? ''}-${f.maxRupees ?? ''}');
      }
    }

    if (type == 'Land') {
      final landType = _selectedLandType?.trim();
      if (landType != null && landType.isNotEmpty) {
        parts.add('land:$landType');
      }
    }

    return parts.join('|');
  }

  Future<void> _openFilters(Rect panelAnchorRect, Rect arrowAnchorRect) async {
    if (!mounted) return;

    final initialType = _selectedPropertyType;
    final initialListingType = _selectedListingType;
    final initialPrice = _selectedPriceRange;
    final initialLandType = _selectedLandType;
    final initialSuitableFor = _selectedCommercialSuitableFor;
    final initialAreaRange = _selectedAreaRange;
    final initialMinBedrooms = _selectedMinBedrooms;
    final initialCarParking = _selectedCarParking;
    final initialMinFloors = _selectedMinFloors;
    final initialBuildingAge = _selectedBuildingAge;

    final result = await showGeneralDialog<_HomeMapFiltersDialogResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, _, __) {
        final media = MediaQuery.of(context);
        final size = media.size;
        const horizontalPadding = 16.0;
        const arrowWidth = 18.0;
        const arrowHeight = 10.0;
        const popupGap = 0.0;
        const popupOverlapIntoAnchor = 34.0;
        const arrowOverlapIntoPopup = 3.0;

        final safeTop = media.padding.top;
        final popupTopRaw =
            panelAnchorRect.bottom + popupGap - popupOverlapIntoAnchor;
        final popupTop = popupTopRaw < safeTop + 4 ? safeTop + 4 : popupTopRaw;

        final popupWidth = size.width - (horizontalPadding * 2);
        final arrowAnchorCenterX =
            arrowAnchorRect.left + (arrowAnchorRect.width / 2);
        const arrowLeftMin = horizontalPadding + 12;
        final arrowLeftMax = horizontalPadding + popupWidth - 12 - arrowWidth;
        final arrowLeftRaw = arrowAnchorCenterX - (arrowWidth / 2);
        final arrowLeft = arrowLeftRaw < arrowLeftMin
            ? arrowLeftMin
            : (arrowLeftRaw > arrowLeftMax ? arrowLeftMax : arrowLeftRaw);

        var localType = initialType;
        var localListingType = initialListingType;
        var localPrice = initialPrice;
        var localLandType = initialLandType;
        var localSuitableFor = initialSuitableFor;
        var localAreaRange = initialAreaRange;
        var localMinBedrooms = initialMinBedrooms;
        var localCarParking = initialCarParking;
        var localMinFloors = initialMinFloors;
        var localBuildingAge = initialBuildingAge;
        var localShowIndependentMoreFilters = (initialMinFloors != null ||
            (initialBuildingAge?.trim().isNotEmpty ?? false));

        if (localLandType?.trim() == 'Any') {
          localLandType = null;
        }

        const sectionTitleStyle = TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        );

        const chipLabelStyle = TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        );

        const chipLabelPadding = EdgeInsets.symmetric(horizontal: 8);
        const chipVisualDensity = VisualDensity.compact;
        const chipRadius = 6.0;
        const wrapSpacing = 6.0;
        const wrapRunSpacing = 6.0;

        const landTypeOptions = <String>[
          'Any',
          'Residential',
          'Commercial',
          'Agricultural',
        ];

        final scrollController = ScrollController();
        final independentMoreFiltersAnchorKey = GlobalKey();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final showPrice = _isPriceFilterEligiblePropertyType(localType) &&
                (localType?.trim() != 'Layout');
            if (!showPrice) {
              localPrice = null;
            }

            final showLandType = (localType?.trim() == 'Land');
            if (!showLandType) {
              localLandType = null;
            }

            final showCommercialFilters =
                (localType?.trim() == 'CommercialSpace');
            if (!showCommercialFilters) {
              localSuitableFor = null;
              localAreaRange = null;
            }

            final showIndependentHouseFilters =
                (localType?.trim() == 'IndependentHouse');
            if (!showIndependentHouseFilters) {
              localMinBedrooms = null;
              localCarParking = null;
              localMinFloors = null;
              localBuildingAge = null;
              localShowIndependentMoreFilters = false;
            }

            const areaMinSqft = 200.0;
            const areaMaxSqft = 10000.0;
            final areaValues = localAreaRange == null
                ? const RangeValues(areaMinSqft, areaMaxSqft)
                : RangeValues(
                    localAreaRange!.minSqft.toDouble().clamp(
                          areaMinSqft,
                          areaMaxSqft,
                        ),
                    localAreaRange!.maxSqft.toDouble().clamp(
                          areaMinSqft,
                          areaMaxSqft,
                        ),
                  );

            return GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: popupTop,
                        left: horizontalPadding,
                        right: horizontalPadding,
                        child: GestureDetector(
                          onTap: () {},
                          child: Material(
                            elevation: 10,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            color: Colors.white,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: size.height * 0.72,
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 6, 16, 14),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: CustomScrollView(
                                        controller: scrollController,
                                        primary: false,
                                        shrinkWrap: true,
                                        slivers: [
                                          SliverToBoxAdapter(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                          left: 4),
                                                      child: Text(
                                                        'Listing Type',
                                                        style:
                                                            sectionTitleStyle,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 4),
                                                      child: TextButton(
                                                        style: TextButton
                                                            .styleFrom(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          minimumSize:
                                                              const Size(
                                                                  32, 32),
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                        ),
                                                        onPressed: () {
                                                          Navigator.of(context)
                                                              .pop(
                                                            (
                                                              type: null,
                                                              listingType:
                                                                  'Sell',
                                                              price: null,
                                                              landType: null,
                                                              suitableFor: null,
                                                              areaRange: null,
                                                              minBedrooms: null,
                                                              carParking: null,
                                                              minFloors: null,
                                                              buildingAge: null,
                                                            ),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'CLEAR',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF0FAD97),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Wrap(
                                                  spacing: wrapSpacing,
                                                  runSpacing: wrapRunSpacing,
                                                  children: [
                                                    for (final option
                                                        in const <({
                                                      String id,
                                                      String label
                                                    })>[
                                                      (
                                                        id: 'Sell',
                                                        label: 'Buy'
                                                      ),
                                                      (
                                                        id: 'Rent',
                                                        label: 'Rent'
                                                      ),
                                                      (
                                                        id: 'Lease',
                                                        label: 'Lease'
                                                      ),
                                                    ])
                                                      ChoiceChip(
                                                        label:
                                                            Text(option.label),
                                                        selected:
                                                            (localListingType ==
                                                                option.id),
                                                        showCheckmark: false,
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        visualDensity:
                                                            chipVisualDensity,
                                                        labelPadding:
                                                            chipLabelPadding,
                                                        selectedColor:
                                                            const Color(
                                                                0xFF0FAD97),
                                                        backgroundColor:
                                                            const Color(
                                                                0xFFF1F5F9),
                                                        side: const BorderSide(
                                                            color: Color(
                                                                0xFFCBD5E1)),
                                                        labelStyle: TextStyle(
                                                          fontSize:
                                                              chipLabelStyle
                                                                  .fontSize,
                                                          fontWeight:
                                                              chipLabelStyle
                                                                  .fontWeight,
                                                          color:
                                                              (localListingType ==
                                                                      option.id)
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A),
                                                        ),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      chipRadius),
                                                        ),
                                                        onSelected: (_) {
                                                          setModalState(() {
                                                            localListingType =
                                                                localListingType ==
                                                                        option
                                                                            .id
                                                                    ? null
                                                                    : option.id;
                                                          });
                                                        },
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                const Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: Color(0xFFE2E8F0),
                                                ),
                                                const SizedBox(height: 10),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 44),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text(
                                                            'Property Type',
                                                            style:
                                                                sectionTitleStyle),
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing:
                                                            wrapRunSpacing,
                                                        children: [
                                                          for (final option
                                                              in _propertyTypeOptions)
                                                            ChoiceChip(
                                                              label: Text(
                                                                  option.label),
                                                              selected:
                                                                  (localType ==
                                                                      option
                                                                          .id),
                                                              showCheckmark:
                                                                  false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFCBD5E1)),
                                                              labelStyle:
                                                                  TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle
                                                                        .fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle
                                                                        .fontWeight,
                                                                color: (localType ==
                                                                        option
                                                                            .id)
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFF0F172A),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            chipRadius),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localType =
                                                                      option.id;
                                                                  if (!_isPriceFilterEligiblePropertyType(
                                                                          localType) ||
                                                                      localType
                                                                              ?.trim() ==
                                                                          'Layout') {
                                                                    localPrice =
                                                                        null;
                                                                  }
                                                                  if (localType
                                                                          ?.trim() !=
                                                                      'Land') {
                                                                    localLandType =
                                                                        null;
                                                                  }
                                                                  if (localType
                                                                          ?.trim() !=
                                                                      'CommercialSpace') {
                                                                    localSuitableFor =
                                                                        null;
                                                                    localAreaRange =
                                                                        null;
                                                                  }
                                                                  if (localType
                                                                          ?.trim() !=
                                                                      'IndependentHouse') {
                                                                    localMinBedrooms =
                                                                        null;
                                                                    localCarParking =
                                                                        null;
                                                                    localMinFloors =
                                                                        null;
                                                                    localBuildingAge =
                                                                        null;
                                                                    localShowIndependentMoreFilters =
                                                                        false;
                                                                  }
                                                                });
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (showPrice &&
                                                    showCommercialFilters) ...[
                                                  const SizedBox(height: 12),
                                                  const Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: Color(0xFFE2E8F0)),
                                                  const SizedBox(height: 10),
                                                ],
                                                if (showCommercialFilters)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                right: 44),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Padding(
                                                              padding: EdgeInsets
                                                                  .only(
                                                                      left: 4),
                                                              child: Text(
                                                                  'Suitable For',
                                                                  style:
                                                                      sectionTitleStyle),
                                                            ),
                                                            const SizedBox(
                                                                height: 10),
                                                            Wrap(
                                                              spacing:
                                                                  wrapSpacing,
                                                              runSpacing:
                                                                  wrapRunSpacing,
                                                              children: [
                                                                ChoiceChip(
                                                                  label: const Text(
                                                                      'All Types'),
                                                                  selected:
                                                                      localSuitableFor ==
                                                                          null,
                                                                  showCheckmark:
                                                                      false,
                                                                  materialTapTargetSize:
                                                                      MaterialTapTargetSize
                                                                          .shrinkWrap,
                                                                  visualDensity:
                                                                      chipVisualDensity,
                                                                  labelPadding:
                                                                      chipLabelPadding,
                                                                  selectedColor:
                                                                      const Color(
                                                                          0xFF0FAD97),
                                                                  backgroundColor:
                                                                      const Color(
                                                                          0xFFF1F5F9),
                                                                  side: const BorderSide(
                                                                      color: Color(
                                                                          0xFFCBD5E1)),
                                                                  labelStyle:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        chipLabelStyle
                                                                            .fontSize,
                                                                    fontWeight:
                                                                        chipLabelStyle
                                                                            .fontWeight,
                                                                    color: localSuitableFor ==
                                                                            null
                                                                        ? Colors
                                                                            .white
                                                                        : const Color(
                                                                            0xFF0F172A),
                                                                  ),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            chipRadius),
                                                                  ),
                                                                  onSelected:
                                                                      (_) {
                                                                    setModalState(
                                                                        () {
                                                                      localSuitableFor =
                                                                          null;
                                                                    });
                                                                  },
                                                                ),
                                                                for (final option
                                                                    in _commercialSuitableForOptions)
                                                                  ChoiceChip(
                                                                    label: Text(
                                                                        option),
                                                                    selected:
                                                                        localSuitableFor ==
                                                                            option,
                                                                    showCheckmark:
                                                                        false,
                                                                    materialTapTargetSize:
                                                                        MaterialTapTargetSize
                                                                            .shrinkWrap,
                                                                    visualDensity:
                                                                        chipVisualDensity,
                                                                    labelPadding:
                                                                        chipLabelPadding,
                                                                    selectedColor:
                                                                        const Color(
                                                                            0xFF0FAD97),
                                                                    backgroundColor:
                                                                        const Color(
                                                                            0xFFF1F5F9),
                                                                    side: const BorderSide(
                                                                        color: Color(
                                                                            0xFFCBD5E1)),
                                                                    labelStyle:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          chipLabelStyle
                                                                              .fontSize,
                                                                      fontWeight:
                                                                          chipLabelStyle
                                                                              .fontWeight,
                                                                      color: localSuitableFor ==
                                                                              option
                                                                          ? Colors
                                                                              .white
                                                                          : const Color(
                                                                              0xFF0F172A),
                                                                    ),
                                                                    shape:
                                                                        RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              chipRadius),
                                                                    ),
                                                                    onSelected:
                                                                        (_) {
                                                                      setModalState(
                                                                          () {
                                                                        localSuitableFor = localSuitableFor ==
                                                                                option
                                                                            ? null
                                                                            : option;
                                                                      });
                                                                    },
                                                                  ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      const Divider(
                                                          height: 1,
                                                          thickness: 1,
                                                          color: Color(
                                                              0xFFE2E8F0)),
                                                      const SizedBox(
                                                          height: 10),
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text(
                                                            'Area (sq ft)',
                                                            style:
                                                                sectionTitleStyle),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 4,
                                                                right: 8),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                              '${areaValues.start.round()} sq ft',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                    0xFF334155),
                                                              ),
                                                            ),
                                                            Text(
                                                              areaValues.end >=
                                                                      areaMaxSqft
                                                                  ? '10,000+ sq ft'
                                                                  : '${areaValues.end.round()} sq ft',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Color(
                                                                    0xFF334155),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 8),
                                                        child: RangeSlider(
                                                          values: areaValues,
                                                          min: areaMinSqft,
                                                          max: areaMaxSqft,
                                                          divisions: 98,
                                                          activeColor:
                                                              const Color(
                                                                  0xFF0FAD97),
                                                          inactiveColor:
                                                              const Color(
                                                                  0xFFE2E8F0),
                                                          labels: RangeLabels(
                                                            '${areaValues.start.round()} sq ft',
                                                            areaValues.end >=
                                                                    areaMaxSqft
                                                                ? '10,000+ sq ft'
                                                                : '${areaValues.end.round()} sq ft',
                                                          ),
                                                          onChanged: (v) {
                                                            setModalState(() {
                                                              final start = v
                                                                  .start
                                                                  .round();
                                                              final end =
                                                                  v.end.round();
                                                              final isAny = start <=
                                                                      areaMinSqft
                                                                          .round() &&
                                                                  end >=
                                                                      areaMaxSqft
                                                                          .round();
                                                              localAreaRange = isAny
                                                                  ? null
                                                                  : _AreaRangeFilter(
                                                                      minSqft:
                                                                          start,
                                                                      maxSqft:
                                                                          end,
                                                                    );
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                if (showPrice) ...[
                                                  const SizedBox(height: 12),
                                                  const Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: Color(0xFFE2E8F0)),
                                                  const SizedBox(height: 10),
                                                ],
                                                if (showPrice)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text('Price',
                                                            style:
                                                                sectionTitleStyle),
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing:
                                                            wrapRunSpacing,
                                                        children: [
                                                          for (final option
                                                              in _priceRangeOptions)
                                                            ChoiceChip(
                                                              label: Text(
                                                                  option.label),
                                                              selected: (localPrice ==
                                                                      null
                                                                  ? option ==
                                                                      _anyPriceRange
                                                                  : option.label ==
                                                                      localPrice!
                                                                          .label),
                                                              showCheckmark:
                                                                  false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFCBD5E1)),
                                                              labelStyle:
                                                                  TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle
                                                                        .fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle
                                                                        .fontWeight,
                                                                color: (localPrice == null
                                                                        ? option ==
                                                                            _anyPriceRange
                                                                        : option.label ==
                                                                            localPrice!
                                                                                .label)
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFF0F172A),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            chipRadius),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localPrice =
                                                                      option ==
                                                                              _anyPriceRange
                                                                          ? null
                                                                          : option;
                                                                });
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                if (showPrice &&
                                                    showIndependentHouseFilters) ...[
                                                  const SizedBox(height: 12),
                                                  const Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: Color(0xFFE2E8F0)),
                                                  const SizedBox(height: 10),
                                                ],
                                                if (showIndependentHouseFilters)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text('Bedrooms',
                                                            style:
                                                                sectionTitleStyle),
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing:
                                                            wrapRunSpacing,
                                                        children: [
                                                          ChoiceChip(
                                                            label: const Text(
                                                                'Any'),
                                                            selected:
                                                                localMinBedrooms ==
                                                                    null,
                                                            showCheckmark:
                                                                false,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            visualDensity:
                                                                chipVisualDensity,
                                                            labelPadding:
                                                                chipLabelPadding,
                                                            selectedColor:
                                                                const Color(
                                                                    0xFF0FAD97),
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFFF1F5F9),
                                                            side: const BorderSide(
                                                                color: Color(
                                                                    0xFFCBD5E1)),
                                                            labelStyle:
                                                                TextStyle(
                                                              fontSize:
                                                                  chipLabelStyle
                                                                      .fontSize,
                                                              fontWeight:
                                                                  chipLabelStyle
                                                                      .fontWeight,
                                                              color: localMinBedrooms ==
                                                                      null
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A),
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          chipRadius),
                                                            ),
                                                            onSelected: (_) {
                                                              setModalState(() {
                                                                localMinBedrooms =
                                                                    null;
                                                              });
                                                            },
                                                          ),
                                                          for (final option
                                                              in _bedroomMinOptions)
                                                            ChoiceChip(
                                                              label: Text(
                                                                  '$option+'),
                                                              selected:
                                                                  localMinBedrooms ==
                                                                      option,
                                                              showCheckmark:
                                                                  false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFCBD5E1)),
                                                              labelStyle:
                                                                  TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle
                                                                        .fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle
                                                                        .fontWeight,
                                                                color: localMinBedrooms ==
                                                                        option
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFF0F172A),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            chipRadius),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localMinBedrooms =
                                                                      localMinBedrooms ==
                                                                              option
                                                                          ? null
                                                                          : option;
                                                                });
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      const Divider(
                                                          height: 1,
                                                          thickness: 1,
                                                          color: Color(
                                                              0xFFE2E8F0)),
                                                      const SizedBox(
                                                          height: 10),
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text(
                                                            'Car Parking',
                                                            style:
                                                                sectionTitleStyle),
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing:
                                                            wrapRunSpacing,
                                                        children: [
                                                          ChoiceChip(
                                                            label: const Text(
                                                                'Any'),
                                                            selected:
                                                                localCarParking ==
                                                                    null,
                                                            showCheckmark:
                                                                false,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            visualDensity:
                                                                chipVisualDensity,
                                                            labelPadding:
                                                                chipLabelPadding,
                                                            selectedColor:
                                                                const Color(
                                                                    0xFF0FAD97),
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFFF1F5F9),
                                                            side: const BorderSide(
                                                                color: Color(
                                                                    0xFFCBD5E1)),
                                                            labelStyle:
                                                                TextStyle(
                                                              fontSize:
                                                                  chipLabelStyle
                                                                      .fontSize,
                                                              fontWeight:
                                                                  chipLabelStyle
                                                                      .fontWeight,
                                                              color: localCarParking ==
                                                                      null
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A),
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          chipRadius),
                                                            ),
                                                            onSelected: (_) {
                                                              setModalState(() {
                                                                localCarParking =
                                                                    null;
                                                              });
                                                            },
                                                          ),
                                                          ChoiceChip(
                                                            label: const Text(
                                                                'Available'),
                                                            selected:
                                                                localCarParking ==
                                                                    true,
                                                            showCheckmark:
                                                                false,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            visualDensity:
                                                                chipVisualDensity,
                                                            labelPadding:
                                                                chipLabelPadding,
                                                            selectedColor:
                                                                const Color(
                                                                    0xFF0FAD97),
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFFF1F5F9),
                                                            side: const BorderSide(
                                                                color: Color(
                                                                    0xFFCBD5E1)),
                                                            labelStyle:
                                                                TextStyle(
                                                              fontSize:
                                                                  chipLabelStyle
                                                                      .fontSize,
                                                              fontWeight:
                                                                  chipLabelStyle
                                                                      .fontWeight,
                                                              color: localCarParking ==
                                                                      true
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A),
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          chipRadius),
                                                            ),
                                                            onSelected: (_) {
                                                              setModalState(() {
                                                                localCarParking =
                                                                    localCarParking ==
                                                                            true
                                                                        ? null
                                                                        : true;
                                                              });
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      const Divider(
                                                          height: 1,
                                                          thickness: 1,
                                                          color: Color(
                                                              0xFFE2E8F0)),
                                                      const SizedBox(
                                                          height: 10),
                                                      InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        onTap: () {
                                                          final willOpen =
                                                              !localShowIndependentMoreFilters;
                                                          setModalState(() {
                                                            localShowIndependentMoreFilters =
                                                                !localShowIndependentMoreFilters;
                                                          });

                                                          if (willOpen) {
                                                            WidgetsBinding
                                                                .instance
                                                                .addPostFrameCallback(
                                                                    (_) {
                                                              final targetContext =
                                                                  independentMoreFiltersAnchorKey
                                                                      .currentContext;
                                                              if (targetContext ==
                                                                  null) {
                                                                return;
                                                              }

                                                              Scrollable
                                                                  .ensureVisible(
                                                                targetContext,
                                                                duration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            220),
                                                                curve: Curves
                                                                    .easeOut,
                                                                alignment: 0.08,
                                                              );
                                                            });
                                                          }
                                                        },
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .fromLTRB(
                                                                  4, 6, 4, 6),
                                                          child: Text.rich(
                                                            TextSpan(
                                                              children: [
                                                                const TextSpan(
                                                                  text:
                                                                      'More filters ',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Color(
                                                                        0xFF0F172A),
                                                                  ),
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      localShowIndependentMoreFilters
                                                                          ? '▲'
                                                                          : '▼',
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: Color(
                                                                        0xFF0F172A),
                                                                  ),
                                                                ),
                                                                const TextSpan(
                                                                  text:
                                                                      '  (Floors, Building Age)',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    color: Color(
                                                                        0xFF64748B),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      if (localShowIndependentMoreFilters) ...[
                                                        const SizedBox(
                                                            height: 10),
                                                        Padding(
                                                          key:
                                                              independentMoreFiltersAnchorKey,
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 4),
                                                          child: const Text(
                                                            'Floors',
                                                            style:
                                                                sectionTitleStyle,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Wrap(
                                                          spacing: wrapSpacing,
                                                          runSpacing:
                                                              wrapRunSpacing,
                                                          children: [
                                                            ChoiceChip(
                                                              label: const Text(
                                                                  'Any'),
                                                              selected:
                                                                  localMinFloors ==
                                                                      null,
                                                              showCheckmark:
                                                                  false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFCBD5E1)),
                                                              labelStyle:
                                                                  TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle
                                                                        .fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle
                                                                        .fontWeight,
                                                                color: localMinFloors ==
                                                                        null
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFF0F172A),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            chipRadius),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localMinFloors =
                                                                      null;
                                                                });
                                                              },
                                                            ),
                                                            for (final option
                                                                in _floorMinOptions)
                                                              ChoiceChip(
                                                                label: Text(
                                                                    '$option+'),
                                                                selected:
                                                                    localMinFloors ==
                                                                        option,
                                                                showCheckmark:
                                                                    false,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                    chipVisualDensity,
                                                                labelPadding:
                                                                    chipLabelPadding,
                                                                selectedColor:
                                                                    const Color(
                                                                        0xFF0FAD97),
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFFF1F5F9),
                                                                side: const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1)),
                                                                labelStyle:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      chipLabelStyle
                                                                          .fontSize,
                                                                  fontWeight:
                                                                      chipLabelStyle
                                                                          .fontWeight,
                                                                  color: localMinFloors ==
                                                                          option
                                                                      ? Colors
                                                                          .white
                                                                      : const Color(
                                                                          0xFF0F172A),
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              chipRadius),
                                                                ),
                                                                onSelected:
                                                                    (_) {
                                                                  setModalState(
                                                                      () {
                                                                    localMinFloors = localMinFloors ==
                                                                            option
                                                                        ? null
                                                                        : option;
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 12),
                                                        const Divider(
                                                          height: 1,
                                                          thickness: 1,
                                                          color:
                                                              Color(0xFFE2E8F0),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                  left: 4),
                                                          child: Text(
                                                              'Building Age',
                                                              style:
                                                                  sectionTitleStyle),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Wrap(
                                                          spacing: wrapSpacing,
                                                          runSpacing:
                                                              wrapRunSpacing,
                                                          children: [
                                                            ChoiceChip(
                                                              label: const Text(
                                                                  'Any'),
                                                              selected:
                                                                  localBuildingAge ==
                                                                      null,
                                                              showCheckmark:
                                                                  false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(
                                                                      0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                  color: Color(
                                                                      0xFFCBD5E1)),
                                                              labelStyle:
                                                                  TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle
                                                                        .fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle
                                                                        .fontWeight,
                                                                color: localBuildingAge ==
                                                                        null
                                                                    ? Colors
                                                                        .white
                                                                    : const Color(
                                                                        0xFF0F172A),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            chipRadius),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localBuildingAge =
                                                                      null;
                                                                });
                                                              },
                                                            ),
                                                            for (final option
                                                                in _buildingAgeOptions)
                                                              ChoiceChip(
                                                                label: Text(
                                                                    option),
                                                                selected:
                                                                    localBuildingAge ==
                                                                        option,
                                                                showCheckmark:
                                                                    false,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                    chipVisualDensity,
                                                                labelPadding:
                                                                    chipLabelPadding,
                                                                selectedColor:
                                                                    const Color(
                                                                        0xFF0FAD97),
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFFF1F5F9),
                                                                side: const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1)),
                                                                labelStyle:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      chipLabelStyle
                                                                          .fontSize,
                                                                  fontWeight:
                                                                      chipLabelStyle
                                                                          .fontWeight,
                                                                  color: localBuildingAge ==
                                                                          option
                                                                      ? Colors
                                                                          .white
                                                                      : const Color(
                                                                          0xFF0F172A),
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              chipRadius),
                                                                ),
                                                                onSelected:
                                                                    (_) {
                                                                  setModalState(
                                                                      () {
                                                                    localBuildingAge = localBuildingAge ==
                                                                            option
                                                                        ? null
                                                                        : option;
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                if (showPrice &&
                                                    showLandType) ...[
                                                  const SizedBox(height: 12),
                                                  const Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: Color(0xFFE2E8F0)),
                                                  const SizedBox(height: 10),
                                                ],
                                                if (showLandType)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 44),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                  left: 4),
                                                          child: Text(
                                                              'Land Type',
                                                              style:
                                                                  sectionTitleStyle),
                                                        ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Wrap(
                                                          spacing: wrapSpacing,
                                                          runSpacing:
                                                              wrapRunSpacing,
                                                          children: [
                                                            for (final option
                                                                in landTypeOptions)
                                                              ChoiceChip(
                                                                label: Text(
                                                                    option),
                                                                selected: option ==
                                                                        'Any'
                                                                    ? localLandType ==
                                                                        null
                                                                    : localLandType ==
                                                                        option,
                                                                showCheckmark:
                                                                    false,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                    chipVisualDensity,
                                                                labelPadding:
                                                                    chipLabelPadding,
                                                                selectedColor:
                                                                    const Color(
                                                                        0xFF0FAD97),
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFFF1F5F9),
                                                                side: const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1)),
                                                                labelStyle:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      chipLabelStyle
                                                                          .fontSize,
                                                                  fontWeight:
                                                                      chipLabelStyle
                                                                          .fontWeight,
                                                                  color: (option == 'Any'
                                                                          ? localLandType ==
                                                                              null
                                                                          : localLandType ==
                                                                              option)
                                                                      ? Colors
                                                                          .white
                                                                      : const Color(
                                                                          0xFF0F172A),
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              chipRadius),
                                                                ),
                                                                onSelected:
                                                                    (_) {
                                                                  setModalState(
                                                                      () {
                                                                    if (option ==
                                                                        'Any') {
                                                                      localLandType =
                                                                          null;
                                                                      return;
                                                                    }
                                                                    localLandType = localLandType ==
                                                                            option
                                                                        ? null
                                                                        : option;
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0xFFE2E8F0)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        SizedBox(
                                          height: 36,
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                  color: Color(0xFF0FAD97)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              minimumSize: const Size(0, 36),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                            child: const Text(
                                              'Close',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0FAD97),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        SizedBox(
                                          height: 36,
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF0FAD97),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              minimumSize: const Size(0, 36),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.of(context).pop(
                                                (
                                                  type: localType,
                                                  listingType: localListingType,
                                                  price: localPrice,
                                                  landType: localLandType,
                                                  suitableFor: localSuitableFor,
                                                  areaRange: localAreaRange,
                                                  minBedrooms: localMinBedrooms,
                                                  carParking: localCarParking,
                                                  minFloors: localMinFloors,
                                                  buildingAge: localBuildingAge,
                                                ),
                                              );
                                            },
                                            child: const Text(
                                              'Apply',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: popupTop - arrowHeight + arrowOverlapIntoPopup,
                        left: arrowLeft,
                        child: const IgnorePointer(
                          child: _FilterPopoverArrow(
                            width: arrowWidth,
                            height: arrowHeight,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.02),
              end: Offset.zero,
            ).animate(fade),
            child: child,
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    final nextType = result.type?.trim().isEmpty ?? true ? null : result.type;
    final nextListingType =
        result.listingType?.trim().isEmpty ?? true ? null : result.listingType;
    final nextPrice = result.price;
    final nextLandType =
        result.landType?.trim().isEmpty ?? true ? null : result.landType;
    final normalizedNextLandType =
        nextLandType?.trim() == 'Any' ? null : nextLandType;

    final nextSuitableFor =
        result.suitableFor?.trim().isEmpty ?? true ? null : result.suitableFor;
    final nextAreaRange = result.areaRange;

    final nextMinBedrooms = result.minBedrooms;
    final nextCarParking = result.carParking;
    final nextMinFloors = result.minFloors;
    final nextBuildingAge =
        result.buildingAge?.trim().isEmpty ?? true ? null : result.buildingAge;

    final normalizedNextType = nextType?.trim();
    final shouldAllowPrice =
        _isPriceFilterEligiblePropertyType(normalizedNextType) &&
            normalizedNextType != 'Layout';

    final shouldAllowLandType = normalizedNextType == 'Land';
    final shouldAllowCommercialFilters =
        normalizedNextType == 'CommercialSpace';
    final shouldAllowIndependentHouseFilters =
        normalizedNextType == 'IndependentHouse';

    _updateState(() {
      _selectedPropertyType = nextType;
      _selectedListingType = nextListingType;
      _selectedPriceRange = shouldAllowPrice ? nextPrice : null;
      _selectedLandType = shouldAllowLandType ? normalizedNextLandType : null;

      _selectedCommercialSuitableFor =
          shouldAllowCommercialFilters ? nextSuitableFor : null;
      _selectedAreaRange = shouldAllowCommercialFilters ? nextAreaRange : null;

      _selectedMinBedrooms =
          shouldAllowIndependentHouseFilters ? nextMinBedrooms : null;
      _selectedCarParking =
          shouldAllowIndependentHouseFilters ? nextCarParking : null;
      _selectedMinFloors =
          shouldAllowIndependentHouseFilters ? nextMinFloors : null;
      _selectedBuildingAge =
          shouldAllowIndependentHouseFilters ? nextBuildingAge : null;
    });

    await _fetchViewport();
  }
}
