import 'package:google_place/google_place.dart';

const String googlePlacesApiKey = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: 'AIzaSyCY-mEvaGFsjSCLSNruAE2jNtfEKOYmgTU',
);

const LatLon tamilNaduBiasPoint = LatLon(11.1271, 78.6569);
const int tamilNaduRadiusMeters = 400000;
const String recentPlacesStorageKey = 'rmap_recent_places_v1';
