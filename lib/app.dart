import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;

import 'constants/api_constants.dart';
import 'models/map_viewport_models.dart';
import 'screens/layout_detail_screen.dart';
import 'screens/property_detail_screen.dart';
import 'screens/splash_screen.dart';
import 'services/analytics_service.dart';
import 'services/auth_aware_http_client.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'state/auth_scope.dart';
import 'state/auth_state.dart';
import 'utils/route_observer.dart';
import 'widgets/session_expired_dialog.dart';

/// Global navigator key used by the deep-link service to push routes from
/// outside the widget tree.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Singleton deep-link service initialised at app startup.
late final DeepLinkService deepLinkService;

/// Completes when [HomeMapScreen] has initialised and the splash-to-home
/// transition is done.  Push-notification navigation awaits this so it
/// doesn't race with the splash screen's [pushReplacement].
Completer<void> homeScreenReadyCompleter = Completer<void>();

/// Call from [HomeMapScreen.initState] to signal readiness.
void markHomeScreenReady() {
  if (!homeScreenReadyCompleter.isCompleted) {
    homeScreenReadyCompleter.complete();
  }
}

class RMapApp extends StatefulWidget {
  const RMapApp({super.key});

  @override
  State<RMapApp> createState() => _RMapAppState();
}

class _RMapAppState extends State<RMapApp> {
  late final AuthState _authState;

  @override
  void initState() {
    super.initState();
    _authState = AuthState();
    _authState.initialize();

    // When any API call returns 401, force-logout and prompt re-login.
    AuthAwareHttpClient.onSessionExpired = _onSessionExpired;

    deepLinkService = DeepLinkService(navigatorKey: appNavigatorKey);
    deepLinkService.initialize();

    // Handle push notification taps → navigate to property.
    PushNotificationService.instance.onNotificationTap = _onNotificationTap;
  }

