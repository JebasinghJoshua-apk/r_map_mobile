import 'package:flutter/material.dart';

import '../utils/pending_property_selection.dart';
import '../widgets/delimited_bullet_list.dart';
import '../widgets/property_detail_shared.dart';

/// Detail screen for Plot property type.
class PlotDetailScreen extends BasePropertyDetailScreen {
  const PlotDetailScreen({
    super.key,
    required super.feature,
    super.imageUrls,
    super.isLoadingImages,
    super.imagesError,
    super.fromDeepLink,
  });

  @override
  State<PlotDetailScreen> createState() => _PlotDetailScreenState();
}

class _PlotDetailScreenState
    extends BasePropertyDetailScreenState<PlotDetailScreen> {
  @override
  String get screenName => 'PlotDetail';

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final metadata = feature.metadata;

    final title =
        feature.name.trim().isEmpty ? 'Plot Details' : feature.name.trim();

    final commonMeta = extractCommonMeta(metadata);
    final price = commonMeta['price'];
    final location = commonMeta['location'];
    final areaLabel = commonMeta['area'];
    final areaDisplay = formatAreaDisplay(areaLabel);
    final facing = commonMeta['facing'];
    final additionalInfo = commonMeta['additionalInfo'];
    final contactName = commonMeta['contactName'];
    final phoneNumber = commonMeta['phoneNumber'];

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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
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
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          size: 18,
                                          color: Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 4),
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
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                PendingPropertySelection.set(widget.feature);
                                Navigator.of(context).pop();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'View\non Map',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                        if (facing != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  label: 'FACING',
                                  value: labelOrDash(facing),
                                ),
                              ),
                              const SizedBox(width: 12),
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
                                value: 'Plot',
                              ),
                              if (listingType.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                KeyValueRow(
                                  label: 'Listing',
                                  value: listingType,
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
                        if (contactName != null || phoneNumber != null) ...[
                          const SizedBox(height: 14),
                          AuthGatedContactSection(
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
                                  CallablePhoneRow(
                                    label: 'Phone',
                                    rawValue: phoneNumber,
                                    onCall: callPhoneNumber,
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
