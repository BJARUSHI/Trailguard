import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/gps_point.dart';
import 'gps_tracking_service.dart';
import 'hiking_session_service.dart';

/// Pure logic for the stillness check — no service/plugin dependencies —
/// so it can be unit-tested directly without platform bindings.
class StillnessEvaluator {
  const StillnessEvaluator._();

  static bool isWithinRadius(
    GpsPoint anchor,
    GpsPoint point, {
    double radiusMeters = AppConstants.stillnessRadiusMeters,
  }) {
    return anchor.distanceTo(point) <= radiusMeters;
  }

  static bool thresholdExceeded(
    GpsPoint anchor,
    GpsPoint point, {
    int thresholdSeconds = AppConstants.stillnessAlertThresholdSeconds,
  }) {
    return point.timestamp.difference(anchor.timestamp).inSeconds >= thresholdSeconds;
  }
}

/// Module: Stillness / Immobility Detection
///
/// Watches GPS position while a session is active. If the hiker's position
/// stays within [AppConstants.stillnessRadiusMeters] of a fixed anchor point
/// for longer than [AppConstants.stillnessAlertThresholdSeconds], it's
/// treated as "possibly stuck/immobile" and the trigger stream fires so the
/// UI layer can show the full-screen "Are you okay?" check.
///
/// Kept free of any UI/plugin (notifications, sound, vibration) dependencies
/// so the movement-detection logic itself can be unit-tested in isolation.
class StillnessDetectionService {
  static final StillnessDetectionService instance =
      StillnessDetectionService._();
  StillnessDetectionService._();

  final _gps = GpsTrackingService.instance;
  final _sessionService = HikingSessionService.instance;

  StreamSubscription<GpsPoint>? _gpsSub;
  GpsPoint? _anchor;
  bool _enabled = true;
  bool _alertActive = false;
  Timer? _timer;

  final _triggerController = StreamController<GpsPoint>.broadcast();
  final _movementResumedController = StreamController<void>.broadcast();

  /// Fires with the current GPS point once the stillness threshold is
  /// exceeded. The UI layer should show the full-screen check when this
  /// fires.
  Stream<GpsPoint> get triggerStream => _triggerController.stream;

  /// Fires if the hiker starts moving again while an alert is active/being
  /// counted down, so the UI can auto-cancel.
  Stream<void> get movementResumedStream => _movementResumedController.stream;

  bool get isEnabled => _enabled;
  bool get isAlertActive => _alertActive;

  /// Load the persisted on/off preference (defaults to enabled) and start
  /// watching GPS if a session is already active.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(AppConstants.stillnessAlertEnabledPrefKey) ?? true;
    _startWatching();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.stillnessAlertEnabledPrefKey, enabled);
    if (!enabled) {
      _anchor = null;
      _alertActive = false;
    }
  }

  void _startWatching() {
    _gpsSub ??= _gps.positionStream.listen(_onPoint);
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => _checkTimer());
  }

  void _checkTimer() {
    if (!_enabled || _alertActive || _anchor == null) return;
    final elapsed = DateTime.now().difference(_anchor!.timestamp).inSeconds;
    if (elapsed >= AppConstants.stillnessAlertThresholdSeconds) {
      _alertActive = true;
      _triggerController.add(_anchor!);
    }
  }

  /// Call when the countdown UI is dismissed/cancelled/completed so the
  /// detector starts fresh from the current position instead of
  /// immediately re-triggering.
  void resetAfterAlert(GpsPoint? currentPoint) {
    _alertActive = false;
    if (currentPoint != null) {
      // Must update the timestamp to NOW, otherwise if the GPS is perfectly still,
      // the old timestamp will immediately trigger the 60-second threshold again
      // on the next timer tick.
      _anchor = GpsPoint(
        latitude: currentPoint.latitude,
        longitude: currentPoint.longitude,
        altitude: currentPoint.altitude,
        accuracy: currentPoint.accuracy,
        timestamp: DateTime.now(),
        speed: currentPoint.speed,
      );
    } else {
      _anchor = null;
    }
  }

  void _onPoint(GpsPoint point) {
    if (!_enabled) return;

    final session = _sessionService.currentSession;
    if (session == null || _sessionService.isPaused) {
      _anchor = null;
      return;
    }

    if (_anchor == null) {
      _anchor = point;
      return;
    }

    if (!StillnessEvaluator.isWithinRadius(_anchor!, point)) {
      // Genuine movement — reset the anchor to this new position.
      final wasActive = _alertActive;
      _anchor = point;
      _alertActive = false;
      if (wasActive) {
        _movementResumedController.add(null);
      }
      return;
    }

    // Still within the radius of the anchor — check elapsed time.
    if (_alertActive) return; // already triggered, waiting on countdown
    if (StillnessEvaluator.thresholdExceeded(_anchor!, point)) {
      _alertActive = true;
      _triggerController.add(point);
    }
  }

  void dispose() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _timer?.cancel();
    _timer = null;
  }
}
