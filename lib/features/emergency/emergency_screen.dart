import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/services/hiking_session_service.dart';
import '../../core/services/gps_tracking_service.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/gps_point.dart';
import '../../core/services/sms_alert_service.dart';
import '../../core/services/stillness_detection_service.dart';
import '../../core/constants/app_constants.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _sessionService = HikingSessionService.instance;
  final _gps = GpsTrackingService.instance;
  final _db = DatabaseHelper.instance;
  final _smsService = SmsAlertService.instance;
  final _stillnessService = StillnessDetectionService.instance;
  bool _stillnessAlertEnabled = true;
  GpsPoint? _lastKnownPos;
  bool _emergencyActive = false;
  List<EmergencyContact> _contacts = [];
  bool _sendingSms = false;

  @override
  void initState() {
    super.initState();
    _updateLocation();
    _loadContacts();
    _stillnessAlertEnabled = _stillnessService.isEnabled;
  }

  Future<void> _updateLocation() async {
    if (_gps.lastPoint != null) {
      setState(() => _lastKnownPos = _gps.lastPoint);
    }
    final fresh = await _gps.getCurrentLocation(
      _sessionService.currentSession?.id ?? 'emergency',
    );
    if (fresh != null && mounted) {
      setState(() => _lastKnownPos = fresh);
    }
  }

  Future<void> _loadContacts() async {
    final contacts = await _smsService.getContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _addContactDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2128),
        title: const Text('Add Emergency Contact', style: TextStyle(color: Color(0xFFE6EDF3))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Color(0xFFE6EDF3)),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            style: const TextStyle(color: Color(0xFFE6EDF3)),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number (with country code)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E)))),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _smsService.addContact(nameCtrl.text.trim(), phoneCtrl.text.trim());
      await _loadContacts();
    }
  }

  Future<void> _removeContact(int index) async {
    await _smsService.removeContact(index);
    await _loadContacts();
  }

  Future<void> _triggerSOS() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2128),
        title: const Text('Confirm SOS', style: TextStyle(color: Color(0xFFFF3D3D))),
        content: Text(
          _contacts.isEmpty
              ? 'This activates Emergency Mode and saves your location.\n\nNote: No emergency contacts saved, so no SMS will be sent. Add a contact below first if you want an alert sent.'
              : 'This activates Emergency Mode, saves your location, and sends an SMS alert to your ${_contacts.length} saved contact(s).',
          style: const TextStyle(color: Color(0xFF8B949E)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8B949E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3D3D)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activate SOS'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _updateLocation();
    await _sessionService.logEmergency('Manual SOS activated by hiker');
    setState(() => _emergencyActive = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Emergency mode activated. Location saved.'),
        backgroundColor: Color(0xFFFF3D3D),
      ));
    }

    if (_contacts.isNotEmpty) {
      await _sendSmsAlert();
    }
  }

  Future<void> _sendSmsAlert() async {
    setState(() => _sendingSms = true);
    try {
      final results = await _smsService.sendEmergencyAlert(
        latitude: _lastKnownPos?.latitude,
        longitude: _lastKnownPos?.longitude,
      );
      final sentCount = results.values.where((ok) => ok).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('SOS SMS sent to $sentCount of ${results.length} contact(s).'),
          backgroundColor: sentCount == results.length ? const Color(0xFF3FB950) : const Color(0xFFF0883E),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not send SMS: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: const Color(0xFFFF3D3D),
        ));
      }
    } finally {
      if (mounted) setState(() => _sendingSms = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final pos = _lastKnownPos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _updateLocation)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: (_emergencyActive || _sendingSms) ? null : _triggerSOS,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: _emergencyActive ? const Color(0x33FF3D3D) : const Color(0xFFFF3D3D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF3D3D), width: 2),
              ),
              child: Column(children: [
                Icon(_emergencyActive ? Icons.emergency : Icons.sos,
                    size: 48, color: _emergencyActive ? const Color(0xFFFF3D3D) : Colors.white),
                const SizedBox(height: 8),
                Text(_emergencyActive ? 'EMERGENCY ACTIVE' : 'SOS - EMERGENCY',
                    style: TextStyle(
                      color: _emergencyActive ? const Color(0xFFFF3D3D) : Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
                Text(
                  _sendingSms
                      ? 'Sending SMS alert...'
                      : (_emergencyActive ? 'Emergency logged.' : 'Tap to activate emergency mode'),
                  style: TextStyle(
                      color: _emergencyActive ? const Color(0xFFFF3D3D) : Colors.white,
                      fontSize: 13),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LAST KNOWN LOCATION', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
              const Divider(height: 16, color: Color(0xFF30363D)),
              _InfoRow('Latitude', pos?.latitude.toStringAsFixed(6) ?? 'No GPS signal'),
              _InfoRow('Longitude', pos?.longitude.toStringAsFixed(6) ?? 'No GPS signal'),
              _InfoRow('Altitude', pos != null ? '${pos.altitude.toStringAsFixed(1)} m' : 'Unknown'),
            ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('EMERGENCY CONTACTS', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF3FB950), size: 20),
                  onPressed: _addContactDialog,
                  tooltip: 'Add contact',
                ),
              ]),
              const Divider(height: 16, color: Color(0xFF30363D)),
              if (_contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No contacts saved. Add one so SOS can text them.',
                      style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                )
              else
                ..._contacts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final c = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF8B949E)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${c.name} — ${c.phone}',
                          style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13))),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF3D3D)),
                        onPressed: () => _removeContact(i),
                        tooltip: 'Remove',
                      ),
                    ]),
                  );
                }),
            ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Expanded(
                  child: Text('STILLNESS ALERT', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
                ),
                Switch(
                  value: _stillnessAlertEnabled,
                  onChanged: (val) async {
                    setState(() => _stillnessAlertEnabled = val);
                    await _stillnessService.setEnabled(val);
                  },
                ),
              ]),
              const Divider(height: 16, color: Color(0xFF30363D)),
              const Text(
                'If no movement is detected for '
                '${AppConstants.stillnessAlertThresholdSeconds} seconds during a session, '
                "TrailGuard will show a full-screen \"Are you okay?\" check "
                '(with alarm + vibration). If you don\'t respond within '
                '${AppConstants.stillnessCountdownSeconds} seconds, an emergency SMS is sent automatically.',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
              ),
            ]))),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('EMERGENCY ACTIONS', style: TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
              const Divider(height: 16, color: Color(0xFF30363D)),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _contacts.isEmpty || _sendingSms ? null : _sendSmsAlert,
                icon: const Icon(Icons.sms_outlined, color: Color(0xFFFF3D3D)),
                label: Text(_sendingSms ? 'Sending...' : 'Send SOS SMS Now',
                    style: const TextStyle(color: Color(0xFFFF3D3D))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFF3D3D)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),

            ]))),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 100, child: Text(label,
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 12))),
        Expanded(child: Text(value,
            style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
