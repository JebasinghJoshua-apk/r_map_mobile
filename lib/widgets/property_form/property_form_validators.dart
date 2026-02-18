import 'property_form_constants.dart';
import 'property_type_forms.dart';

/// Result of form validation containing the payload and API endpoint type.
class ValidationResult {
  const ValidationResult({
    required this.isValid,
    this.payload,
    this.createType,
    this.errorMessage,
  });

  final bool isValid;
  final Map<String, dynamic>? payload;
  final String? createType;
  final String? errorMessage;

  static const invalid = ValidationResult(isValid: false);
}

/// Normalizes a contact number to digits only (with optional + prefix).
String normalizeContact(String raw) {
  final trimmed = raw.trim();
  final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.isEmpty) return '';
  return trimmed.startsWith('+') ? '+$digitsOnly' : digitsOnly;
}

/// Parses a string to double, handling comma-formatted numbers.
double? parseDouble(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned.replaceAll(',', ''));
}

/// Parses a string to int.
int? parseInt(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned);
}

/// Resolves listing type for API payload.
String listingTypeForPayload(String listingType) {
  final v = listingType.trim();
  if (v.isEmpty) return 'Sell';
  if (v == 'Buy') return 'Sell';
  return v;
}

/// Validates Plot form and returns payload if valid.
ValidationResult validatePlotForm({
  required PlotFormState state,
  required String listingType,
  required String boundaryGeoJson,
}) {
  final title = state.title.trim();
  final areaRaw = state.area.trim();
  final area = parseDouble(areaRaw);
  final location = state.location.trim();
  final description = state.moreDetails.trim();
  final priceRaw = state.price.trim();
  final price = parseDouble(priceRaw);
  final contactName = state.contactName.trim();
  final normalizedContact = normalizeContact(state.contactNumber);

  var hasError = false;

  if (areaRaw.isEmpty) {
    hasError = true;
    state.errArea = 'Plot area is required.';
  } else if (area == null || area <= 0) {
    hasError = true;
    state.errArea = 'Plot area must be greater than zero.';
  }

  if (priceRaw.isEmpty) {
    hasError = true;
    state.errPrice = 'Price is required.';
  } else if (price == null || price <= 0) {
    hasError = true;
    state.errPrice = 'Price must be greater than zero.';
  }

  if (location.isEmpty) {
    hasError = true;
    state.errLocation = 'Locality is required.';
  }

  if (title.isEmpty) {
    hasError = true;
    state.errTitle = 'Property title is required.';
  }

  if (contactName.isEmpty) {
    hasError = true;
    state.errContactName = 'Contact name is required.';
  }

  if (state.contactNumber.trim().isEmpty) {
    hasError = true;
    state.errContactNumber = 'Contact number is required.';
  } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
    hasError = true;
    state.errContactNumber = 'Enter a valid contact number.';
  }

  if (hasError) {
    return ValidationResult.invalid;
  }

  final payload = <String, dynamic>{
    'listingType': listingTypeForPayload(listingType),
    'propertyTitle': title,
    'areaLabel': areaRaw,
    'price': price,
    'location': location,
    'additionalInformation': description.isEmpty ? null : description,
    'contactName': contactName,
    'contactNumber': normalizedContact,
    'plots': <Map<String, dynamic>>[
      <String, dynamic>{
        'label': 'Plot 1',
        'polygonGeoJson': boundaryGeoJson,
      }
    ],
    'roads': const <Map<String, dynamic>>[],
  };

  return ValidationResult(
    isValid: true,
    payload: payload,
    createType: 'individual-plots',
  );
}

