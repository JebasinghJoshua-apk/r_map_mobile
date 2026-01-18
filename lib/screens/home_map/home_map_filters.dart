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
    if (!_isPriceFilterEligiblePropertyType(type)) return '';
    final f = _selectedPriceRange;
    if (f == null) return '';
    return '${f.minRupees ?? ''}-${f.maxRupees ?? ''}';
  }

  Future<void> _openFilters() async {
    if (!mounted) return;

    final initialType = _selectedPropertyType;
    final initialPrice = _selectedPriceRange;

    final result =
        await showModalBottomSheet<({String? type, _PriceRangeFilter? price})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        var localType = initialType;
        var localPrice = initialPrice;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final showPrice = _isPriceFilterEligiblePropertyType(localType) &&
                (localType?.trim() != 'Layout');
            if (!showPrice) {
              localPrice = null;
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Property Type',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        for (final option in _propertyTypeOptions)
                          ChoiceChip(
                            label: Text(option.label),
                            selected: (localType == option.id),
                            showCheckmark: false,
                            selectedColor: const Color(0xFF0FAD97),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: (localType == option.id)
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            onSelected: (_) {
                              setModalState(() {
                                localType = option.id;
                                if (!_isPriceFilterEligiblePropertyType(
                                        localType) ||
                                    localType?.trim() == 'Layout') {
                                  localPrice = null;
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    if (showPrice) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Price',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final option in _priceRangeOptions)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: (localPrice == null
                                  ? option == _anyPriceRange
                                  : option.label == localPrice!.label),
                              showCheckmark: false,
                              selectedColor: const Color(0xFF0FAD97),
                              backgroundColor: const Color(0xFFF1F5F9),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: (localPrice == null
                                        ? option == _anyPriceRange
                                        : option.label == localPrice!.label)
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
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
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context)
                                .pop((type: null, price: null));
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
                            Navigator.of(context)
                                .pop((type: localType, price: localPrice));
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

    final normalizedNextType = nextType?.trim();
    final shouldAllowPrice =
        _isPriceFilterEligiblePropertyType(normalizedNextType) &&
            normalizedNextType != 'Layout';

    _updateState(() {
      _selectedPropertyType = nextType;
      _selectedPriceRange = shouldAllowPrice ? nextPrice : null;
    });

    await _fetchViewport();
  }
}
