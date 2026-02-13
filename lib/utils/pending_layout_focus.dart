/// Lightweight cross-route handoff for layout focus.
///
/// Used when a deep-link LayoutDetailScreen pops and we want the home map
/// to focus on that layout (animate camera to fit the layout boundary).
class PendingLayoutFocus {
  PendingLayoutFocus._();

  static String? _pendingLayoutId;

  static void set(String layoutId) {
    _pendingLayoutId = layoutId;
  }

  static String? take() {
    final next = _pendingLayoutId;
    _pendingLayoutId = null;
    return next;
  }

  static bool get hasPending => _pendingLayoutId != null;
}