/// Validates Independent House form and returns payload if valid.
ValidationResult validateHouseForm({
  required HouseFormState state,
  required String listingType,
  required String boundaryGeoJson,
}) {
  final title = state.title.trim();
  final location = state.location.trim();
  final bedrooms = parseInt(state.bedrooms);
  final builtUpArea = parseDouble(state.builtUpArea);
  final floors = parseInt(state.floors);
  final buildingAge = parseInt(state.buildingAgeYears);
  final carParkingRaw = state.carParking.trim();
  final carParkingCount =
      parseCarParkingCount(carParkingRaw.isEmpty ? 'None' : carParkingRaw);
  final price = parseDouble(state.price);
  final contactName = state.contactName.trim();
  final normalizedContact = normalizeContact(state.contactNumber);

  var hasError = false;

  if (location.isEmpty) {
    hasError = true;
    state.errLocation = 'Locality is required.';
  }

  if (state.bedrooms.trim().isEmpty) {
    hasError = true;
    state.errBedrooms = 'Bedrooms is required.';
  } else if (bedrooms == null || bedrooms <= 0) {
    hasError = true;
    state.errBedrooms = 'Bedrooms must be a positive whole number.';
  }

  if (state.builtUpArea.trim().isEmpty) {
    hasError = true;
    state.errBuiltUpArea = 'Built-up area is required.';
  } else if (builtUpArea == null || builtUpArea <= 0) {
    hasError = true;
    state.errBuiltUpArea = 'Built-up area must be greater than zero.';
  }

  if (state.floors.trim().isEmpty) {
    hasError = true;
    state.errFloors = 'Floors is required.';
  } else if (floors == null || floors <= 0) {
    hasError = true;
    state.errFloors = 'Floors must be a positive whole number.';
  }

  if (carParkingRaw.isEmpty) {
    hasError = true;
    state.errCarParking = 'Car parking is required.';
  } else if (carParkingCount < 0) {
    hasError = true;
    state.errCarParking = 'Invalid car parking value.';
  }

  if (state.price.trim().isEmpty) {
    hasError = true;
    state.errPrice = 'Price is required.';
  } else if (price == null || price <= 0) {
    hasError = true;
    state.errPrice = 'Price must be greater than zero.';
  }

  if (title.isEmpty) {
    hasError = true;
    state.errTitle = 'Property title is required.';
  }

  if (contactName.isEmpty) {
    hasError = true;
    state.errContactName = 'Contact name is required.';
  }

  if (state.contactNumber.trim().isEmpty) {
    hasError = true;
    state.errContactNumber = 'Contact number is required.';
  } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
    hasError = true;
    state.errContactNumber = 'Enter a valid contact number.';
  }

  if (hasError) {
    return ValidationResult.invalid;
  }

  if (buildingAge != null && buildingAge < 0) {
    return const ValidationResult(
      isValid: false,
      errorMessage: 'Building age cannot be negative.',
    );
  }

  final payload = <String, dynamic>{
    'listingType': listingTypeForPayload(listingType),
    'propertyType': kPropertyTypeValueMap['Independent House'],
    'propertyTitle': title,
    'bedrooms': bedrooms,
    'builtUpAreaInSquareFeet': builtUpArea,
    'floors': floors,
    'buildingAge': buildingAge,
    'carParkingCount': carParkingCount,
    'price': price,
    'location': location,
    'additionalDetails':
        state.moreDetails.trim().isEmpty ? null : state.moreDetails.trim(),
    'contactName': contactName,
    'contactNumber': normalizedContact,
    'houseBoundaryGeoJson': boundaryGeoJson,
  };

  return ValidationResult(
    isValid: true,
    payload: payload,
    createType: 'independent-houses',
  );
}

