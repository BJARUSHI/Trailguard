import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/gps_point.dart';
import '../../core/services/gps_tracking_service.dart';
import '../../core/services/sms_alert_service.dart';
import 'stillness_check_dialog.dart'; // To reuse StillnessAlarmController

class DisorientationCheckDialog extends StatefulWidget {
  const DisorientationCheckDialog({super.key});

  @override
  State<DisorientationCheckDialog> createState() => _DisorientationCheckDialogState();
}

enum _DialogState { sending, sent }

class _DisorientationCheckDialogState extends State<DisorientationCheckDialog> {
  final _smsService = SmsAlertService.instance;
  final _gps = GpsTrackingService.instance;

  _DialogState _state = _DialogState.sending;

  @override
  void initState() {
    super.initState();
    StillnessAlarmController.start();
    _sendAlert();
  }

  Future<void> _sendAlert() async {
    setState(() => _state = _DialogState.sending);
    final pos = _gps.lastPoint;
    try {
      await _smsService.sendEmergencyAlert(
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
    } catch (_) {
      // Ignore SMS errors in the dialog
    }
    if (!mounted) return;
    setState(() => _state = _DialogState.sent);
    
    // Stop the alarm after a few seconds or when dismissed
    await Future.delayed(const Duration(seconds: 4));
    await StillnessAlarmController.stop();
  }

  Future<void> _dismiss() async {
    await StillnessAlarmController.stop();
    if (mounted) _closeRoute();
  }

  void _closeRoute() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF5A1000), // A dark reddish color
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_off, color: Colors.white, size: 80),
                const SizedBox(height: 20),
                const Text(
                  'Disorientation Detected!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your movement patterns suggest you may be lost.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 40),
                if (_state == _DialogState.sending) ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text('Sending emergency SMS...',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ] else ...[
                  const Icon(Icons.check_circle, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  const Text('Emergency SMS sent to your contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _dismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF5A1000),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("I'm okay",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
