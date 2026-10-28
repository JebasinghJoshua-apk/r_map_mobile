import 'package:flutter/foundation.dart';

import '../models/map_viewport_models.dart';

/// Lightweight cross-route handoff for property selection.
///
/// Used by layout shares and when a deep-link detail screen pops to select
/// that property on the home map (bottom panel + optional camera focus).
class PendingPropertySelection {
  PendingPropertySelection._();

  static MapPropertyFeature? _pending;
  static final changes = ValueNotifier<int>(0);

  static void set(MapPropertyFeature feature) {
    _pending = feature;
    changes.value++;
  }

  static MapPropertyFeature? take() {
    final next = _pending;
    _pending = null;
    return next;
  }

  static bool get hasPending => _pending != null;
}
