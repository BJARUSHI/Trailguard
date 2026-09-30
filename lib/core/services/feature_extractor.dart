import 'dart:math' as math;
import '../models/gps_point.dart';
import '../models/behavioral_features.dart';
import '../constants/app_constants.dart';

/// Module 4 + 5: Behavioral Feature Extraction & Terrain Awareness
class FeatureExtractor {
  static BehavioralFeatures extract({
    required List<GpsPoint> window,
    required String sessionId,
    double? destLat,
    double? destLon,
  }) {
    if (window.length < 3) {
      return BehavioralFeatures(
        sessionId: sessionId,
        timestamp: DateTime.now(),
      );
    }

    return BehavioralFeatures(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      directionVariance: _directionVariance(window),
      backtrackingRatio: _backtrackingRatio(window),
      pathEfficiency: _pathEfficiency(window),
      loopScore: _loopDetectionScore(window),
      movementEntropy: _movementEntropy(window),
      speedStability: _speedStability(window),
      stopFrequency: _stopFrequency(window),
      elevationChange: _elevationChange(window),
      terrainSlope: _terrainSlope(window),
      progressTowardDest: _progressTowardDestination(
        window,
        destLat: destLat,
        destLon: destLon,
      ),
    );
  }

  // ─── Feature 1: Direction Variance ───────────────────────────
  static double _directionVariance(List<GpsPoint> pts) {
    if (pts.length < 3) return 0.0;
    final bearings = <double>[];
    for (int i = 1; i < pts.length; i++) {
      bearings.add(pts[i - 1].bearingTo(pts[i]));
    }
    // Circular variance
    double sinSum = 0, cosSum = 0;
    for (final b in bearings) {
      final rad = b * math.pi / 180;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }
    final R = math.sqrt(sinSum * sinSum + cosSum * cosSum) / bearings.length;
    // R=1 means all same direction, R=0 means random
    return (1 - R).clamp(0.0, 1.0);
  }

  // ─── Feature 2: Backtracking Ratio ───────────────────────────
  static double _backtrackingRatio(List<GpsPoint> pts) {
    if (pts.length < 3) return 0.0;
    int backtrackCount = 0;
    for (int i = 2; i < pts.length; i++) {
      final bearing1 = pts[i - 2].bearingTo(pts[i - 1]);
      final bearing2 = pts[i - 1].bearingTo(pts[i]);
      final diff = _angleDiff(bearing1, bearing2);
      if (diff > AppConstants.backtrackAngleThreshold) backtrackCount++;
    }
    return (backtrackCount / (pts.length - 2)).clamp(0.0, 1.0);
  }

  // ─── Feature 3: Path Efficiency ──────────────────────────────
  static double _pathEfficiency(List<GpsPoint> pts) {
    if (pts.length < 2) return 1.0;
    final straight = pts.first.distanceTo(pts.last);
    double actual = 0.0;
    for (int i = 1; i < pts.length; i++) {
      actual += pts[i - 1].distanceTo(pts[i]);
    }
    if (actual < 1.0) return 1.0;
    return (straight / actual).clamp(0.0, 1.0);
  }

  // ─── Feature 4: Loop Detection Score ─────────────────────────
  static double _loopDetectionScore(List<GpsPoint> pts) {
    if (pts.length < 5) return 0.0;
    int loopPoints = 0;
    const radius = AppConstants.loopDetectionRadiusMeters;
    // Check how many recent points are close to earlier points
    for (int i = pts.length ~/ 2; i < pts.length; i++) {
      for (int j = 0; j < i - 3; j++) {
        if (pts[i].distanceTo(pts[j]) < radius) {
          loopPoints++;
          break;
        }
      }
    }
    final halfLen = pts.length - pts.length ~/ 2;
    return (loopPoints / halfLen.clamp(1, halfLen)).clamp(0.0, 1.0);
  }

