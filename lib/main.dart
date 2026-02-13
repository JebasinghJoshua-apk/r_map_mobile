import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'services/performance_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (analytics is auto-enabled, zero UI-thread cost).
  await Firebase.initializeApp();

  // Initialize performance logger (debug mode only).
  if (kDebugMode) {
    await PerformanceLogger.instance.init();
  }

  // Avoid drawing content behind Android system navigation buttons.
  // Some OEMs (notably Samsung) can render a transparent nav bar in edge-to-edge,
  // making the back/home buttons hard to see over maps.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );

  final platformBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  final isDarkMode = platformBrightness == Brightness.dark;

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: isDarkMode ? Colors.black : Colors.white,
    systemNavigationBarDividerColor: isDarkMode ? Colors.black : Colors.white,
    systemNavigationBarIconBrightness:
        isDarkMode ? Brightness.light : Brightness.dark,
  ));
  runApp(const RMapApp());
}
