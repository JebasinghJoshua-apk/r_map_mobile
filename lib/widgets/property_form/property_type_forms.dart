import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'indian_currency_formatter.dart';
import 'property_form_constants.dart';
import 'property_form_widgets.dart';

/// State holder for Plot form fields.
class PlotFormState {
  String area = '';
  String price = '';
  String location = '';
  String title = '';
  String moreDetails = '';
  String contactName = '';
  String contactNumber = '';

  String? errArea;
  String? errPrice;
  String? errLocation;
  String? errTitle;
  String? errMoreDetails;
  String? errContactName;
  String? errContactNumber;
}

/// State holder for Independent House form fields.
class HouseFormState {
  String title = '';
  String bedrooms = '';
  String builtUpArea = '';
  String floors = '';
  String buildingAgeYears = '';
  String carParking = '';
  String price = '';
  String location = '';
  String moreDetails = '';
  String contactName = '';
  String contactNumber = '';

  String? errBedrooms;
  String? errBuiltUpArea;
  String? errFloors;
  String? errCarParking;
  String? errPrice;
  String? errLocation;
  String? errTitle;
  String? errContactName;
  String? errContactNumber;
}

/// State holder for Apartment form fields.
class ApartmentFormState {
  String title = '';
  String bedrooms = '';
  String area = '';
  String floor = '';
  String totalFloors = '';
  String carParking = '';
  String buildingAgeYears = '';
  String price = '';
  String location = '';
  String moreInfo = '';
  String contactName = '';
  String contactNumber = '';

  String? errBedrooms;
  String? errArea;
  String? errFloor;
  String? errTotalFloors;
  String? errCarParking;
  String? errBuildingAgeYears;
  String? errPrice;
  String? errLocation;
}

/// State holder for Land form fields.
class LandFormState {
  String title = '';
  String landType = '';
  String area = '';
  String price = '';
  String location = '';
  String moreInfo = '';
  String contactName = '';
  String contactNumber = '';

  String? errLandType;
  String? errArea;
  String? errPrice;
  String? errLocation;
  String? errTitle;
  String? errContactName;
  String? errContactNumber;
}

/// State holder for Commercial Space form fields.
class CommercialFormState {
  String title = '';
  String spaceType = '';
  String builtUpArea = '';
  String price = '';
  String location = '';
  String additionalDetails = '';
  String contactName = '';
  String contactNumber = '';

  String? errSpaceType;
  String? errBuiltUpArea;
  String? errPrice;
  String? errLocation;
  String? errTitle;
  String? errContactName;
  String? errContactNumber;
}

