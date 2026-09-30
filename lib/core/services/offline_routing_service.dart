import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class TrailNode {
  final String id;
  final double lat;
  final double lon;
  final double elevation;
  final String name;

  TrailNode({
    required this.id,
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.name,
  });

  LatLng get location => LatLng(lat, lon);

  factory TrailNode.fromJson(Map<String, dynamic> json) => TrailNode(
        id: json['id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        elevation: (json['elevation'] as num).toDouble(),
        name: json['name'] as String? ?? 'Trail Point',
      );
}

class TrailEdge {
  final String from;
  final String to;
  final double distance;

  TrailEdge({required this.from, required this.to, required this.distance});

  factory TrailEdge.fromJson(Map<String, dynamic> json) => TrailEdge(
        from: json['from'] as String,
        to: json['to'] as String,
        distance: (json['distance'] as num).toDouble(),
      );
}

class RouteStep {
  final LatLng point;
  final String instruction;
  final double distanceMeters;
  final double bearingDegrees;

  RouteStep({
    required this.point,
    required this.instruction,
    required this.distanceMeters,
    required this.bearingDegrees,
  });
}

class RoutingResult {
  final List<LatLng> path;
  final List<RouteStep> steps;
  final double totalDistanceMeters;
  final bool usedTrailNetwork;

  RoutingResult({
    required this.path,
    required this.steps,
    required this.totalDistanceMeters,
    required this.usedTrailNetwork,
  });
}

/// Module N: Offline OSM Trail Graph Router & Turn-by-Turn Engine
class OfflineRoutingService {
  static final OfflineRoutingService instance = OfflineRoutingService._();
  OfflineRoutingService._();

  final List<TrailNode> _nodes = [];
  final List<TrailEdge> _edges = [];
  final Distance _distanceCalc = const Distance();
  bool _isInitialized = false;

  List<TrailNode> get nodes => List.unmodifiable(_nodes);

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final jsonString =
          await rootBundle.loadString('assets/trails/bundled_trails.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final trails = data['trails'] as List;

      _nodes.clear();
      _edges.clear();

      for (final trail in trails) {
        final nodeMap = trail['nodes'] as List;
        final edgeMap = trail['edges'] as List;

        for (final n in nodeMap) {
          _nodes.add(TrailNode.fromJson(n as Map<String, dynamic>));
        }
        for (final e in edgeMap) {
          _edges.add(TrailEdge.fromJson(e as Map<String, dynamic>));
        }
      }
      _isInitialized = true;
    } catch (_) {
      _isInitialized = false;
    }
  }

  RoutingResult computeRoute({
    required LatLng currentPos,
    required LatLng targetPos,
    double maxSnapMeters = 3000.0,
  }) {
    if (!_isInitialized || _nodes.isEmpty) {
      return RoutingResult(
        path: [currentPos, targetPos],
        steps: [],
        totalDistanceMeters: _distanceCalc(currentPos, targetPos),
        usedTrailNetwork: false,
      );
    }

    // 1. Find nearest start and target nodes
    TrailNode? startNode;
    TrailNode? endNode;
    double minStartDist = double.infinity;
    double minEndDist = double.infinity;

    for (final node in _nodes) {
      final dStart = _distanceCalc(currentPos, node.location);
      if (dStart < minStartDist) {
        minStartDist = dStart;
        startNode = node;
      }

      final dEnd = _distanceCalc(targetPos, node.location);
      if (dEnd < minEndDist) {
        minEndDist = dEnd;
        endNode = node;
      }
    }

    if (startNode == null ||
        endNode == null ||
        minStartDist > maxSnapMeters ||
        minEndDist > maxSnapMeters) {
      return RoutingResult(
        path: [currentPos, targetPos],
        steps: [],
        totalDistanceMeters: _distanceCalc(currentPos, targetPos),
        usedTrailNetwork: false,
      );
    }

    // 2. Run Dijkstra graph shortest path algorithm
    final nodePath = _dijkstra(startNode.id, endNode.id);
    if (nodePath.isEmpty) {
      return RoutingResult(
        path: [currentPos, targetPos],
        steps: [],
        totalDistanceMeters: _distanceCalc(currentPos, targetPos),
        usedTrailNetwork: false,
      );
    }

    // 3. Assemble point polyline and turn-by-turn steps
    final fullPath = <LatLng>[currentPos];
    final steps = <RouteStep>[];
    double totalDistance = minStartDist;

    final nodeMap = {for (final n in _nodes) n.id: n};

    fullPath.add(startNode.location);

    for (int i = 0; i < nodePath.length - 1; i++) {
      final curr = nodeMap[nodePath[i]]!;
      final next = nodeMap[nodePath[i + 1]]!;
      final legDist = _distanceCalc(curr.location, next.location);
      final bearing = _distanceCalc.bearing(curr.location, next.location);

      totalDistance += legDist;
      fullPath.add(next.location);

      final directionStr = _bearingToDirection(bearing);
      steps.add(RouteStep(
        point: curr.location,
        instruction: 'Head $directionStr toward ${next.name}',
        distanceMeters: legDist,
        bearingDegrees: bearing,
      ));
    }

    totalDistance += minEndDist;
    fullPath.add(targetPos);

    return RoutingResult(
      path: fullPath,
      steps: steps,
      totalDistanceMeters: totalDistance,
      usedTrailNetwork: true,
    );
  }

  List<String> _dijkstra(String startId, String endId) {
    final distances = <String, double>{startId: 0.0};
    final previous = <String, String>{};
    final unvisited = <String>{for (final n in _nodes) n.id};

    // Build adjacency list
    final adj = <String, List<MapEntry<String, double>>>{};
    for (final e in _edges) {
      adj.putIfAbsent(e.from, () => []).add(MapEntry(e.to, e.distance));
      adj.putIfAbsent(e.to, () => []).add(MapEntry(e.from, e.distance));
    }

    while (unvisited.isNotEmpty) {
      String? current;
      double minD = double.infinity;
      for (final n in unvisited) {
        final d = distances[n] ?? double.infinity;
        if (d < minD) {
          minD = d;
          current = n;
        }
      }

      if (current == null || minD == double.infinity) break;
      if (current == endId) break;

      unvisited.remove(current);

      final neighbors = adj[current] ?? [];
      for (final neighbor in neighbors) {
        if (!unvisited.contains(neighbor.key)) continue;
        final alt = distances[current]! + neighbor.value;
        if (alt < (distances[neighbor.key] ?? double.infinity)) {
          distances[neighbor.key] = alt;
          previous[neighbor.key] = current;
        }
      }
    }

    final path = <String>[];
    String? curr = endId;
    if (!previous.containsKey(endId) && startId != endId) return [];

    while (curr != null) {
      path.insert(0, curr);
      curr = previous[curr];
    }
    return path;
  }

  String _bearingToDirection(double bearing) {
    final b = (bearing + 360) % 360;
    if (b >= 337.5 || b < 22.5) return 'North';
    if (b >= 22.5 && b < 67.5) return 'Northeast';
    if (b >= 67.5 && b < 112.5) return 'East';
    if (b >= 112.5 && b < 157.5) return 'Southeast';
    if (b >= 157.5 && b < 202.5) return 'South';
    if (b >= 202.5 && b < 247.5) return 'Southwest';
    if (b >= 247.5 && b < 292.5) return 'West';
    return 'Northwest';
  }
}
