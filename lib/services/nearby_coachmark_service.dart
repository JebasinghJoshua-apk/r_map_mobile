import 'package:shared_preferences/shared_preferences.dart';

/// Manages the lifecycle of the "Nearby layouts" button coachmark & pulse.
///
/// Flow:
///   1. First app open after update → show coachmark tooltip.
///   2. If dismissed (not clicked) → show soft pulse on next 2 sessions.
///   3. After first click → remove all highlights forever (for this version).
class NearbyCoachmarkService {
  NearbyCoachmarkService._();
  static final NearbyCoachmarkService instance = NearbyCoachmarkService._();

  static const String _keyVersion = 'rmap_nearby_coachmark_version';
  static const String _keyClicked = 'rmap_nearby_coachmark_clicked';
  static const String _keyPulseRemaining = 'rmap_nearby_pulse_remaining';

  /// Bump this string whenever you want the coachmark to re-appear after an
  /// app update that adds meaningful nearby-list changes.
  static const String _currentCoachmarkVersion = '1';

  SharedPreferences? _prefs;

  bool _shouldShowCoachmark = false;
  bool _shouldShowPulse = false;

  /// True when the full coachmark overlay should be displayed.
  bool get shouldShowCoachmark => _shouldShowCoachmark;

  /// True when only the subtle pulse ring should be displayed.
  bool get shouldShowPulse => _shouldShowPulse;

  /// Initialise and resolve which state to show.
  /// Call once when the map screen mounts.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;

    final savedVersion = prefs.getString(_keyVersion);
    final clicked = prefs.getBool(_keyClicked) ?? false;

    // New coachmark version → reset everything.
    if (savedVersion != _currentCoachmarkVersion) {
      await prefs.setString(_keyVersion, _currentCoachmarkVersion);
      await prefs.setBool(_keyClicked, false);
      await prefs.setInt(_keyPulseRemaining, 0);
      _shouldShowCoachmark = true;
      _shouldShowPulse = false;
      return;
    }

    // Already clicked → nothing to show.
    if (clicked) {
      _shouldShowCoachmark = false;
      _shouldShowPulse = false;
      return;
    }

    // Coachmark was shown in a previous session — check pulse.
    final pulseRemaining = prefs.getInt(_keyPulseRemaining) ?? 0;
    if (pulseRemaining > 0) {
      _shouldShowCoachmark = false;
      _shouldShowPulse = true;
      // Consume one pulse session.
      await prefs.setInt(_keyPulseRemaining, pulseRemaining - 1);
    } else {
      _shouldShowCoachmark = false;
      _shouldShowPulse = false;
    }
  }

  /// Called when the coachmark tooltip is dismissed (user tapped away or the X).
  /// Starts the 2-session pulse countdown.
  Future<void> onCoachmarkDismissed() async {
    _shouldShowCoachmark = false;
    _shouldShowPulse = false; // pulse starts from *next* session.
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(_keyPulseRemaining, 2);
  }

  /// Called when the user taps the Nearby layouts button.
  /// Permanently disables all highlights for the current coachmark version.
  Future<void> onNearbyClicked() async {
    _shouldShowCoachmark = false;
    _shouldShowPulse = false;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(_keyClicked, true);
    await prefs.setInt(_keyPulseRemaining, 0);
  }
}