/// Builds form fields for Plot property type.
List<Widget> buildPlotFormFields({
  required PlotFormState state,
  required TextEditingController titleController,
  required TextEditingController priceController,
  required TextEditingController contactNameController,
  required TextEditingController contactNumberController,
  required VoidCallback onAreaChanged,
  required VoidCallback onPriceChanged,
  required VoidCallback onLocationChanged,
  required VoidCallback onTitleChanged,
  required VoidCallback onMoreDetailsChanged,
  required VoidCallback onContactNameChanged,
  required VoidCallback onContactNumberChanged,
  required int prefillRevision,
}) {
  const indianPriceFormatters = <TextInputFormatter>[
    IndianCurrencyInputFormatter(),
  ];

  return [
    PropertyTextField(
      label: 'Plot Area (Sq.ft)',
      value: state.area,
      onChanged: (v) {
        state.area = v;
        state.errArea = null;
        onAreaChanged();
      },
      hint: 'e.g., 2400',
      keyboard: TextInputType.number,
      errorText: state.errArea,
      prefillRevision: prefillRevision,
      propertyType: 'Plot',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Price',
      value: state.price,
      controller: priceController,
      inputFormatters: indianPriceFormatters,
      onChanged: (v) {
        state.price = v;
        state.errPrice = null;
        onPriceChanged();
      },
      hint: 'e.g., ₹50,00,000',
      keyboard: TextInputType.number,
      errorText: state.errPrice,
      prefillRevision: prefillRevision,
      propertyType: 'Plot',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Locality',
      value: state.location,
      onChanged: (v) {
        state.location = v;
        state.errLocation = null;
        onLocationChanged();
      },
      hint: 'e.g., Anna Nagar, Chennai',
      errorText: state.errLocation,
      prefillRevision: prefillRevision,
      propertyType: 'Plot',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Property Title',
      value: state.title,
      controller: titleController,
      onChanged: (v) {
        state.title = v;
        state.errTitle = null;
        onTitleChanged();
      },
      hint: 'e.g., Residential Plot in Anna Nagar',
      errorText: state.errTitle,
      prefillRevision: prefillRevision,
      propertyType: 'Plot',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Description',
      value: state.moreDetails,
      onChanged: (v) {
        state.moreDetails = v;
        state.errMoreDetails = null;
        onMoreDetailsChanged();
      },
      hint: 'e.g., East Facing, DTCP Approved',
      maxLines: 3,
      minLines: 3,
      errorText: state.errMoreDetails,
      prefillRevision: prefillRevision,
      propertyType: 'Plot',
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Contact Name',
            value: state.contactName,
            controller: contactNameController,
            onChanged: (v) {
              state.contactName = v;
              state.errContactName = null;
              onContactNameChanged();
            },
            errorText: state.errContactName,
            prefillRevision: prefillRevision,
            propertyType: 'Plot',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Contact Number',
            value: state.contactNumber,
            controller: contactNumberController,
            onChanged: (v) {
              state.contactNumber = v;
              state.errContactNumber = null;
              onContactNumberChanged();
            },
            keyboard: TextInputType.phone,
            errorText: state.errContactNumber,
            prefillRevision: prefillRevision,
            propertyType: 'Plot',
          ),
        ),
      ],
    ),
  ];
}

