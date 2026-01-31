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

  Future<void> _openFilters(Rect anchorRect) async {
    if (!mounted) return;

    final initialType = _selectedPropertyType;
    final initialListingType = _selectedListingType;
    final initialPrice = _selectedPriceRange;
    final initialLandType = _selectedLandType;

    final result = await showGeneralDialog<
        ({
          String? type,
          String? listingType,
          _PriceRangeFilter? price,
          String? landType,
        })>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filters',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, _, __) {
        final media = MediaQuery.of(context);
        final size = media.size;
        const horizontalPadding = 16.0;
        const arrowWidth = 18.0;
        const arrowHeight = 10.0;
        const popupGap = 8.0;

        final safeTop = media.padding.top;
        final popupTopRaw = anchorRect.bottom + popupGap;
        final popupTop = popupTopRaw < safeTop + 8 ? safeTop + 8 : popupTopRaw;

        final popupWidth = size.width - (horizontalPadding * 2);
        final anchorCenterX = anchorRect.left + (anchorRect.width / 2);
        const arrowLeftMin = horizontalPadding + 12;
        final arrowLeftMax = horizontalPadding + popupWidth - 12 - arrowWidth;
        final arrowLeftRaw = anchorCenterX - (arrowWidth / 2);
        final arrowLeft = arrowLeftRaw < arrowLeftMin
            ? arrowLeftMin
            : (arrowLeftRaw > arrowLeftMax ? arrowLeftMax : arrowLeftRaw);

        var localType = initialType;
        var localListingType = initialListingType;
        var localPrice = initialPrice;
        var localLandType = initialLandType;
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

        const chipLabelPadding = EdgeInsets.symmetric(horizontal: 10);
        const chipVisualDensity = VisualDensity.compact;
        const chipRadius = 6.0;
        const wrapSpacing = 8.0;
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

            return GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Material(
                color: Colors.transparent,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: popupTop - arrowHeight,
                        left: arrowLeft,
                        child: const IgnorePointer(
                          child: _FilterPopoverArrow(
                            width: arrowWidth,
                            height: arrowHeight,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        top: popupTop,
                        left: horizontalPadding,
                        right: horizontalPadding,
                        child: GestureDetector(
                          onTap: () {},
                          child: Material(
                            elevation: 10,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(16),
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
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: IconButton(
                                        tooltip: 'Close',
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                          width: 32,
                                          height: 32,
                                        ),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
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
                                                      const SizedBox(
                                                          height: 10),
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                left: 4),
                                                        child: Text(
                                                          'Listing Type',
                                                          style:
                                                              sectionTitleStyle,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: wrapSpacing,
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
                                                                  option.label),
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
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
                                                                  localListingType = localListingType ==
                                                                          option
                                                                              .id
                                                                      ? null
                                                                      : option
                                                                          .id;
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
                                                      const SizedBox(height: 6),
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
                                                              onSelected: (_) {
                                                                setModalState(
                                                                    () {
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
                                                      const SizedBox(
                                                          height: 10),
                                                      if (showPrice) ...[
                                                        const SizedBox(
                                                            height: 10),
                                                        const Text(
                                                          'Price',
                                                          style:
                                                              sectionTitleStyle,
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Wrap(
                                                          spacing: wrapSpacing,
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
                                                                              localPrice!
                                                                                  .label)
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
                                                        const SizedBox(
                                                            height: 10),
                                                        const Text(
                                                          'Land Type',
                                                          style:
                                                              sectionTitleStyle,
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
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
                                                    ],
                                                  ),
                                                ),
                                              ],
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
                                                          'Price',
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
