class HikingSession {
  final String id;
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final double? startLat;
  final double? startLon;
  final double? destLat;
  final double? destLon;
  final double totalDistance;
  final bool isActive;
  final bool emergencyTriggered;
  final String? notes;

  const HikingSession({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.startLat,
    this.startLon,
    this.destLat,
    this.destLon,
    this.totalDistance = 0.0,
    this.isActive = true,
    this.emergencyTriggered = false,
    this.notes,
  });

  bool get hasDestination => destLat != null && destLon != null;

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  factory HikingSession.fromMap(Map<String, dynamic> map) {
    return HikingSession(
      id: map['id'] as String,
      name: map['name'] as String,
      startTime:
          DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      startLat: (map['start_lat'] as num?)?.toDouble(),
      startLon: (map['start_lon'] as num?)?.toDouble(),
      destLat: (map['dest_lat'] as num?)?.toDouble(),
      destLon: (map['dest_lon'] as num?)?.toDouble(),
      totalDistance: (map['total_distance'] as num?)?.toDouble() ?? 0.0,
      isActive: (map['is_active'] as int?) == 1,
      emergencyTriggered: (map['emergency_triggered'] as int?) == 1,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'start_lat': startLat,
      'start_lon': startLon,
      'dest_lat': destLat,
      'dest_lon': destLon,
      'total_distance': totalDistance,
      'is_active': isActive ? 1 : 0,
      'emergency_triggered': emergencyTriggered ? 1 : 0,
      'notes': notes,
    };
  }

  HikingSession copyWith({
    String? name,
    DateTime? endTime,
    double? destLat,
    double? destLon,
    double? totalDistance,
    bool? isActive,
    bool? emergencyTriggered,
    String? notes,
  }) {
    return HikingSession(
      id: id,
      name: name ?? this.name,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      startLat: startLat,
      startLon: startLon,
      destLat: destLat ?? this.destLat,
      destLon: destLon ?? this.destLon,
      totalDistance: totalDistance ?? this.totalDistance,
      isActive: isActive ?? this.isActive,
      emergencyTriggered: emergencyTriggered ?? this.emergencyTriggered,
      notes: notes ?? this.notes,
    );
  }
}
