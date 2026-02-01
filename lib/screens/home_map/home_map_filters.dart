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

    final result = await showGeneralDialog<
        ({
          String? type,
          String? listingType,
          _PriceRangeFilter? price,
          String? landType,
          String? suitableFor,
          _AreaRangeFilter? areaRange,
        })>(
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
                                child: Stack(
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: CustomScrollView(
                                            shrinkWrap: true,
                                            slivers: [
                                              SliverToBoxAdapter(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Padding(
                                                      padding: EdgeInsets.zero,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const SizedBox(
                                                              height: 12),
                                                          Row(
                                                            children: [
                                                              const Padding(
                                                                padding: EdgeInsets
                                                                    .only(
                                                                        left:
                                                                            4),
                                                                child: Text(
                                                                  'Listing Type',
                                                                  style:
                                                                      sectionTitleStyle,
                                                                ),
                                                              ),
                                                              const Spacer(),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                  right: 4,
                                                                ),
                                                                child:
                                                                    TextButton(
                                                                  style: TextButton
                                                                      .styleFrom(
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    minimumSize:
                                                                        const Size(
                                                                            32,
                                                                            32),
                                                                    tapTargetSize:
                                                                        MaterialTapTargetSize
                                                                            .shrinkWrap,
                                                                  ),
                                                                  onPressed:
                                                                      () {
                                                                    Navigator.of(
                                                                            context)
                                                                        .pop(
                                                                      (
                                                                        type:
                                                                            null,
                                                                        listingType:
                                                                            'Sell',
                                                                        price:
                                                                            null,
                                                                        landType:
                                                                            null,
                                                                        suitableFor:
                                                                            null,
                                                                        areaRange:
                                                                            null,
                                                                      ),
                                                                    );
                                                                  },
                                                                  child:
                                                                      const Text(
                                                                    'CLEAR',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color: Color(
                                                                          0xFF0FAD97),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 10),
                                                          Wrap(
                                                            spacing:
                                                                wrapSpacing,
                                                            runSpacing:
                                                                wrapRunSpacing,
                                                            children: [
                                                              for (final option
                                                                  in const <({
                                                                String id,
                                                                String label,
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
                                                                  label: Text(
                                                                      option
                                                                          .label),
                                                                  selected:
                                                                      (localListingType ==
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
                                                                  side:
                                                                      const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1),
                                                                  ),
                                                                  labelStyle:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        chipLabelStyle
                                                                            .fontSize,
                                                                    fontWeight:
                                                                        chipLabelStyle
                                                                            .fontWeight,
                                                                    color: (localListingType ==
                                                                            option
                                                                                .id)
                                                                        ? Colors
                                                                            .white
                                                                        : const Color(
                                                                            0xFF0F172A,
                                                                          ),
                                                                  ),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      chipRadius,
                                                                    ),
                                                                  ),
                                                                  onSelected:
                                                                      (_) {
                                                                    setModalState(
                                                                        () {
                                                                      localListingType = localListingType ==
                                                                              option.id
                                                                          ? null
                                                                          : option.id;
                                                                    });
                                                                  },
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
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
                                                        right: 44,
                                                      ),
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
                                                                  sectionTitleStyle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 10),
                                                          Wrap(
                                                            spacing:
                                                                wrapSpacing,
                                                            runSpacing:
                                                                wrapRunSpacing,
                                                            children: [
                                                              for (final option
                                                                  in _propertyTypeOptions)
                                                                ChoiceChip(
                                                                  label: Text(
                                                                      option
                                                                          .label),
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
                                                                  side:
                                                                      const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1),
                                                                  ),
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
                                                                            0xFF0F172A,
                                                                          ),
                                                                  ),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      chipRadius,
                                                                    ),
                                                                  ),
                                                                  onSelected:
                                                                      (_) {
                                                                    setModalState(
                                                                        () {
                                                                      localType =
                                                                          option
                                                                              .id;
                                                                      if (!_isPriceFilterEligiblePropertyType(
                                                                            localType,
                                                                          ) ||
                                                                          localType?.trim() ==
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
                                                              right: 44,
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Padding(
                                                                  padding: EdgeInsets
                                                                      .only(
                                                                          left:
                                                                              4),
                                                                  child: Text(
                                                                    'Suitable For',
                                                                    style:
                                                                        sectionTitleStyle,
                                                                  ),
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
                                                                      side:
                                                                          const BorderSide(
                                                                        color: Color(
                                                                            0xFFCBD5E1),
                                                                      ),
                                                                      labelStyle:
                                                                          TextStyle(
                                                                        fontSize:
                                                                            chipLabelStyle.fontSize,
                                                                        fontWeight:
                                                                            chipLabelStyle.fontWeight,
                                                                        color: localSuitableFor ==
                                                                                null
                                                                            ? Colors.white
                                                                            : const Color(
                                                                                0xFF0F172A,
                                                                              ),
                                                                      ),
                                                                      shape:
                                                                          RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                          chipRadius,
                                                                        ),
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
                                                                            MaterialTapTargetSize.shrinkWrap,
                                                                        visualDensity:
                                                                            chipVisualDensity,
                                                                        labelPadding:
                                                                            chipLabelPadding,
                                                                        selectedColor:
                                                                            const Color(0xFF0FAD97),
                                                                        backgroundColor:
                                                                            const Color(0xFFF1F5F9),
                                                                        side:
                                                                            const BorderSide(
                                                                          color:
                                                                              Color(0xFFCBD5E1),
                                                                        ),
                                                                        labelStyle:
                                                                            TextStyle(
                                                                          fontSize:
                                                                              chipLabelStyle.fontSize,
                                                                          fontWeight:
                                                                              chipLabelStyle.fontWeight,
                                                                          color: localSuitableFor == option
                                                                              ? Colors.white
                                                                              : const Color(
                                                                                  0xFF0F172A,
                                                                                ),
                                                                        ),
                                                                        shape:
                                                                            RoundedRectangleBorder(
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                            chipRadius,
                                                                          ),
                                                                        ),
                                                                        onSelected:
                                                                            (_) {
                                                                          setModalState(
                                                                              () {
                                                                            localSuitableFor = localSuitableFor == option
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
                                                                0xFFE2E8F0),
                                                          ),
                                                          const SizedBox(
                                                              height: 10),
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                    left: 4),
                                                            child: Text(
                                                              'Area (sq ft)',
                                                              style:
                                                                  sectionTitleStyle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              left: 4,
                                                              right: 8,
                                                            ),
                                                            child: Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Text(
                                                                  '${areaValues.start.round()} sq ft',
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        12,
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
                                                                    fontSize:
                                                                        12,
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
                                                                    .only(
                                                              right: 8,
                                                            ),
                                                            child: RangeSlider(
                                                              values:
                                                                  areaValues,
                                                              min: areaMinSqft,
                                                              max: areaMaxSqft,
                                                              divisions: 98,
                                                              activeColor:
                                                                  const Color(
                                                                      0xFF0FAD97),
                                                              inactiveColor:
                                                                  const Color(
                                                                      0xFFE2E8F0),
                                                              labels:
                                                                  RangeLabels(
                                                                '${areaValues.start.round()} sq ft',
                                                                areaValues.end >=
                                                                        areaMaxSqft
                                                                    ? '10,000+ sq ft'
                                                                    : '${areaValues.end.round()} sq ft',
                                                              ),
                                                              onChanged: (v) {
                                                                setModalState(
                                                                    () {
                                                                  final start = v
                                                                      .start
                                                                      .round();
                                                                  final end = v
                                                                      .end
                                                                      .round();
                                                                  final isAny = start <=
                                                                          areaMinSqft
                                                                              .round() &&
                                                                      end >=
                                                                          areaMaxSqft
                                                                              .round();
                                                                  localAreaRange =
                                                                      isAny
                                                                          ? null
                                                                          : _AreaRangeFilter(
                                                                              minSqft: start,
                                                                              maxSqft: end,
                                                                            );
                                                                });
                                                              },
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    if (showPrice) ...[
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
                                                            child: Text(
                                                              'Price',
                                                              style:
                                                                  sectionTitleStyle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 10),
                                                          Wrap(
                                                            spacing:
                                                                wrapSpacing,
                                                            runSpacing:
                                                                wrapRunSpacing,
                                                            children: [
                                                              for (final option
                                                                  in _priceRangeOptions)
                                                                ChoiceChip(
                                                                  label: Text(
                                                                      option
                                                                          .label),
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
                                                                  side:
                                                                      const BorderSide(
                                                                    color: Color(
                                                                        0xFFCBD5E1),
                                                                  ),
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
                                                                                localPrice!.label)
                                                                        ? Colors.white
                                                                        : const Color(
                                                                            0xFF0F172A,
                                                                          ),
                                                                  ),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      chipRadius,
                                                                    ),
                                                                  ),
                                                                  onSelected:
                                                                      (_) {
                                                                    setModalState(
                                                                        () {
                                                                      localPrice = option ==
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
                                                        showLandType) ...[
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
                                                    ],
                                                    if (showLandType)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                          right: 44,
                                                        ),
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
                                                                'Land Type',
                                                                style:
                                                                    sectionTitleStyle,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 10),
                                                            Wrap(
                                                              spacing:
                                                                  wrapSpacing,
                                                              runSpacing:
                                                                  wrapRunSpacing,
                                                              children: [
                                                                for (final option
                                                                    in landTypeOptions)
                                                                  ChoiceChip(
                                                                    label: Text(
                                                                        option),
                                                                    selected: option == 'Any'
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
                                                                    side:
                                                                        const BorderSide(
                                                                      color: Color(
                                                                          0xFFCBD5E1),
                                                                    ),
                                                                    labelStyle:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          chipLabelStyle
                                                                              .fontSize,
                                                                      fontWeight:
                                                                          chipLabelStyle
                                                                              .fontWeight,
                                                                      color: (option == 'Any'
                                                                              ? localLandType == null
                                                                              : localLandType == option)
                                                                          ? Colors.white
                                                                          : const Color(
                                                                              0xFF0F172A,
                                                                            ),
                                                                    ),
                                                                    shape:
                                                                        RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius
                                                                              .circular(
                                                                        chipRadius,
                                                                      ),
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
                                          color: Color(0xFFE2E8F0),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            SizedBox(
                                              height: 36,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                    color: Color(0xFF0FAD97),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                  ),
                                                  minimumSize:
                                                      const Size(0, 36),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
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
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                  ),
                                                  minimumSize:
                                                      const Size(0, 36),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                onPressed: () {
                                                  Navigator.of(context).pop(
                                                    (
                                                      type: localType,
                                                      listingType:
                                                          localListingType,
                                                      price: localPrice,
                                                      landType: localLandType,
                                                      suitableFor:
                                                          localSuitableFor,
                                                      areaRange: localAreaRange,
                                                    ),
                                                  );
                                                },
                                                child: const Text(
                                                  'Apply',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
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

    final normalizedNextType = nextType?.trim();
    final shouldAllowPrice =
        _isPriceFilterEligiblePropertyType(normalizedNextType) &&
            normalizedNextType != 'Layout';

    final shouldAllowLandType = normalizedNextType == 'Land';

    final shouldAllowCommercialFilters =
        normalizedNextType == 'CommercialSpace';

    _updateState(() {
      _selectedPropertyType = nextType;
      _selectedListingType = nextListingType;
      _selectedPriceRange = shouldAllowPrice ? nextPrice : null;
      _selectedLandType = shouldAllowLandType ? normalizedNextLandType : null;
      _selectedCommercialSuitableFor =
          shouldAllowCommercialFilters ? nextSuitableFor : null;
      _selectedAreaRange = shouldAllowCommercialFilters ? nextAreaRange : null;
    });

    await _fetchViewport();
  }
}

class _FilterPopoverArrow extends StatelessWidget {
  const _FilterPopoverArrow({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _FilterPopoverArrowPainter(color),
    );
  }
}

class _FilterPopoverArrowPainter extends CustomPainter {
  _FilterPopoverArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FilterPopoverArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}


/*
extension _HomeMapFilters on _HomeMapScreenState {
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
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    right: 44,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const SizedBox(height: 10),
                                                      const Padding(
                                                        padding: EdgeInsets.only(left: 4),
                                                        child: Text(
                                                          'Listing Type',
                                                          style: sectionTitleStyle,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing: wrapRunSpacing,
                                                        children: [
                                                          for (final option in const <({
                                                            String id,
                                                            String label,
                                                          })>[
                                                            (id: 'Sell', label: 'Buy'),
                                                            (id: 'Rent', label: 'Rent'),
                                                            (id: 'Lease', label: 'Lease'),
                                                          ])
                                                            ChoiceChip(
                                                              label: Text(option.label),
                                                              selected: (localListingType ==
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
                                                                  const Color(0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                color: Color(0xFFCBD5E1),
                                                              ),
                                                              labelStyle: TextStyle(
                                                                fontSize: chipLabelStyle
                                                                    .fontSize,
                                                                fontWeight: chipLabelStyle
                                                                    .fontWeight,
                                                                color: (localListingType ==
                                                                        option.id)
                                                                    ? Colors.white
                                                                    : const Color(
                                                                        0xFF0F172A,
                                                                      ),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                  chipRadius,
                                                                ),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(() {
                                                                  localListingType =
                                                                      localListingType ==
                                                                              option.id
                                                                          ? null
                                                                          : option.id;
                                                                });
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                const Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: Color(0xFFE2E8F0),
                                                ),
                                                const SizedBox(height: 12),
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    right: 44,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Padding(
                                                        padding: EdgeInsets.only(left: 4),
                                                        child: Text(
                                                          'Property Type',
                                                          style: sectionTitleStyle,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: wrapSpacing,
                                                        runSpacing: wrapRunSpacing,
                                                        children: [
                                                          for (final option
                                                              in _propertyTypeOptions)
                                                            ChoiceChip(
                                                              label: Text(option.label),
                                                              selected:
                                                                  (localType == option.id),
                                                              showCheckmark: false,
                                                              materialTapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                              visualDensity:
                                                                  chipVisualDensity,
                                                              labelPadding:
                                                                  chipLabelPadding,
                                                              selectedColor:
                                                                  const Color(0xFF0FAD97),
                                                              backgroundColor:
                                                                  const Color(0xFFF1F5F9),
                                                              side: const BorderSide(
                                                                color: Color(0xFFCBD5E1),
                                                              ),
                                                              labelStyle: TextStyle(
                                                                fontSize:
                                                                    chipLabelStyle.fontSize,
                                                                fontWeight:
                                                                    chipLabelStyle.fontWeight,
                                                                color: (localType == option.id)
                                                                    ? Colors.white
                                                                    : const Color(
                                                                        0xFF0F172A,
                                                                      ),
                                                              ),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                  chipRadius,
                                                                ),
                                                              ),
                                                              onSelected: (_) {
                                                                setModalState(() {
                                                                  localType = option.id;
                                                                  if (!_isPriceFilterEligiblePropertyType(
                                                                        localType,
                                                                      ) ||
                                                                      localType
                                                                              ?.trim() ==
                                                                          'Layout') {
                                                                    localPrice = null;
                                                                  }
                                                                  if (localType
                                                                          ?.trim() !=
                                                                      'Land') {
                                                                    localLandType = null;
                                                                  }
                                                                });
                                                              },
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 10),
                                                      if (showPrice) ...[
                                                        const SizedBox(height: 10),
                                                        const Text(
                                                          spacing: propertyTypeWrapSpacing,
                                                          style: sectionTitleStyle,
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Wrap(
                                                          spacing: wrapSpacing,
                                                          runSpacing: wrapRunSpacing,
                                                          children: [
                                                            for (final option
                                                                in _priceRangeOptions)
                                                              ChoiceChip(
                                                                label: Text(option.label),
                                                                selected: (localPrice == null
                                                                    ? option == _anyPriceRange
                                                                    : option.label ==
                                                                        localPrice!.label),
                                                                showCheckmark: false,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                propertyTypeChipLabelPadding,
                                                                labelPadding:
                                                                    chipLabelPadding,
                                                                selectedColor:
                                                                    const Color(0xFF0FAD97),
                                                                backgroundColor:
                                                                    const Color(0xFFF1F5F9),
                                                                side: const BorderSide(
                                                                  color: Color(0xFFCBD5E1),
                                                                ),
                                                                labelStyle: TextStyle(
                                                                  fontSize: chipLabelStyle
                                                                      .fontSize,
                                                                  fontWeight: chipLabelStyle
                                                                      .fontWeight,
                                                                  color: (localPrice == null
                                                                          ? option ==
                                                                              _anyPriceRange
                                                                          : option.label ==
                                                                              localPrice!
                                                                                  .label)
                                                                      ? Colors.white
                                                                      : const Color(
                                                                          0xFF0F172A,
                                                                        ),
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                    chipRadius,
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setModalState(() {
                                                                    localPrice = option ==
                                                                            _anyPriceRange
                                                                        ? null
                                                                        : option;
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                      if (showLandType) ...[
                                                        const SizedBox(height: 10),
                                                        const Text(
                                                          'Land Type',
                                                          style: sectionTitleStyle,
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Wrap(
                                                          spacing: wrapSpacing,
                                                          runSpacing: wrapRunSpacing,
                                                          children: [
                                                            for (final option
                                                                in landTypeOptions)
                                                              ChoiceChip(
                                                                label: Text(option),
                                                                selected: option == 'Any'
                                                                    ? localLandType == null
                                                                    : localLandType == option,
                                                                showCheckmark: false,
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                visualDensity:
                                                                    chipVisualDensity,
                                                                labelPadding:
                                                                    chipLabelPadding,
                                                                selectedColor:
                                                                    const Color(0xFF0FAD97),
                                                                backgroundColor:
                                                                    const Color(0xFFF1F5F9),
                                                                side: const BorderSide(
                                                                  color: Color(0xFFCBD5E1),
                                                                ),
                                                                labelStyle: TextStyle(
                                                                  fontSize: chipLabelStyle
                                                                      .fontSize,
                                                                  fontWeight: chipLabelStyle
                                                                      .fontWeight,
                                                                  color: (option == 'Any'
                                                                          ? localLandType ==
                                                                              null
                                                                          : localLandType ==
                                                                              option)
                                                                      ? Colors.white
                                                                      : const Color(
                                                                          0xFF0F172A,
                                                                        ),
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                    chipRadius,
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setModalState(() {
                                                                    if (option == 'Any') {
                                                                      localLandType = null;
                                                                      return;
                                                                    }
                                                                    localLandType =
                                                                        localLandType == option
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
                                                ),
                                              ],
                                            ),
                                                                : const Color(
                                                                    0xFF0F172A,
                                                                  ),
                                                          ),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              chipRadius,
                                                            ),
                                                          ),
                                                          onSelected: (_) {
                                                            setModalState(() {
                                                              localType =
                                                                  option.id;
                                                              if (!_isPriceFilterEligiblePropertyType(
                                                                    localType,
                                                                  ) ||
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
                                                            });
                                                          },
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 10),
                                                  if (showPrice) ...[
                                                    const SizedBox(height: 10),
                                                    const Text(
                                                      'Price',
                                                      style: sectionTitleStyle,
                                                    ),
                                                    const SizedBox(height: 6),
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
                                                            side:
                                                                const BorderSide(
                                                              color: Color(
                                                                  0xFFCBD5E1),
                                                            ),
                                                            labelStyle:
                                                                TextStyle(
                                                              fontSize:
                                                                  chipLabelStyle
                                                                      .fontSize,
                                                              fontWeight:
                                                                  chipLabelStyle
                                                                      .fontWeight,
                                                              color: (localPrice ==
                                                                          null
                                                                      ? option ==
                                                                          _anyPriceRange
                                                                      : option.label ==
                                                                          localPrice!
                                                                              .label)
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A,
                                                                    ),
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                chipRadius,
                                                              ),
                                                            ),
                                                            onSelected: (_) {
                                                              setModalState(() {
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
                                                  if (showLandType) ...[
                                                    const SizedBox(height: 10),
                                                    const Text(
                                                      'Land Type',
                                                      style: sectionTitleStyle,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: wrapSpacing,
                                                      runSpacing:
                                                          wrapRunSpacing,
                                                      children: [
                                                        for (final option
                                                            in landTypeOptions)
                                                          ChoiceChip(
                                                            label: Text(option),
                                                            selected: option == 'Any'
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
                                                            side:
                                                                const BorderSide(
                                                              color: Color(
                                                                  0xFFCBD5E1),
                                                            ),
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
                                                                  ? Colors.white
                                                                  : const Color(
                                                                      0xFF0F172A,
                                                                    ),
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                chipRadius,
                                                              ),
                                                            ),
                                                            onSelected: (_) {
                                                              setModalState(() {
                                                                if (option ==
                                                                    'Any') {
                                                                  localLandType =
                                                                      null;
                                                                  return;
                                                                }
                                                                localLandType =
                                                                    localLandType ==
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
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop(
                                                  (
                                                    type: null,
                                                    listingType: null,
                                                    price: null,
                                                    landType: null,
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Clear',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF0FAD97),
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF0FAD97),
                                                foregroundColor: Colors.white,
                                              ),
                                              onPressed: () {
                                                Navigator.of(context).pop(
                                                  (
                                                    type: localType,
                                                    listingType:
                                                        localListingType,
                                                    price: localPrice,
                                                    landType: localLandType,
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Apply',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
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

    final normalizedNextType = nextType?.trim();
    final shouldAllowPrice =
        _isPriceFilterEligiblePropertyType(normalizedNextType) &&
            normalizedNextType != 'Layout';

    final shouldAllowLandType = normalizedNextType == 'Land';

    _updateState(() {
      _selectedPropertyType = nextType;
      _selectedListingType = nextListingType;
      _selectedPriceRange = shouldAllowPrice ? nextPrice : null;
      _selectedLandType = shouldAllowLandType ? normalizedNextLandType : null;
    });

    await _fetchViewport();
  }
}

class _FilterPopoverArrow extends StatelessWidget {
  const _FilterPopoverArrow({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _FilterPopoverArrowPainter(color),
    );
  }
}

class _FilterPopoverArrowPainter extends CustomPainter {
  _FilterPopoverArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FilterPopoverArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

*/
