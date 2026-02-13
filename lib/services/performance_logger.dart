import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Performance logger for tracing viewport rendering performance.
/// Only logs in debug mode and writes to a local file.
class PerformanceLogger {
  PerformanceLogger._();
  static final instance = PerformanceLogger._();

  File? _logFile;
  final _timers = <String, Stopwatch>{};
  final _buffer = StringBuffer();
  int _requestCounter = 0;

  /// Initialize the logger (must be called once, typically in main.dart).
  Future<void> init() async {
    if (!kDebugMode) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/viewport_perf.log');

      // Clear previous log on startup
      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }
      await _logFile!.create();

      await _log('=== Viewport Performance Log ===');
      await _log('Started: ${DateTime.now().toIso8601String()}');
      await _log('');
    } catch (e) {
      debugPrint('PerformanceLogger init failed: $e');
    }
  }

  /// Start a new viewport request session.
  int startRequest() {
    if (!kDebugMode) return 0;
    _requestCounter++;
    _timers.clear();
    _buffer.clear();
    _buffer.writeln('');
    _buffer.writeln(
        '=== Request #$_requestCounter @ ${DateTime.now().toIso8601String()} ===');
    return _requestCounter;
  }

  /// Start a timer with a given label.
  void startTimer(String label) {
    if (!kDebugMode) return;
    _timers[label] = Stopwatch()..start();
  }

  /// Stop a timer and record the elapsed time.
  int stopTimer(String label) {
    if (!kDebugMode) return 0;
    final stopwatch = _timers[label];
    if (stopwatch == null) return 0;

    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    _buffer.writeln('  $label: ${elapsed}ms');
    return elapsed;
  }

  /// Log additional data (e.g., response size, polygon count).
  void logData(String label, dynamic value) {
    if (!kDebugMode) return;
    _buffer.writeln('  $label: $value');
  }

  /// Finish the request and write the buffer to the log file.
  Future<void> finishRequest() async {
    if (!kDebugMode || _logFile == null) return;

    try {
      final totalTimer = _timers['total'];
      if (totalTimer != null && totalTimer.isRunning) {
        totalTimer.stop();
        _buffer.writeln('  TOTAL: ${totalTimer.elapsedMilliseconds}ms');
      }

      _buffer.writeln('');
      await _logFile!.writeAsString(
        _buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );

      debugPrint(_buffer.toString());
    } catch (e) {
      debugPrint('PerformanceLogger write failed: $e');
    }
  }

  Future<void> _log(String message) async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(
        '$message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Get the log file path for external access.
  String? get logFilePath => _logFile?.path;
}
