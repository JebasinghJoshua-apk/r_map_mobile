import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'state/auth_scope.dart';
import 'state/auth_state.dart';
import 'utils/route_observer.dart';

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
  }

  @override
  void dispose() {
    _authState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        navigatorObservers: [routeObserver],
        home: const SplashScreen(),
      ),
    );
  }
}
