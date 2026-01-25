part of '../home_map_screen.dart';

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
  }

  String _clientFilterSignature() {
    final type = _selectedPropertyType?.trim();
    if (type == null || type.isEmpty) return '';

    final parts = <String>[];

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

  Future<void> _openFilters() async {
    if (!mounted) return;

    final initialType = _selectedPropertyType;
    final initialPrice = _selectedPriceRange;
    final initialLandType = _selectedLandType;

    final result = await showModalBottomSheet<
        ({
          String? type,
          _PriceRangeFilter? price,
          String? landType,
        })>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        var localType = initialType;
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

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Property Type', style: sectionTitleStyle),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: wrapSpacing,
                      runSpacing: wrapRunSpacing,
                      children: [
                        for (final option in _propertyTypeOptions)
                          ChoiceChip(
                            label: Text(option.label),
                            selected: (localType == option.id),
                            showCheckmark: false,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: chipVisualDensity,
                            labelPadding: chipLabelPadding,
                            selectedColor: const Color(0xFF0FAD97),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            labelStyle: TextStyle(
                              fontSize: chipLabelStyle.fontSize,
                              fontWeight: chipLabelStyle.fontWeight,
                              color: (localType == option.id)
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(chipRadius),
                            ),
                            onSelected: (_) {
                              setModalState(() {
                                localType = option.id;
                                if (!_isPriceFilterEligiblePropertyType(
                                        localType) ||
                                    localType?.trim() == 'Layout') {
                                  localPrice = null;
                                }
                                if (localType?.trim() != 'Land') {
                                  localLandType = null;
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    if (showPrice) ...[
                      const SizedBox(height: 10),
                      const Text('Price', style: sectionTitleStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: wrapSpacing,
                        runSpacing: wrapRunSpacing,
                        children: [
                          for (final option in _priceRangeOptions)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: (localPrice == null
                                  ? option == _anyPriceRange
                                  : option.label == localPrice!.label),
                              showCheckmark: false,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: chipVisualDensity,
                              labelPadding: chipLabelPadding,
                              selectedColor: const Color(0xFF0FAD97),
                              backgroundColor: const Color(0xFFF1F5F9),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              labelStyle: TextStyle(
                                fontSize: chipLabelStyle.fontSize,
                                fontWeight: chipLabelStyle.fontWeight,
                                color: (localPrice == null
                                        ? option == _anyPriceRange
                                        : option.label == localPrice!.label)
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(chipRadius),
                              ),
                              onSelected: (_) {
                                setModalState(() {
                                  localPrice =
                                      option == _anyPriceRange ? null : option;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    if (showLandType) ...[
                      const SizedBox(height: 10),
                      const Text('Land Type', style: sectionTitleStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: wrapSpacing,
                        runSpacing: wrapRunSpacing,
                        children: [
                          for (final option in landTypeOptions)
                            ChoiceChip(
                              label: Text(option),
                              selected: option == 'Any'
                                  ? localLandType == null
                                  : localLandType == option,
                              showCheckmark: false,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: chipVisualDensity,
                              labelPadding: chipLabelPadding,
                              selectedColor: const Color(0xFF0FAD97),
                              backgroundColor: const Color(0xFFF1F5F9),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              labelStyle: TextStyle(
                                fontSize: chipLabelStyle.fontSize,
                                fontWeight: chipLabelStyle.fontWeight,
                                color: (option == 'Any'
                                        ? localLandType == null
                                        : localLandType == option)
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(chipRadius),
                              ),
                              onSelected: (_) {
                                setModalState(() {
                                  if (option == 'Any') {
                                    localLandType = null;
                                    return;
                                  }
                                  localLandType =
                                      localLandType == option ? null : option;
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              (type: null, price: null, landType: null),
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
                            backgroundColor: const Color(0xFF0FAD97),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop(
                              (
                                type: localType,
                                price: localPrice,
                                landType: localLandType,
                              ),
                            );
                          },
                          child: const Text(
                            'Apply',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    final nextType = result.type?.trim().isEmpty ?? true ? null : result.type;
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
      _selectedPriceRange = shouldAllowPrice ? nextPrice : null;
      _selectedLandType = shouldAllowLandType ? normalizedNextLandType : null;
    });

    await _fetchViewport();
  }
}
