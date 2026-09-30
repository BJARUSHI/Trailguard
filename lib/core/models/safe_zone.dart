import 'gps_point.dart';
import 'dart:math' as math;

class SafeZone {
  final int? id;
  final String sessionId;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final DateTime createdAt;

  const SafeZone({
    this.id,
    required this.sessionId,
    required this.centerLat,
    required this.centerLon,
    this.radiusMeters = 50.0,
    required this.createdAt,
  });

  bool contains(GpsPoint point) {
    final distance = _haversineDistance(
        centerLat, centerLon, point.latitude, point.longitude);
    return distance <= radiusMeters;
  }

  double distanceFrom(double lat, double lon) {
    return _haversineDistance(centerLat, centerLon, lat, lon);
  }

  static double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  factory SafeZone.fromMap(Map<String, dynamic> map) {
    return SafeZone(
      id: map['id'] as int?,
      sessionId: map['session_id'] as String,
      centerLat: (map['center_lat'] as num).toDouble(),
      centerLon: (map['center_lon'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 50.0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'center_lat': centerLat,
      'center_lon': centerLon,
      'radius_meters': radiusMeters,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}