/// Builds form fields for Independent House property type.
List<Widget> buildHouseFormFields({
  required HouseFormState state,
  required TextEditingController titleController,
  required TextEditingController priceController,
  required TextEditingController contactNameController,
  required TextEditingController contactNumberController,
  required VoidCallback onBedroomsChanged,
  required VoidCallback onBuiltUpAreaChanged,
  required VoidCallback onFloorsChanged,
  required VoidCallback onCarParkingChanged,
  required VoidCallback onBuildingAgeChanged,
  required VoidCallback onPriceChanged,
  required VoidCallback onLocationChanged,
  required VoidCallback onTitleChanged,
  required VoidCallback onMoreDetailsChanged,
  required VoidCallback onContactNameChanged,
  required VoidCallback onContactNumberChanged,
  required int prefillRevision,
}) {
  const indianPriceFormatters = <TextInputFormatter>[
    IndianCurrencyInputFormatter(),
  ];

  return [
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Bedrooms',
            value: state.bedrooms,
            onChanged: (v) {
              state.bedrooms = v;
              state.errBedrooms = null;
              onBedroomsChanged();
            },
            hint: 'e.g., 3',
            keyboard: TextInputType.number,
            errorText: state.errBedrooms,
            prefillRevision: prefillRevision,
            propertyType: 'Independent House',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Built-up Area (Sq.ft)',
            value: state.builtUpArea,
            onChanged: (v) {
              state.builtUpArea = v;
              state.errBuiltUpArea = null;
              onBuiltUpAreaChanged();
            },
            hint: 'e.g., 1500',
            keyboard: TextInputType.number,
            errorText: state.errBuiltUpArea,
            prefillRevision: prefillRevision,
            propertyType: 'Independent House',
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Floors',
            value: state.floors,
            onChanged: (v) {
              state.floors = v;
              state.errFloors = null;
              onFloorsChanged();
            },
            hint: 'e.g., 2',
            keyboard: TextInputType.number,
            errorText: state.errFloors,
            prefillRevision: prefillRevision,
            propertyType: 'Independent House',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyDropdown(
            label: 'Car Parking',
            value: state.carParking.isEmpty ? 'None' : state.carParking,
            options: kCarParkingOptions,
            onChanged: (v) {
              state.carParking = v ?? 'None';
              state.errCarParking = null;
              onCarParkingChanged();
            },
            errorText: state.errCarParking,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Building Age (Years)',
      value: state.buildingAgeYears,
      onChanged: (v) {
        state.buildingAgeYears = v;
        onBuildingAgeChanged();
      },
      hint: 'e.g., 10',
      keyboard: TextInputType.number,
      prefillRevision: prefillRevision,
      propertyType: 'Independent House',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Price',
      value: state.price,
      controller: priceController,
      inputFormatters: indianPriceFormatters,
      onChanged: (v) {
        state.price = v;
        state.errPrice = null;
        onPriceChanged();
      },
      hint: 'e.g., 75,00,000',
      keyboard: TextInputType.number,
      errorText: state.errPrice,
      prefillRevision: prefillRevision,
      propertyType: 'Independent House',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Locality',
      value: state.location,
      onChanged: (v) {
        state.location = v;
        state.errLocation = null;
        onLocationChanged();
      },
      hint: 'e.g., Anna Nagar, Chennai',
      errorText: state.errLocation,
      prefillRevision: prefillRevision,
      propertyType: 'Independent House',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Property Title',
      value: state.title,
      controller: titleController,
      onChanged: (v) {
        state.title = v;
        state.errTitle = null;
        onTitleChanged();
      },
      hint: 'e.g., 2 BHK Independent House in Anna Nagar',
      errorText: state.errTitle,
      prefillRevision: prefillRevision,
      propertyType: 'Independent House',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Description',
      value: state.moreDetails,
      onChanged: (v) {
        state.moreDetails = v;
        onMoreDetailsChanged();
      },
      hint: 'e.g., East Facing, Car Parking Available',
      maxLines: 3,
      minLines: 3,
      prefillRevision: prefillRevision,
      propertyType: 'Independent House',
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Contact Name',
            value: state.contactName,
            controller: contactNameController,
            onChanged: (v) {
              state.contactName = v;
              state.errContactName = null;
              onContactNameChanged();
            },
            errorText: state.errContactName,
            prefillRevision: prefillRevision,
            propertyType: 'Independent House',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Contact Number',
            value: state.contactNumber,
            controller: contactNumberController,
            onChanged: (v) {
              state.contactNumber = v;
              state.errContactNumber = null;
              onContactNumberChanged();
            },
            keyboard: TextInputType.phone,
            errorText: state.errContactNumber,
            prefillRevision: prefillRevision,
            propertyType: 'Independent House',
          ),
        ),
      ],
    ),
  ];
}

