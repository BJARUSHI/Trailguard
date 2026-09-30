import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../models/gps_point.dart';
import '../models/hiking_session.dart';
import '../models/behavioral_features.dart';
import '../models/safety_prediction.dart';
import '../models/safe_zone.dart';
import 'gps_tracking_service.dart';
import 'feature_extractor.dart';
import 'offline_routing_service.dart';
import '../../ml/ml_inference_engine.dart';

/// Central orchestrator: GPS → Features → ML → Prediction pipeline
class HikingSessionService {
  static final HikingSessionService instance = HikingSessionService._();
  HikingSessionService._();

  final _db = DatabaseHelper.instance;
  final _gps = GpsTrackingService.instance;
  final _ml = MLInferenceEngine.instance;
  final _router = OfflineRoutingService.instance;
  final _uuid = const Uuid();

  HikingSession? _currentSession;
  BehavioralFeatures? _latestFeatures;
  SafetyPrediction? _latestPrediction;
  bool _isPaused = false;

  // In-memory trail buffer for fast feature extraction
  final List<GpsPoint> _trailBuffer = [];
  final List<SafeZone> _safeZones = [];

  // Continuous analysis timer
  Timer? _analysisTimer;

  // Streams
  final _predictionController =
      StreamController<SafetyPrediction>.broadcast();
  final _featuresController =
      StreamController<BehavioralFeatures>.broadcast();
  final _pauseController =
      StreamController<bool>.broadcast();

  Stream<SafetyPrediction> get predictionStream =>
      _predictionController.stream;
  Stream<BehavioralFeatures> get featuresStream =>
      _featuresController.stream;
  Stream<bool> get pauseStream =>
      _pauseController.stream;

  HikingSession? get currentSession => _currentSession;
  BehavioralFeatures? get latestFeatures => _latestFeatures;
  SafetyPrediction? get latestPrediction => _latestPrediction;
  List<GpsPoint> get trailBuffer => List.unmodifiable(_trailBuffer);
  List<SafeZone> get safeZones => List.unmodifiable(_safeZones);
  bool get isPaused => _isPaused;

  void pauseSession() {
    if (_currentSession == null || _isPaused) return;
    _isPaused = true;
    _pauseController.add(true);
  }

  void resumeSession() {
    if (_currentSession == null || !_isPaused) return;
    _isPaused = false;
    _pauseController.add(false);
  }

  // ─── Start Session ───────────────────────────────────────────
  Future<HikingSession> startSession({
    required String name,
    double? destLat,
    double? destLon,
  }) async {
    // End any existing session
    if (_currentSession != null) await endSession();

    final session = HikingSession(
      id: _uuid.v4(),
      name: name,
      startTime: DateTime.now(),
      destLat: destLat,
      destLon: destLon,
    );

    await _db.insertSession(session.toMap());
    _currentSession = session;
    _trailBuffer.clear();
    _safeZones.clear();
    _isPaused = false;

    // Start GPS
    await _gps.startTracking(session.id);

    // Load ML model & router
    await _ml.loadModel();
    await _router.initialize();

    // Subscribe to GPS stream
    _gps.positionStream.listen(_onNewGpsPoint);

    // Run analysis every 10 seconds
    _analysisTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _runAnalysis(),
    );

