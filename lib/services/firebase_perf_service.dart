import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';

class FirebasePerfTraceHandle {
  FirebasePerfTraceHandle._(this._trace);

  final Trace _trace;
  bool _stopped = false;

  void putAttribute(String key, String value) {
    if (_stopped) return;
    try {
      _trace.putAttribute(key, value);
    } catch (_) {}
  }

  void putMetric(String key, int value) {
    if (_stopped) return;
    try {
      _trace.setMetric(key, value);
    } catch (_) {}
  }

  void incrementMetric(String key, int by) {
    if (_stopped) return;
    try {
      _trace.incrementMetric(key, by);
    } catch (_) {}
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _trace.stop();
    } catch (_) {}
  }
}

class FirebasePerfService {
  FirebasePerfService._();

  static bool get _enabled =>
      !kDebugMode && ApiConstants.enableFirebasePerfTraces;

  static Future<FirebasePerfTraceHandle?> startTrace(
    String name, {
    Map<String, String>? attributes,
  }) async {
    if (!_enabled) return null;

    try {
      final trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
      final handle = FirebasePerfTraceHandle._(trace);
      if (attributes != null) {
        for (final entry in attributes.entries) {
          handle.putAttribute(entry.key, entry.value);
        }
      }
      return handle;
    } catch (_) {
      return null;
    }
  }
}
