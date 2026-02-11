import '../models/map_viewport_models.dart';

/// Lightweight cross-route handoff for property selection.
///
/// Used when a deep-link PropertyDetailScreen pops and we want the home map
/// to select that property (show bottom panel + optionally focus camera).
class PendingPropertySelection {
  PendingPropertySelection._();

  static MapPropertyFeature? _pending;

  static void set(MapPropertyFeature feature) {
    _pending = feature;
  }

  static MapPropertyFeature? take() {
    final next = _pending;
    _pending = null;
    return next;
  }

  static bool get hasPending => _pending != null;
}