/// Builds form fields for Apartment property type.
List<Widget> buildApartmentFormFields({
  required ApartmentFormState state,
  required TextEditingController titleController,
  required TextEditingController priceController,
  required TextEditingController contactNameController,
  required TextEditingController contactNumberController,
  required VoidCallback onBedroomsChanged,
  required VoidCallback onAreaChanged,
  required VoidCallback onFloorChanged,
  required VoidCallback onTotalFloorsChanged,
  required VoidCallback onCarParkingChanged,
  required VoidCallback onBuildingAgeChanged,
  required VoidCallback onPriceChanged,
  required VoidCallback onLocationChanged,
  required VoidCallback onTitleChanged,
  required VoidCallback onMoreInfoChanged,
  required VoidCallback onContactNameChanged,
  required VoidCallback onContactNumberChanged,
  required int prefillRevision,
}) {
  const indianPriceFormatters = <TextInputFormatter>[
    IndianCurrencyInputFormatter(),
  ];

  return [
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'BHK',
            value: state.bedrooms,
            onChanged: (v) {
              state.bedrooms = v;
              state.errBedrooms = null;
              onBedroomsChanged();
            },
            hint: 'e.g., 2',
            keyboard: TextInputType.number,
            errorText: state.errBedrooms,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Area (sq.ft.)',
            value: state.area,
            onChanged: (v) {
              state.area = v;
              state.errArea = null;
              onAreaChanged();
            },
            hint: 'e.g., 950',
            keyboard: TextInputType.number,
            errorText: state.errArea,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Property Floor',
            value: state.floor,
            onChanged: (v) {
              state.floor = v;
              state.errFloor = null;
              onFloorChanged();
            },
            hint: 'e.g., 3',
            keyboard: TextInputType.number,
            errorText: state.errFloor,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Total Floors',
            value: state.totalFloors,
            onChanged: (v) {
              state.totalFloors = v;
              state.errTotalFloors = null;
              onTotalFloorsChanged();
            },
            hint: 'e.g., 10',
            keyboard: TextInputType.number,
            errorText: state.errTotalFloors,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyDropdown(
            label: 'Car Parking',
            value: state.carParking.isEmpty ? 'None' : state.carParking,
            options: kCarParkingOptions,
            onChanged: (v) {
              state.carParking = (v == null || v.trim().isEmpty) ? 'None' : v;
              state.errCarParking = null;
              onCarParkingChanged();
            },
            errorText: state.errCarParking,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Building Age (Years)',
            value: state.buildingAgeYears,
            onChanged: (v) {
              state.buildingAgeYears = v;
              state.errBuildingAgeYears = null;
              onBuildingAgeChanged();
            },
            hint: 'e.g., 10',
            keyboard: TextInputType.number,
            errorText: state.errBuildingAgeYears,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Price',
      value: state.price,
      controller: priceController,
      inputFormatters: indianPriceFormatters,
      onChanged: (v) {
        state.price = v;
        state.errPrice = null;
        onPriceChanged();
      },
      hint: 'e.g., ₹65,00,000',
      keyboard: TextInputType.number,
      errorText: state.errPrice,
      prefillRevision: prefillRevision,
      propertyType: 'Apartment',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Locality',
      value: state.location,
      onChanged: (v) {
        state.location = v;
        state.errLocation = null;
        onLocationChanged();
      },
      hint: 'e.g., Anna Nagar, Chennai',
      errorText: state.errLocation,
      prefillRevision: prefillRevision,
      propertyType: 'Apartment',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Property Title',
      value: state.title,
      controller: titleController,
      onChanged: (v) {
        state.title = v;
        onTitleChanged();
      },
      hint: 'e.g., 2 BHK Apartment in Anna Nagar',
      prefillRevision: prefillRevision,
      propertyType: 'Apartment',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Additional Information',
      value: state.moreInfo,
      onChanged: (v) {
        state.moreInfo = v;
        onMoreInfoChanged();
      },
      hint:
          'e.g., Near metro station, includes covered parking, recently renovated',
      maxLines: 3,
      minLines: 3,
      prefillRevision: prefillRevision,
      propertyType: 'Apartment',
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Contact Name',
            value: state.contactName,
            controller: contactNameController,
            onChanged: (v) {
              state.contactName = v;
              onContactNameChanged();
            },
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Contact Number',
            value: state.contactNumber,
            controller: contactNumberController,
            onChanged: (v) {
              state.contactNumber = v;
              onContactNumberChanged();
            },
            keyboard: TextInputType.phone,
            prefillRevision: prefillRevision,
            propertyType: 'Apartment',
          ),
        ),
      ],
    ),
  ];
}

