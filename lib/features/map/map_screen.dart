import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/models/gps_point.dart';
import '../../core/models/safe_zone.dart';
import '../../core/models/safety_prediction.dart';
import '../../core/services/gps_tracking_service.dart';
import '../../core/services/hiking_session_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/offline_tile_provider.dart';
import '../../core/services/offline_region_service.dart';
import '../../core/services/offline_routing_service.dart';
import '../../core/services/dead_reckoning_service.dart';
import '../../core/services/waypoint_service.dart';
import '../../core/services/peer_position_service.dart';
import 'offline_region_manager_screen.dart';

/// Module 2: Offline Map System with Trail Routing, Dead Reckoning, Waypoints & P2P Sharing
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _sessionService = HikingSessionService.instance;
  final _gps = GpsTrackingService.instance;
  final _deadReckoning = DeadReckoningService.instance;
  final _waypointService = WaypointService.instance;
  final _peerService = PeerPositionService.instance;
  final _mapCtrl = MapController();

  bool _offlineMode = false;
  bool _showElevationProfile = false;

  // Standard light OpenStreetMap tiles — matches a familiar Google-Maps-like
  // appearance (light background, green parks, tan open land, blue water).
  //
  // NOTE: an earlier revision pointed this at a.basemaps.cartocdn.com (dark
  // theme). That CARTO host is unreachable on at least one tested network
  // (SocketException: Connection refused), and the dark style is no longer
  // wanted anyway — reverted to standard OSM tiles, which were confirmed
  // reachable in earlier testing.
  static const String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _fallbackTileUrl = 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png';

  StreamSubscription<GpsPoint>? _gpsSub;
  StreamSubscription<SafetyPrediction>? _predSub;
  StreamSubscription<EstimatedPosition>? _deadSub;
  StreamSubscription<Map<String, PeerPosition>>? _peerSub;
  StreamSubscription<bool>? _pauseSub;

  LatLng? _currentPos;
  EstimatedPosition? _estimatedPos;
  final List<GpsPoint> _rawGpsTrail = [];
  final List<LatLng> _trail = [];
  List<SafeZone> _safeZones = [];
  List<OfflineWaypoint> _waypoints = [];
  Map<String, PeerPosition> _peers = {};
  SafetyPrediction? _prediction;
  bool _followUser = true;
  bool _showRecovery = false;
  bool _isSelectingDownloadArea = false;
  RoutingResult? _recoveryRoutingResult;
  List<OfflineRegion> _downloadedRegions = [];

  @override
  void initState() {
    super.initState();
    DynamicOfflineTileProvider.initPath();
    _loadWaypoints();
    _loadDownloadedRegions();
    _fetchInitialLocation();

    _deadReckoning.startMonitoring();
    _deadSub = _deadReckoning.estimatedPositionStream.listen((est) {
      setState(() => _estimatedPos = est);
    });

    _peerService.startBroadcasting(
      getCurrentLocation: () =>
          _currentPos ?? _estimatedPos?.position ?? const LatLng(12.8698, 74.8435),
    );
    _peerSub = _peerService.activePeersStream.listen((peers) {
      setState(() => _peers = peers);
    });

    _gpsSub = _gps.positionStream.listen((p) {
      setState(() {
        _currentPos = LatLng(p.latitude, p.longitude);
        _rawGpsTrail.add(p);
        _trail.add(_currentPos!);
        if (_trail.length > AppConstants.trajectoryBufferSize) {
          _rawGpsTrail.removeAt(0);
          _trail.removeAt(0);
        }
        _safeZones = _sessionService.safeZones;

        // Keep the recovery route live: recompute it from the current
        // position on every fix instead of freezing the distance and
        // turn instruction at the moment recovery was first triggered.
        if (_showRecovery) {
          final refreshed = _sessionService.getSmartRecoveryRoute();
          _recoveryRoutingResult = refreshed;
          if (refreshed.totalDistanceMeters < AppConstants.loopDetectionRadiusMeters) {
            _showRecovery = false; // arrived back at the safe zone
          }
        }
      });
      if (_followUser && _currentPos != null) {
        _mapCtrl.move(_currentPos!, _mapCtrl.camera.zoom);
      }
    });

    _predSub = _sessionService.predictionStream.listen((pred) {
      setState(() => _prediction = pred);
      if (pred.riskLevel == RiskLevel.disoriented && !_showRecovery) {
        _activateRecovery();
      }
    });

    _pauseSub = _sessionService.pauseStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadWaypoints() async {
    final wps = await _waypointService.getAllWaypoints();
    setState(() => _waypoints = wps);
  }

  /// Loads the bounds of every downloaded offline region so they can be
  /// drawn as an overlay on the map — this is the fix for "I downloaded a
  /// region but can't tell if/where it worked": the coverage is now visible
  /// directly on the map, not just buried in a separate list screen.
  Future<void> _loadDownloadedRegions() async {
    final regions = await OfflineRegionService.instance.getSavedRegions();
    if (mounted) setState(() => _downloadedRegions = regions);
  }

  Future<void> _fetchInitialLocation() async {
    final hasPerm = await _gps.requestPermissions();
    if (!hasPerm) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          // Only update if it hasn't been set by a live session yet
          if (_currentPos == null) {
            _currentPos = LatLng(pos.latitude, pos.longitude);
            if (_followUser) {
              _mapCtrl.move(_currentPos!, _mapCtrl.camera.zoom);
            }
          }
        });
      }
    } catch (_) {
      // Ignore errors, it will fallback to estimated or hardcoded pos.
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _predSub?.cancel();
    _deadSub?.cancel();
    _peerSub?.cancel();
    _pauseSub?.cancel();
    _deadReckoning.stopMonitoring();
    _peerService.stopBroadcasting();
    super.dispose();
  }

  void _activateRecovery() {
    final routingResult = _sessionService.getSmartRecoveryRoute();
    setState(() {
      _recoveryRoutingResult = routingResult;
      _showRecovery = true;
    });
  }

  void _dismissRecovery() => setState(() => _showRecovery = false);

  Color get _markerColor {
    final level = _prediction?.riskLevel ?? RiskLevel.safe;
    if (level == RiskLevel.disoriented) return const Color(0xFFFF3D3D);
    if (level == RiskLevel.caution) return const Color(0xFFF0883E);
    return const Color(0xFF3FB950);
  }

  void _showAddWaypointDialog(LatLng position) {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'Water Source';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Add Offline Waypoint',
              style: TextStyle(color: Color(0xFFE6EDF3))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pin Name',
                  hintText: 'e.g. Fresh Water Stream',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                dropdownColor: const Color(0xFF1C2128),
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Water Source', child: Text('Water Source')),
                  DropdownMenuItem(value: 'Campsite', child: Text('Campsite')),
                  DropdownMenuItem(value: 'Junction', child: Text('Trail Junction')),
                  DropdownMenuItem(value: 'Hazard', child: Text('Hazard / Caution')),
                  DropdownMenuItem(value: 'Landmark', child: Text('Landmark')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => category = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Drinkable water, shelter available',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _waypointService.addWaypoint(
                  name: nameCtrl.text.trim(),
                  category: category,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _loadWaypoints();
              },
              child: const Text('Save Waypoint'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet() {
    final origin = _currentPos ?? _estimatedPos?.position;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      isScrollControlled: true,
      builder: (ctx) => _WaypointSearchSheet(
        origin: origin,
        onSelectLocation: (pos) {
          Navigator.pop(ctx);
          setState(() => _followUser = false);
          _mapCtrl.move(pos, 16);
        },
      ),
    );
  }

  void _showDownloadDialog({LatLngBounds? bounds}) {
    final nameCtrl = TextEditingController(
      text: 'Trail Region ${DateTime.now().month}/${DateTime.now().day}',
    );
    double minLat = bounds?.southWest.latitude ?? 12.879;
    double maxLat = bounds?.northEast.latitude ?? 12.939;
    double minLon = bounds?.southWest.longitude ?? 74.869;
    double maxLon = bounds?.northEast.longitude ?? 74.929;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Download Offline Region',
            style: TextStyle(color: Color(0xFFE6EDF3))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Color(0xFFE6EDF3)),
              decoration: const InputDecoration(
                labelText: 'Region Name',
                labelStyle: TextStyle(color: Color(0xFF8B949E)),
                hintText: 'e.g. Kudremukh Peak Trail',
                hintStyle: TextStyle(color: Color(0xFF8B949E)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Bounds: (${minLat.toStringAsFixed(3)}, ${minLon.toStringAsFixed(3)}) to (${maxLat.toStringAsFixed(3)}, ${maxLon.toStringAsFixed(3)})\nZoom levels: 13 – 17',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              OfflineRegionService.instance.downloadRegion(
                name: nameCtrl.text.trim().isEmpty
                    ? 'Offline Region'
                    : nameCtrl.text.trim(),
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download started in background...')),
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  // Calculate terrain slope color segments along breadcrumb trail
  List<Polyline> _buildSlopePolylines() {
    if (_rawGpsTrail.length < 2) return [];
    final polylines = <Polyline>[];
    const distanceCalc = Distance();

    for (int i = 0; i < _rawGpsTrail.length - 1; i++) {
      final p1 = _rawGpsTrail[i];
      final p2 = _rawGpsTrail[i + 1];

      final loc1 = LatLng(p1.latitude, p1.longitude);
      final loc2 = LatLng(p2.latitude, p2.longitude);

      final dHorizontal = distanceCalc(loc1, loc2);
      final dVertical = (p2.altitude - p1.altitude).abs();

      Color segmentColor = const Color(0xFF3FB950); // Flat < 5 deg

      if (dHorizontal > 0.5) {
        final slopeRad = atan(dVertical / dHorizontal);
        final slopeDeg = slopeRad * 180.0 / pi;

        if (slopeDeg >= AppConstants.steepTerrainSlopeDeg) {
          segmentColor = const Color(0xFFFF3D3D); // Steep > 20 deg
        } else if (slopeDeg >= AppConstants.flatTerrainSlopeDeg) {
          segmentColor = const Color(0xFFF0883E); // Moderate 5-20 deg
        }
      }

      polylines.add(
        Polyline(
          points: [loc1, loc2],
          color: segmentColor.withValues(alpha: 0.85),
          strokeWidth: 4,
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionService.currentSession == null) {
      if (_trail.isNotEmpty || _rawGpsTrail.isNotEmpty || _showRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _trail.clear();
              _rawGpsTrail.clear();
              _recoveryRoutingResult = null;
              _showRecovery = false;
              _prediction = null;
            });
          }
        });
      }
    }

    final activePos = _currentPos ?? _estimatedPos?.position ?? const LatLng(12.8698, 74.8435);
    final isDeadReckoning = _estimatedPos?.isDeadReckoning ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trail Map'),
        // Toolbar audit (map-style/options cleanup):
        // The old 4-way map style switcher (Dark/Roadmap/Satellite/Terrain)
        // has already been removed in an earlier pass — the map now always
        // renders in a single style, so there's no "view style" button to
        // show here at all. Everything below is a genuinely separate,
        // load-bearing feature (not leftover style-switcher clutter), kept
        // and clearly labeled rather than deleted:
        //   - search: offline waypoint search (Task 3)
        //   - show_chart: elevation/slope profile toggle
        //   - download_for_offline: THE "download map" action — opens the
        //     offline region manager pre-filled with the current visible
        //     area, ready to download in one tap
        //   - gps_fixed/gps_not_fixed: follow-me vs free-scroll toggle
        //   - undo: recovery-route guidance toggle (only shown mid-session)
        //   - pause/play: pause/resume the active hike session
        //   - cloud: online vs offline tile source toggle
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF8B949E)),
            tooltip: 'Search Waypoints',
            onPressed: _showSearchSheet,
          ),
          IconButton(
            tooltip: 'Download Tiles',
            icon: const Icon(Icons.download_for_offline, color: Color(0xFF3FB950)),
            onPressed: () {
              setState(() => _isSelectingDownloadArea = !_isSelectingDownloadArea);
            },
          ),
          IconButton(
            tooltip: _showRecovery ? 'Hide Recovery Route' : 'Show Recovery Route',
            icon: Icon(
              Icons.undo,
              color: _sessionService.currentSession == null 
                  ? const Color(0xFF30363D) // Disabled color
                  : (_showRecovery ? const Color(0xFFF0883E) : const Color(0xFF8B949E)),
            ),
            onPressed: _sessionService.currentSession == null 
              ? null 
              : () {
                  if (_showRecovery) {
                    _dismissRecovery();
                  } else {
                    _activateRecovery();
                  }
                },
          ),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: activePos,
            initialZoom: 15,
            maxZoom: _offlineMode ? 17 : 18,
            minZoom: _offlineMode ? 13 : 5,
            onTap: (_, pos) => setState(() => _followUser = false),
            onLongPress: (_, pos) => _showAddWaypointDialog(pos),
          ),
          children: [
            // Tile Layer
            TileLayer(
              urlTemplate: _offlineMode ? null : _tileUrl,
              userAgentPackageName: 'com.trailguard.app',
              tileProvider: DynamicOfflineTileProvider(),
              fallbackUrl: _offlineMode ? null : _fallbackTileUrl,
              maxZoom: _offlineMode ? 17 : 18,
            ),

            // Downloaded offline region coverage — visible confirmation of
            // what's actually available offline, drawn directly on the map.
            PolygonLayer(
              polygons: _downloadedRegions
                  .map((r) => Polygon(
                        points: [
                          LatLng(r.minLat, r.minLon),
                          LatLng(r.minLat, r.maxLon),
                          LatLng(r.maxLat, r.maxLon),
                          LatLng(r.maxLat, r.minLon),
                        ],
                        color: const Color(0xFF3FB950).withValues(alpha: 0.12),
                        borderColor: const Color(0xFF3FB950),
                        borderStrokeWidth: 2,
                        label: r.name,
                        labelStyle: const TextStyle(
                          color: Color(0xFF3FB950),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ))
                  .toList(),
            ),

            // Safe Zones
            CircleLayer(
              circles: _safeZones
                  .map((z) => CircleMarker(
                        point: LatLng(z.centerLat, z.centerLon),
                        radius: z.radiusMeters,
                        useRadiusInMeter: true,
                        color: const Color(0xFF3FB950).withValues(alpha: 0.15),
                        borderColor: const Color(0xFF3FB950),
                        borderStrokeWidth: 1.5,
                      ))
                  .toList(),
            ),

            // Recovery Route (Dijkstra Trail network or breadcrumb reverse)
            if (_showRecovery &&
                _recoveryRoutingResult != null &&
                _recoveryRoutingResult!.path.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points: _recoveryRoutingResult!.path,
                  color: const Color(0xFFF0883E),
                  strokeWidth: 5,
                  isDotted: true,
                ),
              ]),

            // Breadcrumb Trail (Color-coded slope lines when elevation profile ON)
            if (_trail.isNotEmpty)
              PolylineLayer(
                polylines: _showElevationProfile
                    ? _buildSlopePolylines()
                    : [
                        Polyline(
                          points: _trail,
                          color: const Color(0xFF3FB950).withValues(alpha: 0.8),
                          strokeWidth: 3,
                        ),
                      ],
              ),

            // Offline Waypoint Markers
            MarkerLayer(
              markers: _waypoints.map((wp) {
                Color wpColor;
                IconData wpIcon;
                switch (wp.category) {
                  case 'Water Source':
                    wpColor = const Color(0xFF58A6FF);
                    wpIcon = Icons.water_drop;
                    break;
                  case 'Campsite':
                    wpColor = const Color(0xFF3FB950);
                    wpIcon = Icons.cabin;
                    break;
                  case 'Junction':
                    wpColor = const Color(0xFFD29922);
                    wpIcon = Icons.alt_route;
                    break;
                  case 'Hazard':
                    wpColor = const Color(0xFFFF3D3D);
                    wpIcon = Icons.warning_amber;
                    break;
                  default:
                    wpColor = const Color(0xFFA371F7);
                    wpIcon = Icons.push_pin;
                }
                return Marker(
                  point: wp.location,
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: const Color(0xFF161B22),
                        builder: (ctx) => Container(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(wpIcon, color: wpColor),
                                  const SizedBox(width: 8),
                                  Text(wp.name,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFE6EDF3))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Category: ${wp.category}',
                                  style: const TextStyle(color: Color(0xFF8B949E))),
                              if (wp.notes != null) ...[
                                const SizedBox(height: 10),
                                Text(wp.notes!,
                                    style: const TextStyle(color: Color(0xFFE6EDF3))),
                              ],
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF3D3D)),
                                icon: const Icon(Icons.delete, color: Colors.white),
                                label: const Text('Delete Pin',
                                    style: TextStyle(color: Colors.white)),
                                onPressed: () async {
                                  await _waypointService.deleteWaypoint(wp.id);
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  _loadWaypoints();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: wpColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)
                        ],
                      ),
                      child: Icon(wpIcon, color: Colors.black, size: 18),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Peer Hiker Markers (P2P position sharing)
            MarkerLayer(
              markers: _peers.values.map((peer) {
                return Marker(
                  point: peer.position,
                  width: 60,
                  height: 44,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA371F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          peer.deviceName,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.person_pin_circle,
                          color: Color(0xFFA371F7), size: 22),
                    ],
                  ),
                );
              }).toList(),
            ),

            // Current Location Marker / Dead Reckoning Marker
            MarkerLayer(markers: [
              Marker(
                point: activePos,
                width: isDeadReckoning ? 34 : 24,
                height: isDeadReckoning ? 34 : 24,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDeadReckoning ? const Color(0xFFF0883E) : _markerColor,
                    border: Border.all(
                      color: isDeadReckoning ? Colors.amberAccent : Colors.white,
                      width: isDeadReckoning ? 3.0 : 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDeadReckoning ? Colors.orange : _markerColor)
                            .withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 3,
                      )
                    ],
                  ),
                  child: isDeadReckoning
                      ? const Icon(Icons.sensors_off, size: 16, color: Colors.black)
                      : null,
                ),
              ),
            ]),
          ],
        ),

        // Dead Reckoning GPS Loss Alert Banner
        if (isDeadReckoning)
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0883E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.black, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ESTIMATED POSITION (DEAD RECKONING) — GPS fix lost',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Turn-by-Turn Recovery Banner
        if (_showRecovery && _recoveryRoutingResult != null)
          Positioned(
            top: isDeadReckoning ? 52 : 12,
            left: 12,
            right: 12,
            child: _TurnByTurnRecoveryBanner(
              result: _recoveryRoutingResult!,
              onDismiss: _dismissRecovery,
            ),
          ),

        // Elevation Profile Sheet overlay
        if (_showElevationProfile && _rawGpsTrail.isNotEmpty)
          Positioned(
            bottom: 60,
            left: 12,
            right: 12,
            child: _ElevationProfileCard(trail: _rawGpsTrail),
          ),

        // Map Legend
        Positioned(
          bottom: 16,
          right: 16,
          child: _MapLegend(
            prediction: _prediction,
            showSlopeLegend: _showElevationProfile,
          ),
        ),

        // No tracking hint
        if (_sessionService.currentSession == null && !_isSelectingDownloadArea)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2128).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Start a hike to see your trail • Long-press map to drop pin',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                ),
              ),
            ),
          ),
          
        // Download Area Viewfinder
        if (_isSelectingDownloadArea)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF3FB950), width: 3),
                  color: const Color(0xFF3FB950).withOpacity(0.1),
                ),
                child: Center(
                  child: Icon(Icons.add, color: const Color(0xFF3FB950).withOpacity(0.5), size: 40),
                ),
              ),
            ),
          ),
        if (_isSelectingDownloadArea)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2128).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Pan map to frame the area you want to download',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C2128)),
                      onPressed: () {
                        setState(() => _isSelectingDownloadArea = false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OfflineRegionManagerScreen(
                              currentViewBounds: _mapCtrl.camera.visibleBounds,
                            ),
                          ),
                        ).then((_) => _loadDownloadedRegions());
                      },
                      child: const Text('View Downloaded', style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3FB950)),
                      onPressed: () {
                        setState(() => _isSelectingDownloadArea = false);
                        _showDownloadDialog(bounds: _mapCtrl.camera.visibleBounds);
                      },
                      child: const Text('Download Area', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

// Turn-by-Turn Recovery Guidance Banner Widget
class _TurnByTurnRecoveryBanner extends StatelessWidget {
  final RoutingResult result;
  final VoidCallback onDismiss;

  const _TurnByTurnRecoveryBanner({
    required this.result,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final nextStep = result.steps.isNotEmpty ? result.steps.first : null;
    final distKm = (result.totalDistanceMeters / 1000.0).toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0883E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)
        ],
      ),
      child: Row(children: [
        const Icon(Icons.turn_right, color: Colors.black, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    result.usedTrailNetwork
                        ? 'SMART OSM RECOVERY ROUTE'
                        : 'RECOVERY BREADCRUMB ROUTE',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                  Text('$distKm km left',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                nextStep != null
                    ? nextStep.instruction
                    : 'Follow dashed orange trail back to safety',
                style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 18),
          onPressed: onDismiss,
        )
      ]),
    );
  }
}

