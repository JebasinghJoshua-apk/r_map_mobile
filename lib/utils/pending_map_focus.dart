import 'package:google_maps_flutter/google_maps_flutter.dart';

class PendingMapFocusRequest {
  const PendingMapFocusRequest({
    required this.propertyId,
    required this.boundaryPoints,
  });

  final String propertyId;
  final List<LatLng> boundaryPoints;
}

/// Lightweight cross-route handoff for camera focus.
///
/// Used when a flow pops multiple routes (e.g. `popUntil(isFirst)`) and we still
/// want the map to perform a camera animation afterwards.
class PendingMapFocus {
  PendingMapFocus._();

  static PendingMapFocusRequest? _pending;

  static void set(PendingMapFocusRequest request) {
    _pending = request;
  }

  static PendingMapFocusRequest? take() {
    final next = _pending;
    _pending = null;
    return next;
  }
}