  @override
  void dispose() {
    AuthAwareHttpClient.onSessionExpired = null;
    PushNotificationService.instance.onNotificationTap = null;
    deepLinkService.dispose();
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // iPhone X design reference
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return AuthScope(
          authState: _authState,
          child: MaterialApp(
            title: 'R Map',
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: const TextScaler.linear(1.0),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0FAD97),
              ),
              useMaterial3: true,
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0FAD97),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0FAD97),
                  side: const BorderSide(color: Color(0xFF0FAD97)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            navigatorKey: appNavigatorKey,
            navigatorObservers: [
              routeObserver,
              AnalyticsService.instance.observer,
            ],
            home: const SplashScreen(),
          ),
        );
      },
    );
  }

  /// Called by [AuthAwareHttpClient] when any API returns 401.
  /// Clears the stale session and shows a re-login prompt.
  void _onSessionExpired() {
    // Only act if the user was actually logged in.
    if (!_authState.isAuthenticated) return;

    _authState.forceLogout();

    // Show dialog on the next frame so the navigator context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null) {
        SessionExpiredDialog.show(ctx);
      }
      // Allow the interceptor to fire again after the user re-logs in.
      AuthAwareHttpClient.reset();
    });
  }

  /// Navigate to the property detail screen when a push notification is tapped.
  void _onNotificationTap(Map<String, dynamic> data) {
    debugPrint('[Push] _onNotificationTap called with data: $data');
    final propertyId = data['propertyId'] as String?;
    final propertyType = data['propertyType'] as String?;
    if (propertyId == null || propertyId.isEmpty) {
      debugPrint('[Push] Missing propertyId, aborting');
      return;
    }
    if (propertyType == null || propertyType.isEmpty) {
      debugPrint('[Push] Missing propertyType, aborting');
      return;
    }

    debugPrint('[Push] Navigating to $propertyType / $propertyId');
    unawaited(_navigateToPropertyFromNotification(propertyId, propertyType));
  }

  Future<void> _navigateToPropertyFromNotification(
    String propertyId,
    String propertyType,
  ) async {
    // Wait for the home screen to be ready (splash → home replacement done)
    // so that pushReplacement in SplashScreen doesn't clobber our route.
    try {
      await homeScreenReadyCompleter.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      debugPrint('[Push] HomeScreen not ready after 6s, aborting');
      return;
    }

    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      debugPrint('[Push] Navigator not available, aborting');
      return;
    }

    debugPrint('[Push] Navigator ready, route stack:');
    nav.popUntil((route) {
      debugPrint('[Push]   route: ${route.settings.name ?? route.runtimeType}');
      return true; // don't pop, just log
    });

    // Capture context before async gap.
    final navContext = nav.context;

    // Show loading overlay while fetching property details.
    // ignore: use_build_context_synchronously
    _showLoadingOverlay(navContext);
    debugPrint('[Push] Loading overlay shown');

    try {
      debugPrint('[Push] Fetching share summary: $propertyType / $propertyId');
      final summary = await _fetchShareSummary(propertyType, propertyId);
      debugPrint(
          '[Push] Share summary result: ${summary != null ? "OK (keys: ${summary.keys.join(", ")})" : "NULL (404 or error)"}');

      // Dismiss loading overlay.
      if (nav.canPop()) {
        nav.pop();
        debugPrint('[Push] Loading overlay dismissed');
      }

      if (summary == null) {
        debugPrint('[Push] Falling back to minimal feature');
        _navigateWithMinimalFeature(nav, propertyId, propertyType);
        return;
      }

      final featureId = summary['featureId'] as String? ?? propertyId;
      final name = summary['title'] as String? ?? 'Property';
      final resolvedType = summary['propertyType'] as String? ?? propertyType;

      debugPrint(
          '[Push] Resolved: featureId=$featureId, name=$name, type=$resolvedType');

      // Build center GeoJSON from coordinates if available.
      String? centerGeoJson;
      final lat = summary['centerLatitude'];
      final lng = summary['centerLongitude'];
      if (lat is num && lng is num) {
        centerGeoJson = '{"type":"Point","coordinates":[$lng,$lat]}';
      }

      // Handle Layout type separately.
      if (resolvedType.toLowerCase() == 'layout') {
        debugPrint('[Push] Pushing LayoutDetailScreen');
        nav.push(
          MaterialPageRoute(
            builder: (_) => LayoutDetailScreen(
              layoutId: featureId,
              fromDeepLink: true,
            ),
          ),
        );
        return;
      }

      final feature = MapPropertyFeature(
        propertyId: propertyId,
        featureId: featureId,
        propertyType: resolvedType,
        name: name,
        isOwnedByCurrentUser: false,
        listingType: summary['listingLabel'] as String?,
        boundaryGeoJson: null,
        centerGeoJson: centerGeoJson,
        metadata: _buildMetadataFromSummary(summary),
      );

      debugPrint(
          '[Push] Pushing PropertyDetailScreen (featureId=$featureId, type=$resolvedType)');
      nav.push(
        MaterialPageRoute(
          builder: (_) => PropertyDetailScreen(
            feature: feature,
            fromDeepLink: true,
          ),
        ),
      );
      debugPrint('[Push] PropertyDetailScreen pushed successfully');
    } catch (e, stack) {
      // Dismiss loading overlay on error.
      if (nav.canPop()) nav.pop();
      debugPrint('[Push] Navigation error: $e');
      debugPrint('[Push] Stack trace: $stack');
      // Fallback: navigate with minimal data.
      _navigateWithMinimalFeature(nav, propertyId, propertyType);
    }
  }

  void _navigateWithMinimalFeature(
    NavigatorState nav,
    String propertyId,
    String propertyType,
  ) {
    debugPrint(
        '[Push] _navigateWithMinimalFeature: $propertyType / $propertyId');
    final feature = MapPropertyFeature(
      propertyId: propertyId,
      featureId: propertyId,
      propertyType: propertyType,
      name: 'Property',
      isOwnedByCurrentUser: false,
      listingType: null,
      boundaryGeoJson: null,
      centerGeoJson: null,
      metadata: const {},
    );

    nav.push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          feature: feature,
          fromDeepLink: true,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchShareSummary(
    String propertyType,
    String featureId,
  ) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/share/property/'
        '${Uri.encodeComponent(propertyType)}/$featureId';

    debugPrint('[Push] _fetchShareSummary URL: $url');

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      debugPrint('[Push] Share summary HTTP ${response.statusCode}');
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[Push] Share summary body keys: ${body.keys.join(", ")}');
        return body;
      } else {
        debugPrint(
            '[Push] Share summary non-200 body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      }
    } catch (e) {
      debugPrint('[Push] Share summary fetch error: $e');
    }
    return null;
  }

  Map<String, String?> _buildMetadataFromSummary(Map<String, dynamic> s) {
    return <String, String?>{
      if (s['location'] != null) 'location': s['location'] as String?,
      if (s['priceLabel'] != null) 'price': s['priceLabel'] as String?,
      if (s['areaLabel'] != null) 'area': s['areaLabel'] as String?,
      if (s['bedroomsLabel'] != null) 'bedrooms': s['bedroomsLabel'] as String?,
      if (s['listingLabel'] != null) 'listing': s['listingLabel'] as String?,
      if (s['subtitle'] != null) 'subtitle': s['subtitle'] as String?,
      if (s['heroImageUrl'] != null)
        'heroImageUrl': s['heroImageUrl'] as String?,
      if (s['contactName'] != null) 'contactName': s['contactName'] as String?,
      if (s['contactNumbers'] != null)
        'contactNumbers': s['contactNumbers'] as String?,
      if (s['buildingAgeLabel'] != null)
        'buildingAgeYears': s['buildingAgeLabel'] as String?,
      if (s['floorsLabel'] != null) 'floors': s['floorsLabel'] as String?,
      if (s['facingLabel'] != null) 'facing': s['facingLabel'] as String?,
      if (s['shortCode'] != null) 'shortCode': s['shortCode'] as String?,
    };
  }

  void _showLoadingOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Opening property…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