/// Validates Apartment form and returns payload if valid.
ValidationResult validateApartmentForm({
  required ApartmentFormState state,
  required String listingType,
  required String boundaryGeoJson,
}) {
  final title = state.title.trim();
  final location = state.location.trim();
  final bedrooms = parseInt(state.bedrooms);
  final area = parseDouble(state.area);
  final floor = parseInt(state.floor);
  final totalFloors = parseInt(state.totalFloors);
  final buildingAge = parseInt(state.buildingAgeYears);
  final carParkingRaw = state.carParking.trim();
  final carParkingCount =
      parseCarParkingCount(carParkingRaw.isEmpty ? 'None' : carParkingRaw);
  final price = parseDouble(state.price);

  var hasError = false;

  if (location.isEmpty) {
    hasError = true;
    state.errLocation = 'Locality is required.';
  }

  if (state.bedrooms.trim().isEmpty) {
    hasError = true;
    state.errBedrooms = 'BHK is required.';
  } else if (bedrooms == null || bedrooms <= 0) {
    hasError = true;
    state.errBedrooms = 'BHK must be a positive whole number.';
  }

  if (state.area.trim().isEmpty) {
    hasError = true;
    state.errArea = 'Area is required.';
  } else if (area == null || area <= 0) {
    hasError = true;
    state.errArea = 'Area must be greater than zero.';
  }

  if (state.floor.trim().isEmpty) {
    hasError = true;
    state.errFloor = 'Property floor is required.';
  } else if (floor == null || floor < 0) {
    hasError = true;
    state.errFloor = 'Floor must be zero or greater.';
  }

  if (state.totalFloors.trim().isEmpty) {
    hasError = true;
    state.errTotalFloors = 'Total floors is required.';
  } else if (totalFloors == null || totalFloors <= 0) {
    hasError = true;
    state.errTotalFloors = 'Total floors must be a positive whole number.';
  }

  if (carParkingRaw.isEmpty) {
    hasError = true;
    state.errCarParking = 'Car parking is required.';
  } else if (carParkingCount < 0) {
    hasError = true;
    state.errCarParking = 'Invalid car parking value.';
  }

  if (state.buildingAgeYears.trim().isEmpty) {
    hasError = true;
    state.errBuildingAgeYears = 'Building age is required.';
  } else if (buildingAge == null || buildingAge < 0) {
    hasError = true;
    state.errBuildingAgeYears = 'Building age must be zero or greater.';
  }

  if (state.price.trim().isEmpty) {
    hasError = true;
    state.errPrice = 'Price is required.';
  } else if (price == null || price <= 0) {
    hasError = true;
    state.errPrice = 'Price must be greater than zero.';
  }

  if (floor != null && totalFloors != null && floor > totalFloors) {
    hasError = true;
    state.errFloor = 'Floor cannot exceed total floors.';
  }

  if (hasError) {
    return ValidationResult.invalid;
  }

  if (title.isEmpty) {
    return const ValidationResult(
      isValid: false,
      errorMessage: 'Enter a property title.',
    );
  }

  final contactName = state.contactName.trim();
  if (contactName.isEmpty) {
    return const ValidationResult(
      isValid: false,
      errorMessage: 'Contact name is required.',
    );
  }

  final normalizedContact = normalizeContact(state.contactNumber);
  if (normalizedContact.isEmpty || normalizedContact.length < 6) {
    return const ValidationResult(
      isValid: false,
      errorMessage: 'Enter a valid contact number.',
    );
  }

  final payload = <String, dynamic>{
    'listingType': listingTypeForPayload(listingType),
    'propertyTitle': title,
    'bedrooms': bedrooms,
    'areaInSquareFeet': area,
    'floor': floor,
    'totalFloors': totalFloors,
    'carParkingCount': carParkingCount,
    'buildingAge': buildingAge,
    'price': price,
    'location': location,
    'additionalInformation':
        state.moreInfo.trim().isEmpty ? null : state.moreInfo.trim(),
    'contactName': contactName,
    'contactNumber': normalizedContact,
    'boundaryGeoJson': boundaryGeoJson,
  };

  return ValidationResult(
    isValid: true,
    payload: payload,
    createType: 'apartment-flats',
  );
}