/// Builds form fields for Land property type.
List<Widget> buildLandFormFields({
  required LandFormState state,
  required TextEditingController titleController,
  required TextEditingController priceController,
  required TextEditingController contactNameController,
  required TextEditingController contactNumberController,
  required VoidCallback onLandTypeChanged,
  required VoidCallback onAreaChanged,
  required VoidCallback onPriceChanged,
  required VoidCallback onLocationChanged,
  required VoidCallback onTitleChanged,
  required VoidCallback onMoreInfoChanged,
  required VoidCallback onContactNameChanged,
  required VoidCallback onContactNumberChanged,
  required int prefillRevision,
}) {
  const indianPriceFormatters = <TextInputFormatter>[
    IndianCurrencyInputFormatter(),
  ];

  return [
    PropertyDropdown(
      label: 'Land Type',
      value: state.landType.isEmpty ? 'Select' : state.landType,
      options: <String>['Select', ...kLandTypeValueMap.keys],
      onChanged: (v) {
        final next = (v ?? '').trim();
        state.landType = next == 'Select' ? '' : next;
        state.errLandType = null;
        onLandTypeChanged();
      },
      errorText: state.errLandType,
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Area (sq.ft)',
      value: state.area,
      onChanged: (v) {
        state.area = v;
        state.errArea = null;
        onAreaChanged();
      },
      hint: 'e.g., 2400 sq.ft',
      keyboard: TextInputType.number,
      errorText: state.errArea,
      prefillRevision: prefillRevision,
      propertyType: 'Land',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Price',
      value: state.price,
      controller: priceController,
      inputFormatters: indianPriceFormatters,
      onChanged: (v) {
        state.price = v;
        state.errPrice = null;
        onPriceChanged();
      },
      hint: 'e.g., ₹50,00,000',
      keyboard: TextInputType.number,
      errorText: state.errPrice,
      prefillRevision: prefillRevision,
      propertyType: 'Land',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Locality',
      value: state.location,
      onChanged: (v) {
        state.location = v;
        state.errLocation = null;
        onLocationChanged();
      },
      hint: 'e.g., Anna Nagar, Chennai',
      errorText: state.errLocation,
      prefillRevision: prefillRevision,
      propertyType: 'Land',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Property Title',
      value: state.title,
      controller: titleController,
      onChanged: (v) {
        state.title = v;
        state.errTitle = null;
        onTitleChanged();
      },
      hint: 'e.g., Residential Plot in Anna Nagar',
      errorText: state.errTitle,
      prefillRevision: prefillRevision,
      propertyType: 'Land',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'More Information',
      value: state.moreInfo,
      onChanged: (v) {
        state.moreInfo = v;
        onMoreInfoChanged();
      },
      hint: 'e.g., Near school, 30 ft road access',
      maxLines: 3,
      minLines: 3,
      prefillRevision: prefillRevision,
      propertyType: 'Land',
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Contact Name',
            value: state.contactName,
            controller: contactNameController,
            onChanged: (v) {
              state.contactName = v;
              state.errContactName = null;
              onContactNameChanged();
            },
            errorText: state.errContactName,
            prefillRevision: prefillRevision,
            propertyType: 'Land',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Contact Number',
            value: state.contactNumber,
            controller: contactNumberController,
            onChanged: (v) {
              state.contactNumber = v;
              state.errContactNumber = null;
              onContactNumberChanged();
            },
            keyboard: TextInputType.phone,
            errorText: state.errContactNumber,
            prefillRevision: prefillRevision,
            propertyType: 'Land',
          ),
        ),
      ],
    ),
  ];
}