  // ─── Feature 5: Movement Entropy ─────────────────────────────
  static double _movementEntropy(List<GpsPoint> pts) {
    if (pts.length < 3) return 0.0;
    // Discretize bearing into 8 sectors, compute Shannon entropy
    final counts = List<int>.filled(8, 0);
    for (int i = 1; i < pts.length; i++) {
      final bearing = pts[i - 1].bearingTo(pts[i]);
      final sector = (bearing / 45).floor() % 8;
      counts[sector]++;
    }
    final total = pts.length - 1;
    double entropy = 0.0;
    for (final c in counts) {
      if (c > 0) {
        final p = c / total;
        entropy -= p * math.log(p) / math.log(2);
      }
    }
    // Max entropy for 8 sectors = log2(8) = 3.0
    return (entropy / 3.0).clamp(0.0, 1.0);
  }

  // ─── Feature 6: Speed Stability ──────────────────────────────
  static double _speedStability(List<GpsPoint> pts) {
    final speeds = pts.map((p) => p.speed).where((s) => s >= 0).toList();
    if (speeds.isEmpty) return 1.0;
    final mean = speeds.reduce((a, b) => a + b) / speeds.length;
    if (mean < 0.01) return 0.5;
    final variance = speeds
            .map((s) => (s - mean) * (s - mean))
            .reduce((a, b) => a + b) /
        speeds.length;
    final cv = math.sqrt(variance) / mean; // coefficient of variation
    // cv=0 = perfectly stable, normalize
    return (1 / (1 + cv)).clamp(0.0, 1.0);
  }

  // ─── Feature 7: Stop Frequency ───────────────────────────────
  static double _stopFrequency(List<GpsPoint> pts) {
    if (pts.isEmpty) return 0.0;
    const stopSpeedThreshold = 0.3; // m/s
    final stops = pts.where((p) => p.speed < stopSpeedThreshold).length;
    return (stops / pts.length).clamp(0.0, 1.0);
  }

  // ─── Feature 8 & 9: Terrain Awareness ────────────────────────
  static double _elevationChange(List<GpsPoint> pts) {
    if (pts.length < 2) return 0.0;
    double totalChange = 0.0;
    for (int i = 1; i < pts.length; i++) {
      totalChange += (pts[i].altitude - pts[i - 1].altitude).abs();
    }
    return totalChange; // meters
  }

  static double _terrainSlope(List<GpsPoint> pts) {
    if (pts.length < 2) return 0.0;
    double totalSlope = 0.0;
    int count = 0;
    for (int i = 1; i < pts.length; i++) {
      final horizDist = pts[i - 1].distanceTo(pts[i]);
      if (horizDist > 0.5) {
        final elevChange =
            (pts[i].altitude - pts[i - 1].altitude).abs();
        // slope in degrees
        totalSlope +=
            math.atan(elevChange / horizDist) * 180 / math.pi;
        count++;
      }
    }
    return count > 0 ? totalSlope / count : 0.0;
  }

  // ─── Feature 10: Progress Toward Destination ─────────────────
  static double _progressTowardDestination(
    List<GpsPoint> pts, {
    double? destLat,
    double? destLon,
  }) {
    if (destLat == null || destLon == null || pts.length < 2) return 0.5;
    final destPoint = GpsPoint(
      sessionId: '',
      latitude: destLat,
      longitude: destLon,
      timestamp: DateTime.now(),
    );
    final distStart = pts.first.distanceTo(destPoint);
    final distNow = pts.last.distanceTo(destPoint);
    if (distStart < 1.0) return 1.0;
    return ((distStart - distNow) / distStart + 1) / 2;
  }

  // ─── Utility ─────────────────────────────────────────────────
  static double _angleDiff(double a, double b) {
    double diff = (b - a).abs() % 360;
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  // ─── Stationary Check ────────────────────────────────────────
  static bool isStationary(List<GpsPoint> window) {
    if (window.isEmpty) return true;
    if (window.length < 2) return true;

    double maxDist = 0.0;
    for (int i = 0; i < window.length; i++) {
      for (int j = i + 1; j < window.length; j++) {
        final dist = window[i].distanceTo(window[j]);
        if (dist > maxDist) {
          maxDist = dist;
        }
      }
    }
    // If maximum distance between any points in the window is < 15 meters, hiker is resting
    return maxDist < 15.0;
  }
}