/// Validates Land form and returns payload if valid.
ValidationResult validateLandForm({
  required LandFormState state,
  required String listingType,
  required String boundaryGeoJson,
}) {
  final title = state.title.trim();
  final landType = state.landType.trim();
  final landTypeValue = kLandTypeValueMap[landType];
  final areaRaw = state.area.trim();
  final priceRaw = state.price.trim();
  final price = parseDouble(priceRaw);
  final location = state.location.trim();
  final contactName = state.contactName.trim();
  final normalizedContact = normalizeContact(state.contactNumber);

  var hasError = false;

  if (title.isEmpty) {
    hasError = true;
    state.errTitle = 'Property title is required.';
  }

  if (landTypeValue == null) {
    hasError = true;
    state.errLandType = 'Land type is required.';
  }

  if (areaRaw.isEmpty) {
    hasError = true;
    state.errArea = 'Area is required.';
  }

  if (priceRaw.isEmpty) {
    hasError = true;
    state.errPrice = 'Price is required.';
  } else if (price == null || price <= 0) {
    hasError = true;
    state.errPrice = 'Price must be greater than zero.';
  }

  if (location.isEmpty) {
    hasError = true;
    state.errLocation = 'Locality is required.';
  }

  if (contactName.isEmpty) {
    hasError = true;
    state.errContactName = 'Contact name is required.';
  }

  if (state.contactNumber.trim().isEmpty) {
    hasError = true;
    state.errContactNumber = 'Contact number is required.';
  } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
    hasError = true;
    state.errContactNumber = 'Enter a valid contact number.';
  }

  if (hasError) {
    return ValidationResult.invalid;
  }

  final payload = <String, dynamic>{
    'listingType': listingTypeForPayload(listingType),
    'propertyTitle': title,
    'landType': landTypeValue,
    'areaLabel': areaRaw,
    'price': price,
    'location': location,
    'additionalInformation':
        state.moreInfo.trim().isEmpty ? null : state.moreInfo.trim(),
    'contactName': contactName,
    'contactNumber': normalizedContact,
    'boundaryGeoJson': boundaryGeoJson,
    'roads': const <Map<String, dynamic>>[],
  };

  return ValidationResult(
    isValid: true,
    payload: payload,
    createType: 'lands',
  );
}

/// Validates Commercial Space form and returns payload if valid.
ValidationResult validateCommercialForm({
  required CommercialFormState state,
  required String listingType,
  required String boundaryGeoJson,
  String? errListingType,
}) {
  final title = state.title.trim();
  final location = state.location.trim();
  final builtUpArea = parseDouble(state.builtUpArea);
  final price = parseDouble(state.price);
  final contactName = state.contactName.trim();
  final normalizedContact = normalizeContact(state.contactNumber);
  final spaceTypeValue = state.spaceType.trim();

  final listingLower = listingType.trim().toLowerCase();
  final priceLabel = listingLower == 'rent'
      ? 'Monthly rent'
      : listingLower == 'lease'
          ? 'Lease amount'
          : 'Price';

  var hasError = false;
  String? listingErr;

  if (listingType.trim().isEmpty) {
    hasError = true;
    listingErr = 'Select a transaction type.';
  }

  if (spaceTypeValue.isEmpty) {
    hasError = true;
    state.errSpaceType = 'Select a commercial type.';
  }

  if (title.isEmpty) {
    hasError = true;
    state.errTitle = 'Property title is required.';
  }

  if (location.isEmpty) {
    hasError = true;
    state.errLocation = 'Locality is required.';
  }

  if (state.builtUpArea.trim().isEmpty) {
    hasError = true;
    state.errBuiltUpArea = 'Built-up area is required.';
  } else if (builtUpArea == null || builtUpArea <= 0) {
    hasError = true;
    state.errBuiltUpArea = 'Built-up area must be greater than zero.';
  }

  if (state.price.trim().isEmpty) {
    hasError = true;
    state.errPrice = '$priceLabel is required.';
  } else if (price == null || price <= 0) {
    hasError = true;
    state.errPrice = '$priceLabel must be greater than zero.';
  }

  if (contactName.isEmpty) {
    hasError = true;
    state.errContactName = 'Contact name is required.';
  }

  if (state.contactNumber.trim().isEmpty) {
    hasError = true;
    state.errContactNumber = 'Contact number is required.';
  } else if (normalizedContact.isEmpty || normalizedContact.length < 6) {
    hasError = true;
    state.errContactNumber = 'Enter a valid contact number.';
  }

  if (hasError) {
    return ValidationResult(
      isValid: false,
      errorMessage: listingErr,
    );
  }

  final payload = <String, dynamic>{
    'listingType': listingTypeForPayload(listingType),
    'propertyTitle': title,
    'spaceType': spaceTypeValue.isEmpty ? null : spaceTypeValue,
    'builtUpAreaInSquareFeet': builtUpArea,
    'price': price,
    'location': location,
    'additionalDetails': state.additionalDetails.trim().isEmpty
        ? null
        : state.additionalDetails.trim(),
    'contactName': contactName,
    'contactNumber': normalizedContact,
    'boundaryGeoJson': boundaryGeoJson,
    'roads': const <Map<String, dynamic>>[],
  };

  return ValidationResult(
    isValid: true,
    payload: payload,
    createType: 'commercial-spaces',
  );
}
