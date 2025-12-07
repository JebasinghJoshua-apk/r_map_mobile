import 'package:flutter/material.dart';

import 'screens/home_map_screen.dart';

class RMapApp extends StatelessWidget {
  const RMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeMapScreen(),
    );
  }
}
