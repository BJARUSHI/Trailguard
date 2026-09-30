import 'dart:math' as math;

class GpsPoint {
  final int? id;
  final String sessionId;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double bearing;
  final double accuracy;
  final DateTime timestamp;

  const GpsPoint({
    this.id,
    required this.sessionId,
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.bearing = 0.0,
    this.accuracy = 0.0,
    required this.timestamp,
  });

  factory GpsPoint.fromMap(Map<String, dynamic> map) {
    return GpsPoint(
      id: map['id'] as int?,
      sessionId: map['session_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      bearing: (map['bearing'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'bearing': bearing,
      'accuracy': accuracy,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Haversine distance to another point in meters
  double distanceTo(GpsPoint other) {
    const R = 6371000.0;
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;
    final dLat = (other.latitude - latitude) * math.pi / 180;
    final dLon = (other.longitude - longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// Bearing in degrees to another point
  double bearingTo(GpsPoint other) {
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;
    final dLon = (other.longitude - longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  GpsPoint copyWith({
    String? sessionId,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? bearing,
    double? accuracy,
    DateTime? timestamp,
  }) {
    return GpsPoint(
      id: id,
      sessionId: sessionId ?? this.sessionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      bearing: bearing ?? this.bearing,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() =>
      'GpsPoint($latitude, $longitude, alt:$altitude, spd:$speed)';
}