/// Builds form fields for Commercial Space property type.
List<Widget> buildCommercialFormFields({
  required CommercialFormState state,
  required String listingType,
  required TextEditingController titleController,
  required TextEditingController priceController,
  required TextEditingController contactNameController,
  required TextEditingController contactNumberController,
  required VoidCallback onSpaceTypeChanged,
  required VoidCallback onBuiltUpAreaChanged,
  required VoidCallback onPriceChanged,
  required VoidCallback onLocationChanged,
  required VoidCallback onTitleChanged,
  required VoidCallback onAdditionalDetailsChanged,
  required VoidCallback onContactNameChanged,
  required VoidCallback onContactNumberChanged,
  required int prefillRevision,
}) {
  const indianPriceFormatters = <TextInputFormatter>[
    IndianCurrencyInputFormatter(),
  ];

  final listing = listingType.trim().toLowerCase();
  final priceLabel = listing == 'rent'
      ? 'Monthly Rent'
      : listing == 'lease'
          ? 'Lease Amount'
          : 'Price';
  final priceHint = listing == 'rent'
      ? 'e.g., ₹25,000'
      : listing == 'lease'
          ? 'e.g., ₹10,00,000'
          : 'e.g., ₹45,00,000';

  return [
    PropertyDropdown(
      label: 'Commercial Type',
      value: state.spaceType.isEmpty ? 'Select' : state.spaceType,
      options: <String>['Select', ...kCommercialTypeOptions],
      onChanged: (v) {
        final next = (v ?? '').trim();
        state.spaceType = next == 'Select' ? '' : next;
        state.errSpaceType = null;
        onSpaceTypeChanged();
      },
      errorText: state.errSpaceType,
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Built-up Area (Sq.ft)',
      value: state.builtUpArea,
      onChanged: (v) {
        state.builtUpArea = v;
        state.errBuiltUpArea = null;
        onBuiltUpAreaChanged();
      },
      hint: 'e.g., 1200',
      keyboard: TextInputType.number,
      errorText: state.errBuiltUpArea,
      prefillRevision: prefillRevision,
      propertyType: 'Commercial Space',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: priceLabel,
      value: state.price,
      controller: priceController,
      inputFormatters: indianPriceFormatters,
      onChanged: (v) {
        state.price = v;
        state.errPrice = null;
        onPriceChanged();
      },
      hint: priceHint,
      keyboard: TextInputType.number,
      errorText: state.errPrice,
      prefillRevision: prefillRevision,
      propertyType: 'Commercial Space',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Locality',
      value: state.location,
      onChanged: (v) {
        state.location = v;
        state.errLocation = null;
        onLocationChanged();
      },
      hint: 'e.g., Anna Nagar, Chennai',
      errorText: state.errLocation,
      prefillRevision: prefillRevision,
      propertyType: 'Commercial Space',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Property Title',
      value: state.title,
      controller: titleController,
      onChanged: (v) {
        state.title = v;
        state.errTitle = null;
        onTitleChanged();
      },
      hint: 'e.g., Office Space for Rent in T. Nagar',
      errorText: state.errTitle,
      prefillRevision: prefillRevision,
      propertyType: 'Commercial Space',
    ),
    const SizedBox(height: 12),
    PropertyTextField(
      label: 'Description',
      value: state.additionalDetails,
      onChanged: (v) {
        state.additionalDetails = v;
        onAdditionalDetailsChanged();
      },
      hint: 'e.g., Ground Floor, Road Facing, Car Parking Available',
      maxLines: 3,
      minLines: 3,
      prefillRevision: prefillRevision,
      propertyType: 'Commercial Space',
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: PropertyTextField(
            label: 'Contact Name',
            value: state.contactName,
            controller: contactNameController,
            onChanged: (v) {
              state.contactName = v;
              state.errContactName = null;
              onContactNameChanged();
            },
            errorText: state.errContactName,
            prefillRevision: prefillRevision,
            propertyType: 'Commercial Space',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PropertyTextField(
            label: 'Contact Number',
            value: state.contactNumber,
            controller: contactNumberController,
            onChanged: (v) {
              state.contactNumber = v;
              state.errContactNumber = null;
              onContactNumberChanged();
            },
            keyboard: TextInputType.phone,
            errorText: state.errContactNumber,
            prefillRevision: prefillRevision,
            propertyType: 'Commercial Space',
          ),
        ),
      ],
    ),
  ];
}
