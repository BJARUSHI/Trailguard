import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/services/offline_region_service.dart';

/// Module N: Offline Map Region Manager Screen
class OfflineRegionManagerScreen extends StatefulWidget {
  final LatLngBounds? currentViewBounds;

  const OfflineRegionManagerScreen({super.key, this.currentViewBounds});

  @override
  State<OfflineRegionManagerScreen> createState() =>
      _OfflineRegionManagerScreenState();
}

class _OfflineRegionManagerScreenState
    extends State<OfflineRegionManagerScreen> {
  final _offlineService = OfflineRegionService.instance;
  List<OfflineRegion> _regions = [];
  bool _isLoading = true;
  DownloadProgress? _activeProgress;
  StreamSubscription<DownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    _loadRegions();
    _progressSub = _offlineService.progressStream.listen((progress) {
      setState(() {
        _activeProgress = progress;
      });
      if (progress.isCompleted) {
        _loadRegions();
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() => _isLoading = true);
    final regions = await _offlineService.getSavedRegions();
    setState(() {
      _regions = regions;
      _isLoading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
              decoration: const InputDecoration(
                labelText: 'Region Name',
                hintText: 'e.g. Kudremukh Peak Trail',
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
              _offlineService.downloadRegion(
                name: nameCtrl.text.trim().isEmpty
                    ? 'Offline Region'
                    : nameCtrl.text.trim(),
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon,
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Regions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Download Region',
            onPressed: () => _showDownloadDialog(bounds: widget.currentViewBounds),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_activeProgress != null && !_activeProgress!.isCompleted)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1C2128),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _activeProgress!.statusText,
                        style: const TextStyle(
                            color: Color(0xFF3FB950), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${(_activeProgress!.percentage * 100).toInt()}%',
                        style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _activeProgress!.percentage,
                    backgroundColor: const Color(0xFF30363D),
                    color: const Color(0xFF3FB950),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _regions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_for_offline_outlined,
                                size: 56, color: Color(0xFF8B949E)),
                            const SizedBox(height: 12),
                            const Text(
                              'No downloaded offline regions yet',
                              style: TextStyle(color: Color(0xFF8B949E), fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Download Region'),
                              onPressed: () =>
                                  _showDownloadDialog(bounds: widget.currentViewBounds),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _regions.length,
                        itemBuilder: (context, index) {
                          final region = _regions[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const Icon(Icons.map_outlined,
                                  color: Color(0xFF3FB950), size: 32),
                              title: Text(
                                region.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE6EDF3)),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Tiles: ${region.tileCount} • Size: ${_formatBytes(region.sizeBytes)}\nZoom: ${region.minZoom}-${region.maxZoom}',
                                  style: const TextStyle(
                                      color: Color(0xFF8B949E), fontSize: 12),
                                ),
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFFF3D3D)),
                                tooltip: 'Delete region',
                                onPressed: () async {
                                  await _offlineService.deleteRegion(region.id);
                                  _loadRegions();
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
