import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'models/map_viewport_models.dart';
import 'screens/property_detail_screen.dart';
import 'screens/splash_screen.dart';
import 'services/analytics_service.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'state/auth_scope.dart';
import 'state/auth_state.dart';
import 'utils/route_observer.dart';

/// Global navigator key used by the deep-link service to push routes from
/// outside the widget tree.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Singleton deep-link service initialised at app startup.
late final DeepLinkService deepLinkService;

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

    deepLinkService = DeepLinkService(navigatorKey: appNavigatorKey);
    deepLinkService.initialize();

    // Handle push notification taps → navigate to property.
    PushNotificationService.instance.onNotificationTap = _onNotificationTap;
  }

  @override
  void dispose() {
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

  /// Navigate to the property detail screen when a push notification is tapped.
  void _onNotificationTap(Map<String, dynamic> data) {
    final propertyId = data['propertyId'] as String?;
    final propertyType = data['propertyType'] as String?;
    if (propertyId == null || propertyId.isEmpty) return;

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    final feature = MapPropertyFeature(
      propertyId: propertyId,
      featureId: propertyId,
      propertyType: propertyType ?? 'IndependentHouse',
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
}