    return session;
  }

  // ─── End Session ─────────────────────────────────────────────
  Future<void> endSession() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    await _gps.stopTracking();
    _isPaused = false;

    if (_currentSession != null) {
      final totalDist = _computeTotalDistance();
      await _db.updateSession(
        _currentSession!
            .copyWith(
              isActive: false,
              endTime: DateTime.now(),
              totalDistance: totalDist,
            )
            .toMap(),
        _currentSession!.id,
      );
      _currentSession = null;
    }
    _trailBuffer.clear();
  }

  // ─── GPS Point Handler ───────────────────────────────────────
  void _onNewGpsPoint(GpsPoint point) {
    if (_isPaused) return; // Do not append points to trail buffer while paused
    _trailBuffer.add(point);
    if (_trailBuffer.length > AppConstants.trajectoryBufferSize) {
      _trailBuffer.removeAt(0);
    }
  }

  // ─── Analysis Pipeline ───────────────────────────────────────
  Future<void> _runAnalysis() async {
    if (_currentSession == null || _isPaused ||
        _trailBuffer.length < AppConstants.minPointsForAnalysis) {
      return;
    }

    final window = _trailBuffer.length > AppConstants.featureWindowSize
        ? _trailBuffer.sublist(
            _trailBuffer.length - AppConstants.featureWindowSize)
        : List<GpsPoint>.from(_trailBuffer);

    // Extract features
    final features = FeatureExtractor.extract(
      window: window,
      sessionId: _currentSession!.id,
      destLat: _currentSession!.destLat,
      destLon: _currentSession!.destLon,
    );

    // ML prediction
    SafetyPrediction prediction = _ml.predict(features);

    // Check if stationary (resting/short break) to avoid false disorientation alerts
    if (FeatureExtractor.isStationary(window)) {
      prediction = SafetyPrediction(
        sessionId: prediction.sessionId,
        timestamp: prediction.timestamp,
        disorientationProbability: 0.0,
        confidenceScore: 100,
        riskLevel: RiskLevel.safe,
      );
    }

    _latestFeatures = features;
    _latestPrediction = prediction;

    // Broadcast
    _featuresController.add(features);
    _predictionController.add(prediction);

    // Persist (throttled — every 3rd cycle)
    await _db.insertFeatures(features.toMap());
    await _db.insertPrediction(prediction.toMap());

    // Detect & store safe zones
    if (prediction.riskLevel == RiskLevel.safe &&
        features.pathEfficiency > 0.75 &&
        features.directionVariance < 0.25) {
      _maybeAddSafeZone(window.last);
    }
  }

  void _maybeAddSafeZone(GpsPoint point) {
    // Don't add if already inside an existing safe zone
    for (final z in _safeZones) {
      if (z.contains(point)) return;
    }
    final zone = SafeZone(
      sessionId: _currentSession!.id,
      centerLat: point.latitude,
      centerLon: point.longitude,
      createdAt: DateTime.now(),
    );
    _safeZones.add(zone);
    _db.insertSafeZone(zone.toMap());
  }

  // ─── Recovery Route ──────────────────────────────────────────
  /// Module 9: Reverse Trajectory Replay & Offline Trail Graph Routing
  List<GpsPoint> getRecoveryRoute() {
    if (_trailBuffer.isEmpty) return [];
    // Find nearest safe zone index in trail
    int safeIndex = 0;
    if (_safeZones.isNotEmpty) {
      double minDist = double.infinity;
      for (int i = 0; i < _trailBuffer.length; i++) {
        for (final zone in _safeZones) {
          final d = zone.distanceFrom(
              _trailBuffer[i].latitude, _trailBuffer[i].longitude);
          if (d < minDist) {
            minDist = d;
            safeIndex = i;
          }
        }
      }
      return _trailBuffer.sublist(safeIndex).reversed.toList();
    }
    return _trailBuffer.reversed.toList();
  }

  RoutingResult getSmartRecoveryRoute() {
    if (_trailBuffer.isEmpty) {
      return RoutingResult(
        path: [],
        steps: [],
        totalDistanceMeters: 0,
        usedTrailNetwork: false,
      );
    }

    final currentPos = LatLng(_trailBuffer.last.latitude, _trailBuffer.last.longitude);
    LatLng targetPos = LatLng(_trailBuffer.first.latitude, _trailBuffer.first.longitude);

    if (_safeZones.isNotEmpty) {
      targetPos = LatLng(_safeZones.first.centerLat, _safeZones.first.centerLon);
    }

    final result = _router.computeRoute(currentPos: currentPos, targetPos: targetPos);

    if (result.usedTrailNetwork) {
      return result;
    }

    // Fallback to breadcrumb reverse route
    final breadcrumb = getRecoveryRoute();
    final pathPoints = breadcrumb.map((p) => LatLng(p.latitude, p.longitude)).toList();
    double totalD = 0;
    const distanceCalc = Distance();
    for (int i = 0; i < pathPoints.length - 1; i++) {
      totalD += distanceCalc(pathPoints[i], pathPoints[i + 1]);
    }

    return RoutingResult(
      path: pathPoints,
      steps: [],
      totalDistanceMeters: totalD,
      usedTrailNetwork: false,
    );
  }

  // ─── History Loading ─────────────────────────────────────────
  Future<List<HikingSession>> getAllSessions() async {
    final maps = await _db.getAllSessions();
    return maps.map(HikingSession.fromMap).toList();
  }

  Future<List<GpsPoint>> getSessionTrail(String sessionId) async {
    final maps = await _db.getGpsPoints(sessionId);
    return maps.map(GpsPoint.fromMap).toList();
  }

  Future<List<SafetyPrediction>> getPredictionHistory(
      String sessionId) async {
    final maps = await _db.getPredictionHistory(sessionId);
    return maps.map(SafetyPrediction.fromMap).toList();
  }

  Future<List<BehavioralFeatures>> getFeatureHistory(
      String sessionId) async {
    final maps = await _db.getFeatureHistory(sessionId);
    return maps.map(BehavioralFeatures.fromMap).toList();
  }

  // ─── Emergency Support ───────────────────────────────────────
  Future<void> logEmergency(String message) async {
    if (_currentSession == null) return;
    final last = _gps.lastPoint;
    await _db.insertEmergencyLog({
      'session_id': _currentSession!.id,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'last_lat': last?.latitude,
      'last_lon': last?.longitude,
      'message': message,
      'sent': 0,
    });
    await _db.updateSession(
      _currentSession!.copyWith(emergencyTriggered: true).toMap(),
      _currentSession!.id,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────
  double _computeTotalDistance() {
    if (_trailBuffer.length < 2) return 0.0;
    double d = 0;
    for (int i = 1; i < _trailBuffer.length; i++) {
      d += _trailBuffer[i - 1].distanceTo(_trailBuffer[i]);
    }
    return d;
  }

  void dispose() {
    _analysisTimer?.cancel();
    _predictionController.close();
    _featuresController.close();
  }
}
