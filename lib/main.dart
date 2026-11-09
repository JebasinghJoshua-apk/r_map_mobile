import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/firebase_perf_service.dart';
import 'services/performance_logger.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AppBootstrapper());
}

class _AppBootstrapper extends StatefulWidget {
  const _AppBootstrapper();

  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper> {
  bool _isReady = false;
  Object? _startupError;
  FirebasePerfTraceHandle? _startupTrace;
  bool _postFrameWorkScheduled = false;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      _isReady = false;
      _startupError = null;
    });

    try {
      final initialization = _initialization ??= _initializeApp();
      await initialization.timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _isReady = true;
      });
    } catch (error, stackTrace) {
      if (error is! TimeoutException) {
        _initialization = null;
      }
      debugPrint('[Startup] Initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _startupError = error;
      });
    }
  }

  Future<void> _initializeApp() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    if (Firebase.apps.isEmpty) {
      if (kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS)) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    }

    _startupTrace = await FirebasePerfService.startTrace(
      'app_startup_init_to_first_frame',
    );

    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: true,
      );
      return true;
    };

    if (kDebugMode) {
      await PerformanceLogger.instance.init();
    }

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
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) {
      if (!_postFrameWorkScheduled) {
        _postFrameWorkScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_startupTrace?.stop());
          unawaited(_initializePushNotifications());
        });
      }
      return const RMapApp();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: _startupError == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF0FAD97)),
                      SizedBox(height: 20),
                      Text(
                        'Starting R Map…',
                        style: TextStyle(color: Color(0xFF92A5A8)),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'R Map could not finish starting.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          kReleaseMode
                              ? 'Please try again. If the problem continues, '
                                  'close and reopen the app.'
                              : _startupError.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF92A5A8)),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _initialize,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initializePushNotifications() async {
  try {
    await PushNotificationService.instance
        .initialize()
        .timeout(const Duration(seconds: 20));
  } catch (error, stackTrace) {
    debugPrint('[Push] Initialization did not complete: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
