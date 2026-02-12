/// Lightweight cross-route handoff for plot focus from deep links.
///
/// Used when a deep-link arrives for a specific plot and we want the home map
/// to focus/highlight that plot.
class PendingPlotSelection {
  PendingPlotSelection._();

  static PlotFocusData? _pending;

  static void set({
    required String layoutFeatureId,
    required String plotId,
    double? centerLatitude,
    double? centerLongitude,
  }) {
    _pending = PlotFocusData(
      layoutFeatureId: layoutFeatureId,
      plotId: plotId,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
    );
  }

  static PlotFocusData? take() {
    final next = _pending;
    _pending = null;
    return next;
  }

  static bool get hasPending => _pending != null;
}

/// Plot focus data for deep-link navigation.
class PlotFocusData {
  const PlotFocusData({
    required this.layoutFeatureId,
    required this.plotId,
    this.centerLatitude,
    this.centerLongitude,
  });

  final String layoutFeatureId;
  final String plotId;
  final double? centerLatitude;
  final double? centerLongitude;
}
