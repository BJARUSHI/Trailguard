import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Pre-downloaded offline tile area for TrailGuard fallback.
class OfflineMapArea {
  static const double minLat = 12.879;
  static const double maxLat = 12.939;
  static const double minLon = 74.869;
  static const double maxLon = 74.929;
  static const int minZoom = 13;
  static const int maxZoom = 17;
}

int _lonToTileX(double lon, int z) {
  return ((lon + 180.0) / 360.0 * (1 << z)).floor();
}

int _latToTileY(double lat, int z) {
  final rad = lat * pi / 180.0;
  return ((1.0 - log(tan(rad) + 1.0 / cos(rad)) / pi) / 2.0 * (1 << z)).floor();
}

// Solid neutral grey (#2D333B, matches the app's card background) — used
// when no tile is available at all (offline mode, outside any downloaded
// region). A transparent pixel here was letting the dark scaffold behind
// the map show through as a solid black rectangle, which looked like a
// rendering bug rather than "no offline data for this area."
final Uint8List _blankTileBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPQNbb+DwACxwGbrPXL0QAAAABJRU5ErkJggg==',
);

/// Dynamic tile provider checking local user-downloaded regions first,
/// then bundled assets, then blank tile fallback.
class DynamicOfflineTileProvider extends TileProvider {
  static String? _appDocPath;

  static Future<void> initPath() async {
    if (_appDocPath == null) {
      final docDir = await getApplicationDocumentsDirectory();
      _appDocPath = docDir.path;
    }
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final z = coordinates.z;
    final x = coordinates.x;
    final y = coordinates.y;

    // 1. Check user-downloaded regions in application documents directory FIRST
    if (_appDocPath != null) {
      final offlineTilesDir = Directory(p.join(_appDocPath!, 'offline_tiles'));
      if (offlineTilesDir.existsSync()) {
        final regionDirs = offlineTilesDir.listSync();
        for (final entity in regionDirs) {
          if (entity is Directory) {
            final tileFile = File(p.join(entity.path, '$z', '$x', '$y.png'));
            if (tileFile.existsSync()) {
              return FileImage(tileFile);
            }
          }
        }
      }
    }

    // 2. Check bundled asset tiles
    if (z >= OfflineMapArea.minZoom && z <= OfflineMapArea.maxZoom) {
      final minX = _lonToTileX(OfflineMapArea.minLon, z);
      final maxX = _lonToTileX(OfflineMapArea.maxLon, z);
      final minY = _latToTileY(OfflineMapArea.maxLat, z);
      final maxY = _latToTileY(OfflineMapArea.minLat, z);

      if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
        return AssetImage('assets/maps/${z}_${x}_$y.png');
      }
    }

    // 3. If online mode is active (urlTemplate is provided), fetch from network.
    if (options.urlTemplate != null) {
      final url = options.urlTemplate!
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString())
          .replaceAll('{z}', z.toString());
      return NetworkImage(url, headers: const {'User-Agent': 'TrailGuard/1.0'});
    }

    // 4. Fallback blank tile so application never crashes
    return MemoryImage(_blankTileBytes);
  }
}

class OfflineAssetTileProvider extends DynamicOfflineTileProvider {}
