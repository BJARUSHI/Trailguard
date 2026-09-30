import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../models/gps_point.dart';
import 'gps_tracking_service.dart';

class EstimatedPosition {
  final LatLng position;
  final double bearing;
  final double estimatedSpeedMps;
  final DateTime timestamp;
  final bool isDeadReckoning;

  EstimatedPosition({
    required this.position,
    required this.bearing,
    required this.estimatedSpeedMps,
    required this.timestamp,
    required this.isDeadReckoning,
  });
}

/// Module N: Dead-Reckoning Fallback Engine for GPS fix loss
class DeadReckoningService {
  static final DeadReckoningService instance = DeadReckoningService._();
  DeadReckoningService._();

  final _gps = GpsTrackingService.instance;
  StreamSubscription<GpsPoint>? _gpsSub;
  Timer? _checkTimer;

  bool _isGpsLost = false;
  EstimatedPosition? _currentEstimated;
  GpsPoint? _lastKnownPoint;

  final StreamController<EstimatedPosition> _positionController =
      StreamController<EstimatedPosition>.broadcast();

  Stream<EstimatedPosition> get estimatedPositionStream =>
      _positionController.stream;
  bool get isGpsLost => _isGpsLost;
  EstimatedPosition? get currentEstimated => _currentEstimated;

  void startMonitoring() {
    _gpsSub?.cancel();
    _checkTimer?.cancel();

    _gpsSub = _gps.positionStream.listen((point) {
      _lastKnownPoint = point;
      if (_isGpsLost) {
        _isGpsLost = false;
      }
      _currentEstimated = EstimatedPosition(
        position: LatLng(point.latitude, point.longitude),
        bearing: point.bearing,
        estimatedSpeedMps: point.speed,
        timestamp: point.timestamp,
        isDeadReckoning: false,
      );
      _positionController.add(_currentEstimated!);
    });

    _checkTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkGpsTimeout());
  }

  void _checkGpsTimeout() {
    if (_lastKnownPoint == null) return;
    final now = DateTime.now();
    final elapsedSeconds =
        now.difference(_lastKnownPoint!.timestamp).inSeconds;

    if (elapsedSeconds >= AppConstants.gpsLossTimeoutSeconds) {
      _isGpsLost = true;
      final bearing = _lastKnownPoint!.bearing;
      final prevPos = _currentEstimated?.position ??
          LatLng(_lastKnownPoint!.latitude, _lastKnownPoint!.longitude);

      // Only project the marker forward if there was genuine walking motion
      // right before the fix was lost. Previously this defaulted to an
      // assumed 1.2 m/s walking pace even when the hiker was standing or
      // sitting still, which made the marker "walk" on its own the moment
      // GPS briefly stalled (very common indoors/under tree cover).
      const stationarySpeedThreshold = 0.3; // m/s
      if (_lastKnownPoint!.speed < stationarySpeedThreshold) {
        _currentEstimated = EstimatedPosition(
          position: prevPos,
          bearing: bearing,
          estimatedSpeedMps: 0,
          timestamp: now,
          isDeadReckoning: true,
        );
        _positionController.add(_currentEstimated!);
        return;
      }

      final speed = _lastKnownPoint!.speed;
      const dt = 2.0; // 2 seconds update step
      final distMeters = speed * dt;
      final nextPos = _projectPoint(prevPos, distMeters, bearing);

      _currentEstimated = EstimatedPosition(
        position: nextPos,
        bearing: bearing,
        estimatedSpeedMps: speed,
        timestamp: now,
        isDeadReckoning: true,
      );

      _positionController.add(_currentEstimated!);
    }
  }

  LatLng _projectPoint(LatLng start, double distanceMeters, double bearingDegrees) {
    const rEarth = 6371000.0;
    final radDist = distanceMeters / rEarth;
    final radBearing = bearingDegrees * pi / 180.0;

    final lat1 = start.latitude * pi / 180.0;
    final lon1 = start.longitude * pi / 180.0;

    final lat2 = asin(sin(lat1) * cos(radDist) +
        cos(lat1) * sin(radDist) * cos(radBearing));
    final lon2 = lon1 +
        atan2(sin(radBearing) * sin(radDist) * cos(lat1),
            cos(radDist) - sin(lat1) * sin(lat2));

    return LatLng(lat2 * 180.0 / pi, lon2 * 180.0 / pi);
  }

  void stopMonitoring() {
    _gpsSub?.cancel();
    _checkTimer?.cancel();
    _gpsSub = null;
    _checkTimer = null;
    _isGpsLost = false;
  }
}
