import 'package:flutter/material.dart';

import 'screens/home_map_screen.dart';
import 'state/auth_scope.dart';
import 'state/auth_state.dart';

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeMapScreen(),
      ),
    );
  }
}
