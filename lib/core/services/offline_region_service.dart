import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';

class OfflineRegion {
  final String id;
  final String name;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final int sizeBytes;
  final DateTime createdAt;

  OfflineRegion({
    required this.id,
    required this.name,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.sizeBytes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'min_lat': minLat,
        'max_lat': maxLat,
        'min_lon': minLon,
        'max_lon': maxLon,
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
        'tile_count': tileCount,
        'size_bytes': sizeBytes,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory OfflineRegion.fromMap(Map<String, dynamic> map) => OfflineRegion(
        id: map['id'] as String,
        name: map['name'] as String,
        minLat: (map['min_lat'] as num).toDouble(),
        maxLat: (map['max_lat'] as num).toDouble(),
        minLon: (map['min_lon'] as num).toDouble(),
        maxLon: (map['max_lon'] as num).toDouble(),
        minZoom: map['min_zoom'] as int,
        maxZoom: map['max_zoom'] as int,
        tileCount: map['tile_count'] as int,
        sizeBytes: map['size_bytes'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  bool containsTile(int z, int x, int y) {
    if (z < minZoom || z > maxZoom) return false;
    final minX = lonToTileX(minLon, z);
    final maxX = lonToTileX(maxLon, z);
    final minY = latToTileY(maxLat, z);
    final maxY = latToTileY(minLat, z);
    final tileXMin = min(minX, maxX);
    final tileXMax = max(minX, maxX);
    final tileYMin = min(minY, maxY);
    final tileYMax = max(minY, maxY);
    return x >= tileXMin && x <= tileXMax && y >= tileYMin && y <= tileYMax;
  }

  static int lonToTileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  static int latToTileY(double lat, int z) {
    final rad = lat * pi / 180.0;
    return ((1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << z)).floor();
  }
}

class DownloadProgress {
  final int downloaded;
  final int total;
  final String statusText;
  final bool isCompleted;
  final String? error;

  DownloadProgress({
    required this.downloaded,
    required this.total,
    required this.statusText,
    this.isCompleted = false,
    this.error,
  });

  double get percentage => total == 0 ? 0.0 : (downloaded / total).clamp(0.0, 1.0);
}

/// Module N: In-app Offline Map Region Manager & Downloading Service
class OfflineRegionService {
  static final OfflineRegionService instance = OfflineRegionService._();
  OfflineRegionService._();

  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;

  Directory? _baseDir;

  Future<Directory> get baseTileDirectory async {
    if (_baseDir != null) return _baseDir!;
    final appDocDir = await getApplicationDocumentsDirectory();
    final tilesDir = Directory(p.join(appDocDir.path, 'offline_tiles'));
    if (!await tilesDir.exists()) {
      await tilesDir.create(recursive: true);
    }
    _baseDir = tilesDir;
    return _baseDir!;
  }

  Future<List<OfflineRegion>> getSavedRegions() async {
    final maps = await _db.getAllOfflineRegions();
    return maps.map(OfflineRegion.fromMap).toList();
  }

  Future<File?> getTileFile(int z, int x, int y) async {
    final baseDir = await baseTileDirectory;
    final regions = await getSavedRegions();
    for (final region in regions) {
      if (region.containsTile(z, x, y)) {
        final tileFile = File(p.join(baseDir.path, region.id, '$z', '$x', '$y.png'));
        if (await tileFile.exists()) {
          return tileFile;
        }
      }
    }
    return null;
  }

  Future<OfflineRegion?> downloadRegion({
    required String name,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    int minZoom = 13,
    int maxZoom = 17,
  }) async {
    final regionId = _uuid.v4();
    final baseDir = await baseTileDirectory;
    final regionDir = Directory(p.join(baseDir.path, regionId));
    await regionDir.create(recursive: true);

    // Calculate total tiles
    final tilesToDownload = <TileCoords>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final x1 = OfflineRegion.lonToTileX(minLon, z);
      final x2 = OfflineRegion.lonToTileX(maxLon, z);
      final y1 = OfflineRegion.latToTileY(maxLat, z);
      final y2 = OfflineRegion.latToTileY(minLat, z);

      final minX = min(x1, x2);
      final maxX = max(x1, x2);
      final minY = min(y1, y2);
      final maxY = max(y1, y2);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tilesToDownload.add(TileCoords(z, x, y));
        }
      }
    }

    int downloaded = 0;
    int totalBytes = 0;
    final client = HttpClient();
    client.userAgent = 'TrailGuard-Hackathon-Project/1.0 (student project, low volume)';

    _progressController.add(DownloadProgress(
      downloaded: 0,
      total: tilesToDownload.length,
      statusText: 'Starting tile download...',
    ));

    int nextIndex = 0;
    const maxConcurrent = 8;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex++;
        if (i >= tilesToDownload.length) break;

        final tile = tilesToDownload[i];
        final tileFile = File(p.join(regionDir.path, '${tile.z}', '${tile.x}', '${tile.y}.png'));
        await tileFile.parent.create(recursive: true);

        if (await tileFile.exists()) {
          downloaded++;
          totalBytes += await tileFile.length();
          continue;
        }

        final url = Uri.parse('https://tile.openstreetmap.org/${tile.z}/${tile.x}/${tile.y}.png');
        try {
          final request = await client.getUrl(url);
          final response = await request.close().timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(response);
            await tileFile.writeAsBytes(bytes);
            totalBytes += bytes.length;
            downloaded++;
          }
        } catch (e) {
          // Continue best-effort
        }

        _progressController.add(DownloadProgress(
          downloaded: downloaded,
          total: tilesToDownload.length,
          statusText: 'Downloading tile $downloaded / ${tilesToDownload.length}',
        ));

        // Friendly rate limiting delay
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    final workers = List.generate(maxConcurrent, (_) => worker());
    await Future.wait(workers);

    client.close();

    final region = OfflineRegion(
      id: regionId,
      name: name,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      minZoom: minZoom,
      maxZoom: maxZoom,
      tileCount: downloaded,
      sizeBytes: totalBytes,
      createdAt: DateTime.now(),
    );

    await _db.insertOfflineRegion(region.toMap());

    _progressController.add(DownloadProgress(
      downloaded: downloaded,
      total: tilesToDownload.length,
      statusText: 'Download complete!',
      isCompleted: true,
    ));

    return region;
  }

  /// Download tiles ahead of route with buffer radius (approx 0.015 degrees ~ 1.5km buffer)
  Future<OfflineRegion?> preCacheRouteRegion({
    required String name,
    required List<LatLng> routePoints,
    double bufferDegrees = 0.015,
  }) async {
    if (routePoints.isEmpty) return null;
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLon = routePoints.first.longitude;
    double maxLon = routePoints.first.longitude;

    for (final p in routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    return downloadRegion(
      name: name,
      minLat: minLat - bufferDegrees,
      maxLat: maxLat + bufferDegrees,
      minLon: minLon - bufferDegrees,
      maxLon: maxLon + bufferDegrees,
      minZoom: 13,
      maxZoom: 17,
    );
  }

  Future<void> deleteRegion(String regionId) async {
    await _db.deleteOfflineRegion(regionId);
    final baseDir = await baseTileDirectory;
    final regionDir = Directory(p.join(baseDir.path, regionId));
    if (await regionDir.exists()) {
      await regionDir.delete(recursive: true);
    }
  }
}

class TileCoords {
  final int z;
  final int x;
  final int y;
  TileCoords(this.z, this.x, this.y);
}