// Elevation Profile Card Widget
class _ElevationProfileCard extends StatelessWidget {
  final List<GpsPoint> trail;
  const _ElevationProfileCard({required this.trail});

  @override
  Widget build(BuildContext context) {
    if (trail.isEmpty) return const SizedBox.shrink();
    double minAlt = trail.first.altitude;
    double maxAlt = trail.first.altitude;

    for (final p in trail) {
      if (p.altitude < minAlt) minAlt = p.altitude;
      if (p.altitude > maxAlt) maxAlt = p.altitude;
    }

    final currentAlt = trail.last.altitude;
    final gain = maxAlt - minAlt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ELEVATION PROFILE',
                  style: TextStyle(
                      color: Color(0xFF3FB950),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              Text(
                'Current: ${currentAlt.toInt()}m | Gain: ${gain.toInt()}m',
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: Row(
              children: trail.take(40).map((p) {
                final heightFactor =
                    gain == 0 ? 0.5 : ((p.altitude - minAlt) / gain).clamp(0.1, 1.0);
                return Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 40 * heightFactor,
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      color: const Color(0xFF3FB950),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Waypoint Search Sheet
class _WaypointSearchSheet extends StatefulWidget {
  final ValueChanged<LatLng> onSelectLocation;
  final LatLng? origin;
  const _WaypointSearchSheet({required this.onSelectLocation, this.origin});

  @override
  State<_WaypointSearchSheet> createState() => _WaypointSearchSheetState();
}

class _WaypointSearchSheetState extends State<_WaypointSearchSheet> {
  final _waypointService = WaypointService.instance;
  final _searchCtrl = TextEditingController();
  final _distance = const Distance();
  List<OfflineWaypoint> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  // Live-updating as the user types (called from onChanged, not a submit
  // button) and sorted nearest-first from the user's current GPS position —
  // entirely offline, no network lookup.
  Future<void> _search(String query) async {
    final list = await _waypointService.searchWaypoints(query);
    final origin = widget.origin;
    if (origin != null) {
      list.sort((a, b) => _distance
          .as(LengthUnit.Meter, origin, a.location)
          .compareTo(_distance.as(LengthUnit.Meter, origin, b.location)));
    }
    if (mounted) setState(() => _results = list);
  }

  String _distanceLabel(OfflineWaypoint wp) {
    final origin = widget.origin;
    if (origin == null) return wp.category;
    final meters = _distance.as(LengthUnit.Meter, origin, wp.location);
    final distStr = meters < 1000
        ? '${meters.toStringAsFixed(0)} m away'
        : '${(meters / 1000).toStringAsFixed(1)} km away';
    return '${wp.category} • $distStr';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search offline waypoints...',
              prefixIcon: Icon(Icons.search, color: Color(0xFF8B949E)),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: _results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No waypoints yet.\n\nThis searches pins you\'ve saved — '
                        'long-press anywhere on the map to drop one (e.g. '
                        '"Vamanjoor Junction", a water source, a landmark).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8B949E), height: 1.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final wp = _results[i];
                      return ListTile(
                        leading: const Icon(Icons.place, color: Color(0xFF3FB950)),
                        title: Text(wp.name,
                            style: const TextStyle(color: Color(0xFFE6EDF3))),
                        subtitle: Text(_distanceLabel(wp),
                            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                        onTap: () => widget.onSelectLocation(wp.location),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Map Legend Widget
class _MapLegend extends StatelessWidget {
  final SafetyPrediction? prediction;
  final bool showSlopeLegend;

  const _MapLegend({this.prediction, this.showSlopeLegend = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _LegendItem(color: Color(0xFF3FB950), label: 'Trail'),
        if (showSlopeLegend) ...[
          const _LegendItem(color: Color(0xFFF0883E), label: 'Mod. Slope (5°-20°)'),
          const _LegendItem(color: Color(0xFFFF3D3D), label: 'Steep (>20°)'),
        ],
        _LegendItem(
            color: const Color(0xFF3FB950).withValues(alpha: 0.4), label: 'Safe Zone'),
        const _LegendItem(color: Color(0xFFF0883E), label: 'Recovery'),
        const _LegendItem(color: Color(0xFFA371F7), label: 'Peer Hiker'),
        if (prediction != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Conf: ${prediction!.confidenceScore}%',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10),
            ),
          ),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Container(
            width: 12,
            height: 4,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
      ]),
    );
  }
}
