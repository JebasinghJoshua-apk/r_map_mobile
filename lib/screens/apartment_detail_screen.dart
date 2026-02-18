import 'package:flutter/material.dart';

import '../widgets/delimited_bullet_list.dart';
import '../widgets/property_detail_shared.dart';

/// Detail screen for Apartment property type.
class ApartmentDetailScreen extends BasePropertyDetailScreen {
  const ApartmentDetailScreen({
    super.key,
    required super.feature,
    super.imageUrls,
    super.isLoadingImages,
    super.imagesError,
    super.fromDeepLink,
  });

  @override
  State<ApartmentDetailScreen> createState() => _ApartmentDetailScreenState();
}

class _ApartmentDetailScreenState
    extends BasePropertyDetailScreenState<ApartmentDetailScreen> {
  @override
  String get screenName => 'ApartmentDetail';

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final metadata = feature.metadata;

    final title =
        feature.name.trim().isEmpty ? 'Apartment Details' : feature.name.trim();

    final commonMeta = extractCommonMeta(metadata);
    final price = commonMeta['price'];
    final location = commonMeta['location'];
    final areaLabel = commonMeta['area'];
    final areaDisplay = formatAreaDisplay(areaLabel);
    final facing = commonMeta['facing'];
    final additionalInfo = commonMeta['additionalInfo'];
    final contactName = commonMeta['contactName'];
    final phoneNumber = commonMeta['phoneNumber'];

    // Apartment-specific metadata
    final bedrooms = meta(metadata, ['bedrooms', 'bhk', 'beds']);
    final bathrooms = meta(metadata, ['bathrooms', 'baths']);
    final floor = meta(metadata, ['floor', 'floorNumber']);
    final totalFloors = meta(metadata, ['totalFloors', 'floors']);
    final furnishing = meta(metadata, ['furnishing', 'furnished']);
    final parking = meta(metadata, ['parking', 'carParking']);
    final amenities = meta(metadata, ['amenities', 'facilities']);

    final listingType = formatListingType(feature.listingType);
    final images = buildHeroImages(title);

    return buildScaffold(
      body: Builder(
        builder: (context) {
          final bottomInset = MediaQuery.of(context).padding.bottom;
          final topInset = MediaQuery.of(context).padding.top;
          return ListView(
            padding: EdgeInsets.only(top: topInset, bottom: 24 + bottomInset),
            children: [
              buildHeroHeader(
                images: images,
                title: title,
                location: location,
                price: price,
                listingType: listingType,
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
                              child: StatCard(
                                label: 'PRICE',
                                value: labelOrDash(price),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: StatCard(
                                label: 'AREA',
                                value: labelOrDash(areaDisplay),
                              ),
                            ),
                          ],
                        ),
                        if (bedrooms != null || bathrooms != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (bedrooms != null)
                                Expanded(
                                  child: StatCard(
                                    label: 'BEDROOMS',
                                    value: bedrooms,
                                  ),
                                ),
                              if (bedrooms != null && bathrooms != null)
                                const SizedBox(width: 12),
                              if (bathrooms != null)
                                Expanded(
                                  child: StatCard(
                                    label: 'BATHROOMS',
                                    value: bathrooms,
                                  ),
                                ),
                              if (bedrooms == null || bathrooms == null)
                                const Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        SectionCard(
                          title: 'PROPERTY OVERVIEW',
                          child: Column(
                            children: [
                              const KeyValueRow(
                                label: 'Type',
                                value: 'Apartment',
                              ),
                              if (listingType.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Listing',
                                  value: listingType,
                                ),
                              ],
                              if (floor != null) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Floor',
                                  value: totalFloors != null
                                      ? '$floor of $totalFloors'
                                      : floor,
                                ),
                              ],
                              if (furnishing != null) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Furnishing',
                                  value: furnishing,
                                ),
                              ],
                              if (facing != null) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Facing',
                                  value: facing,
                                ),
                              ],
                              if (parking != null) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Parking',
                                  value: parking,
                                ),
                              ],
                              if (location != null) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Location',
                                  value: location,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (additionalInfo != null) ...[
                          const SizedBox(height: 14),
                          SectionCard(
                            title: 'DESCRIPTION',
                            child: DelimitedBulletList(
                              text: additionalInfo,
                              delimiterPattern: RegExp(r'\n+'),
                              textStyle: const TextStyle(
                                color: Color(0xFF334155),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                        if (amenities != null) ...[
                          const SizedBox(height: 14),
                          SectionCard(
                            title: 'AMENITIES',
                            child: DelimitedBulletList(
                              text: amenities,
                              delimiterPattern: RegExp(r'[,\n]+'),
                              textStyle: const TextStyle(
                                color: Color(0xFF334155),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                        if (contactName != null || phoneNumber != null) ...[
                          const SizedBox(height: 14),
                          SectionCard(
                            title: 'CONTACT DETAILS',
                            child: Column(
                              children: [
                                if (contactName != null)
                                  KeyValueRow(
                                    label: 'Name',
                                    value: contactName,
                                  ),
                                if (contactName != null && phoneNumber != null)
                                  const SizedBox(height: 10),
                                if (phoneNumber != null)
                                  KeyValueRow(
                                    label: 'Phone',
                                    value: phoneNumber,
                                  ),
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
          );
        },
      ),
    );
  }
}
