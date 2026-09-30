import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/waypoint_service.dart';

class StartSessionDialog extends StatefulWidget {
  const StartSessionDialog({super.key});

  @override
  State<StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<StartSessionDialog> {
  final _nameCtrl = TextEditingController();
  bool _hasDestination = false;

  List<OfflineWaypoint> _waypoints = [];
  bool _isLoadingWaypoints = true;
  OfflineWaypoint? _selectedWaypoint;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text =
        'Hike ${DateFormat('MMM d · HH:mm').format(DateTime.now())}';
    _loadWaypoints();
  }

  Future<void> _loadWaypoints() async {
    final wps = await WaypointService.instance.getAllWaypoints();
    if (mounted) {
      setState(() {
        _waypoints = wps;
        _isLoadingWaypoints = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    double? destLat;
    double? destLon;
    if (_hasDestination) {
      if (_selectedWaypoint == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please select a destination waypoint')),
        );
        return;
      }
      destLat = _selectedWaypoint!.latitude;
      destLon = _selectedWaypoint!.longitude;
    }

    Navigator.pop(context, {
      'name': _nameCtrl.text.trim().isEmpty
          ? 'Hike ${DateTime.now().hour}:${DateTime.now().minute}'
          : _nameCtrl.text.trim(),
      'destLat': destLat,
      'destLon': destLon,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C2128),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.hiking, color: Color(0xFF3FB950), size: 24),
        SizedBox(width: 10),
        Text('Start New Hike',
            style: TextStyle(
                color: Color(0xFFE6EDF3),
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Color(0xFFE6EDF3)),
            decoration: const InputDecoration(
              labelText: 'Hike Name',
              prefixIcon: Icon(Icons.label_outline,
                  color: Color(0xFF8B949E), size: 20),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Set Destination Waypoint',
                style: TextStyle(color: Color(0xFFE6EDF3), fontSize: 14)),
            subtitle: const Text('For progress tracking & navigation',
                style:
                    TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            value: _hasDestination,
            activeThumbColor: const Color(0xFF3FB950),
            onChanged: (v) => setState(() => _hasDestination = v),
          ),
          if (_hasDestination) ...[
            const SizedBox(height: 8),
            if (_isLoadingWaypoints)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_waypoints.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D333B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFD29922), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No saved waypoints found. Add waypoints in the Map screen first.',
                      style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                    ),
                  ),
                ]),
              )
            else
              DropdownButtonFormField<OfflineWaypoint>(
                value: _selectedWaypoint,
                dropdownColor: const Color(0xFF1C2128),
                style: const TextStyle(color: Color(0xFFE6EDF3)),
                decoration: const InputDecoration(
                  labelText: 'Select Waypoint',
                  prefixIcon: Icon(Icons.location_on_outlined,
                      color: Color(0xFF8B949E), size: 20),
                ),
                items: _waypoints.map((wp) {
                  return DropdownMenuItem(
                    value: wp,
                    child: Text(wp.name),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedWaypoint = val;
                  });
                },
              ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3FB950).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF3FB950).withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline,
                  color: Color(0xFF3FB950), size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TrailGuard will monitor your movement and alert you if disorientation is detected.',
                  style: TextStyle(
                      color: Color(0xFF8B949E), fontSize: 11),
                ),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF8B949E))),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start Hike'),
        ),
      ],
    );
  }
}
