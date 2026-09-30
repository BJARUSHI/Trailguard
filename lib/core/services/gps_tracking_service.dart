import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../models/gps_point.dart';

/// Module 1: GPS Tracking Engine
class GpsTrackingService {
  static final GpsTrackingService instance = GpsTrackingService._();
  GpsTrackingService._();

  final _db = DatabaseHelper.instance;
  StreamSubscription<Position>? _positionSub;
  final StreamController<GpsPoint> _pointController =
      StreamController<GpsPoint>.broadcast();

  String? _activeSessionId;
  GpsPoint? _lastPoint;

  // Last fix that passed the accuracy + jitter checks below. Used as the
  // anchor for deciding whether a new fix represents real movement or just
  // GPS noise (consumer GPS commonly drifts 5-20m even standing still).
  GpsPoint? _lastAcceptedPoint;

  // Fixes worse than this are mostly noise (typical indoor/urban multipath)
  // and are dropped entirely rather than plotted on the trail.
  static const double _maxAcceptableAccuracyMeters = 150.0;

  Stream<GpsPoint> get positionStream => _pointController.stream;
  GpsPoint? get lastPoint => _lastPoint;
  String? get activeSessionId => _activeSessionId;
  bool get isTracking => _positionSub != null;

  // ─── Permission ──────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<bool> get isLocationEnabled =>
      Geolocator.isLocationServiceEnabled();

  // ─── Start Tracking ──────────────────────────────────────────
  Future<void> startTracking(String sessionId) async {
    _activeSessionId = sessionId;

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConstants.minDistanceMeters.toInt(),
      intervalDuration:
          const Duration(seconds: AppConstants.gpsIntervalSeconds),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'TrailGuard is tracking your hike',
        notificationTitle: 'TrailGuard Active',
        enableWakeLock: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition);
  }

  void _onPosition(Position pos) {
    // Drop very low-quality fixes outright — plotting them just makes the
    // marker jump around while the hiker hasn't actually moved.
    if (pos.accuracy > _maxAcceptableAccuracyMeters) return;

    final rawPoint = GpsPoint(
      sessionId: _activeSessionId!,
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed.clamp(0, 50),
      bearing: pos.heading,
      accuracy: pos.accuracy,
      timestamp: pos.timestamp,
    );

    // Stationary jitter filter: consumer GPS commonly drifts 3-10m even
    // standing still, and the device's self-reported accuracy figure is
    // often optimistic — so instead of trusting that number to size a
    // "was this just noise" radius, work out the IMPLIED SPEED between
    // the last accepted fix and this one. Jitter shows up as small,
    // erratic back-and-forth distances that don't sustain a real walking
    // pace; genuine movement does. This is what was still letting jitter
    // through and inflating the ML's speed-stability / loop-detection
    // scores while standing still.
    if (_lastAcceptedPoint != null) {
      final movedMeters = _lastAcceptedPoint!.distanceTo(rawPoint);
      final elapsedSeconds = rawPoint.timestamp
          .difference(_lastAcceptedPoint!.timestamp)
          .inMilliseconds /
          1000.0;
      final impliedSpeedMps =
          elapsedSeconds > 0 ? movedMeters / elapsedSeconds : 0.0;

      // Below a slow-walk pace, treat it as noise regardless of distance —
      // a real hiker moving 3-6m in a couple of seconds is walking; GPS
      // jitter moving that same distance over the same span is not.
      const stationarySpeedThreshold = 0.4; // m/s (~1.4 km/h)

      if (impliedSpeedMps < stationarySpeedThreshold) {
        final stationaryPoint = _lastAcceptedPoint!.copyWith(
          speed: 0,
          accuracy: pos.accuracy,
          timestamp: pos.timestamp,
        );
        _lastPoint = stationaryPoint;
        _pointController.add(stationaryPoint);
        _db.insertGpsPoint(stationaryPoint.toMap());
        return;
      }
    }

    _lastAcceptedPoint = rawPoint;
    _lastPoint = rawPoint;
    _pointController.add(rawPoint);

    // Persist async (fire-and-forget, non-blocking)
    _db.insertGpsPoint(rawPoint.toMap());
  }

  // ─── Stop Tracking ───────────────────────────────────────────
  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _activeSessionId = null;
  }

  // ─── Current Location ────────────────────────────────────────
  Future<GpsPoint?> getCurrentLocation(String sessionId) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return GpsPoint(
        sessionId: sessionId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitude: pos.altitude,
        speed: pos.speed.clamp(0, 50),
        bearing: pos.heading,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Load Recent Trail ───────────────────────────────────────
  Future<List<GpsPoint>> getRecentTrail(String sessionId,
      {int limit = AppConstants.trajectoryBufferSize}) async {
    final maps = await _db.getGpsPoints(sessionId, limit: limit);
    return maps.map(GpsPoint.fromMap).toList();
  }

  Future<List<GpsPoint>> getTrailWindow(String sessionId) async {
    final maps = await _db.getRecentGpsPoints(
        sessionId, AppConstants.featureWindowSize);
    return maps.reversed.map(GpsPoint.fromMap).toList();
  }

  void dispose() {
    _positionSub?.cancel();
    _pointController.close();
  }
}

// ─── Background Service Initializer ──────────────────────────
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: AppConstants.channelId,
      initialNotificationTitle: 'TrailGuard',
      initialNotificationContent: 'Hike tracking active',
      foregroundServiceNotificationId: AppConstants.notificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  // Background tracking continues via geolocator foreground config
  service.on('stop').listen((_) => service.stopSelf());
}
