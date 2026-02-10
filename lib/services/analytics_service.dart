import 'package:firebase_analytics/firebase_analytics.dart';

/// Lightweight wrapper around Firebase Analytics.
///
/// All calls are fire-and-forget — Firebase batches events internally and
/// uploads them in the background, so there is zero UI-thread overhead.
///
/// Usage:
///   AnalyticsService.instance.logScreenView('HomeMap');
///   AnalyticsService.instance.logLayoutViewed(layoutId: '...', layoutName: '...');
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Expose the observer so MaterialApp can auto-track route changes.
  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ─── Screen tracking ───────────────────────────────────────────────

  Future<void> logScreenView(String screenName) {
    return _analytics.logScreenView(screenName: screenName);
  }

  // ─── Layout / property events ──────────────────────────────────────

  Future<void> logLayoutViewed({
    required String layoutId,
    String? layoutName,
  }) {
    return _analytics.logEvent(
      name: 'layout_viewed',
      parameters: {
        'layout_id': layoutId,
        if (layoutName != null) 'layout_name': layoutName,
      },
    );
  }

  Future<void> logPropertyViewed({
    required String propertyId,
    required String propertyType,
    String? propertyName,
  }) {
    return _analytics.logEvent(
      name: 'property_viewed',
      parameters: {
        'property_id': propertyId,
        'property_type': propertyType,
        if (propertyName != null) 'property_name': propertyName,
      },
    );
  }

  // ─── Plot events ──────────────────────────────────────────────────

  Future<void> logPlotTapped({
    required String plotId,
    required String layoutId,
    String? plotNumber,
    String? status,
  }) {
    return _analytics.logEvent(
      name: 'plot_tapped',
      parameters: {
        'plot_id': plotId,
        'layout_id': layoutId,
        if (plotNumber != null) 'plot_number': plotNumber,
        if (status != null) 'status': status,
      },
    );
  }

  Future<void> logPlotStatusChanged({
    required String plotId,
    required String layoutId,
    required String oldStatus,
    required String newStatus,
  }) {
    return _analytics.logEvent(
      name: 'plot_status_changed',
      parameters: {
        'plot_id': plotId,
        'layout_id': layoutId,
        'old_status': oldStatus,
        'new_status': newStatus,
      },
    );
  }

  // ─── Map events ───────────────────────────────────────────────────

  Future<void> logMapSearch({required String query}) {
    return _analytics.logSearch(searchTerm: query);
  }

  Future<void> logMapFilterApplied({Map<String, Object>? filters}) {
    return _analytics.logEvent(
      name: 'map_filter_applied',
      parameters: filters,
    );
  }

  // ─── Auth events ──────────────────────────────────────────────────

  Future<void> logLogin({String method = 'email'}) {
    return _analytics.logLogin(loginMethod: method);
  }

  Future<void> logSignUp({String method = 'email'}) {
    return _analytics.logSignUp(signUpMethod: method);
  }

  Future<void> logLogout() {
    return _analytics.logEvent(name: 'logout');
  }

  /// Set the user ID for all subsequent events (call on login, clear on logout).
  Future<void> setUserId(String? userId) {
    return _analytics.setUserId(id: userId);
  }

  // ─── Share / save events ──────────────────────────────────────────

  Future<void> logShare({
    required String contentType,
    required String itemId,
    String method = 'link',
  }) {
    return _analytics.logShare(
      contentType: contentType,
      itemId: itemId,
      method: method,
    );
  }

  Future<void> logPropertySaved({
    required String propertyId,
    required String propertyType,
  }) {
    return _analytics.logEvent(
      name: 'property_saved',
      parameters: {
        'property_id': propertyId,
        'property_type': propertyType,
      },
    );
  }

  Future<void> logCallInitiated({
    required String propertyId,
    required String propertyType,
  }) {
    return _analytics.logEvent(
      name: 'call_initiated',
      parameters: {
        'property_id': propertyId,
        'property_type': propertyType,
      },
    );
  }

  // ─── Generic custom event ─────────────────────────────────────────

  Future<void> logCustomEvent(
    String name, {
    Map<String, Object>? parameters,
  }) {
    return _analytics.logEvent(name: name, parameters: parameters);
  }
}
