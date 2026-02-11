/// Constants and type mappings for the property form.
library;

/// Maximum number of photos allowed per property.
const int kMaxPropertyPhotos = 12;

/// Available property types.
const List<String> kPropertyTypes = <String>[
  'Plot',
  'Independent House',
  'Apartment',
  'Land',
  'Commercial Space',
];

/// Available listing types (Sell/Rent/Lease).
const List<String> kListingTypes = <String>[
  'Sell',
  'Rent',
  'Lease',
];

/// Commercial space type options.
const List<String> kCommercialTypeOptions = <String>[
  'Office Space',
  'Shop',
  'Showroom',
  'Warehouse / Godown',
  'Industrial Shed',
  'Industrial Building',
  'Restaurant / Cafe Space',
  'Other',
];

/// Car parking dropdown options.
const List<String> kCarParkingOptions = <String>[
  'None',
  '1',
  '2',
  '3',
  '4+',
];

/// Maps property type labels to their API integer values.
const Map<String, int> kPropertyTypeValueMap = <String, int>{
  'Individual Plots': 0,
  'Independent House': 1,
  'Apartment/Flat': 2,
  'Apartment': 2,
  'Land': 3,
  'Commercial Space': 4,
};

/// Maps land type labels to their API integer values.
const Map<String, int> kLandTypeValueMap = <String, int>{
  'Agricultural': 0,
  'Residential': 1,
  'Commercial': 2,
  'Industrial': 3,
};

/// Returns the media API key for a given property type label.
String mediaKeyForPropertyType(String propertyTypeLabel) {
  switch (propertyTypeLabel.trim()) {
    case 'Plot':
      return 'individualplots';
    case 'Independent House':
      return 'independenthouse';
    case 'Apartment':
      return 'apartmentflat';
    case 'Commercial Space':
      return 'commercialspace';
    case 'Land':
    default:
      return 'land';
  }
}

/// Returns the land type label for a given API value.
String landTypeLabelFromValue(int? value) {
  if (value == null) return '';
  for (final entry in kLandTypeValueMap.entries) {
    if (entry.value == value) return entry.key;
  }
  return '';
}

/// Returns the car parking label from a count value.
String carParkingLabelFromCount(int? count) {
  final v = count ?? 0;
  if (v <= 0) return 'None';
  if (v >= 4) return '4+';
  return v.toString();
}

/// Parses a car parking label to an integer count.
int parseCarParkingCount(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 0;
  if (v.toLowerCase() == 'none') return 0;
  if (v.toLowerCase() == 'available') return 1;
  final cleaned = v.replaceAll('+', '').trim();
  return int.tryParse(cleaned) ?? 0;
}
