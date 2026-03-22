/// Lightweight cross-route handoff for layout focus.
///
/// Used when a deep-link LayoutDetailScreen pops and we want the home map
/// to focus on that layout (animate camera to fit the layout boundary).
class PendingLayoutFocus {
  PendingLayoutFocus._();

  static String? _pendingLayoutId;
  static String? _pendingBoundaryGeoJson;

  static void set(String layoutId, {String? boundaryGeoJson}) {
    _pendingLayoutId = layoutId;
    _pendingBoundaryGeoJson = boundaryGeoJson;
  }

  static ({String layoutId, String? boundaryGeoJson})? take() {
    final id = _pendingLayoutId;
    if (id == null) return null;
    final boundary = _pendingBoundaryGeoJson;
    _pendingLayoutId = null;
    _pendingBoundaryGeoJson = null;
    return (layoutId: id, boundaryGeoJson: boundary);
  }

  static bool get hasPending => _pendingLayoutId != null;
}
