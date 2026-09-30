import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';

class OfflineWaypoint {
  final String id;
  final String name;
  final String category; // Water, Campsite, Junction, Hazard, Landmark
  final double latitude;
  final double longitude;
  final String? notes;
  final DateTime createdAt;

  OfflineWaypoint({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.notes,
    required this.createdAt,
  });

  LatLng get location => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory OfflineWaypoint.fromMap(Map<String, dynamic> map) => OfflineWaypoint(
        id: map['id'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        notes: map['notes'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

/// Module N: Offline Waypoint Pin Storage & Categorized POI Manager
class WaypointService {
  static final WaypointService instance = WaypointService._();
  WaypointService._();

  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();

  Future<OfflineWaypoint> addWaypoint({
    required String name,
    required String category,
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final wp = OfflineWaypoint(
      id: _uuid.v4(),
      name: name,
      category: category,
      latitude: latitude,
      longitude: longitude,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await _db.insertWaypoint(wp.toMap());
    return wp;
  }

  Future<List<OfflineWaypoint>> getAllWaypoints() async {
    final maps = await _db.getAllWaypoints();
    return maps.map(OfflineWaypoint.fromMap).toList();
  }

  Future<List<OfflineWaypoint>> searchWaypoints(String query) async {
    if (query.trim().isEmpty) return getAllWaypoints();
    final maps = await _db.searchWaypoints(query.trim());
    return maps.map(OfflineWaypoint.fromMap).toList();
  }

  Future<void> deleteWaypoint(String id) async {
    await _db.deleteWaypoint(id);
  }
}
