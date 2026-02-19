import 'package:flutter/material.dart';

import '../models/map_viewport_models.dart';
import 'apartment_detail_screen.dart';
import 'commercial_space_detail_screen.dart';
import 'independent_house_detail_screen.dart';
import 'individual_plots_detail_screen.dart';
import 'land_detail_screen.dart';
import 'plot_detail_screen.dart';

/// Router widget that delegates to the appropriate property detail screen
/// based on the property type.
class PropertyDetailScreen extends StatelessWidget {
  const PropertyDetailScreen({
    super.key,
    required this.feature,
    this.imageUrls,
    this.isLoadingImages = false,
    this.imagesError,
    this.fromDeepLink = false,
  });

  final MapPropertyFeature feature;
  final List<String>? imageUrls;
  final bool isLoadingImages;
  final String? imagesError;

  /// When true, popping this screen will set a pending property selection
  /// so HomeMapScreen can select the property and show the bottom panel.
  final bool fromDeepLink;

  @override
  Widget build(BuildContext context) {
    final propertyType = feature.propertyType.trim().toLowerCase();

    switch (propertyType) {
      case 'individualplots':
        return IndividualPlotsDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      case 'plot':
        return PlotDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      case 'apartment':
      case 'apartmentflat':
        return ApartmentDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      case 'independenthouse':
        return IndependentHouseDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      case 'commercialspace':
        return CommercialSpaceDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      case 'land':
        return LandDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );

      // Default to Plot detail screen for unknown types
      default:
        return PlotDetailScreen(
          feature: feature,
          imageUrls: imageUrls,
          isLoadingImages: isLoadingImages,
          imagesError: imagesError,
          fromDeepLink: fromDeepLink,
        );
    }
  }
}
