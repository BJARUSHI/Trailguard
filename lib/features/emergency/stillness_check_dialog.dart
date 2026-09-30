import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/gps_point.dart';
import '../../core/services/alert_service.dart';
import '../../core/services/gps_tracking_service.dart';
import '../../core/services/hiking_session_service.dart';
import '../../core/services/sms_alert_service.dart';
import '../../core/services/stillness_detection_service.dart';

/// Plays the loud looping alarm sound + repeating vibration pattern used by
/// the stillness check. Kept separate from the dialog widget so both can be
/// started/stopped independently of build/dispose timing.
///
/// Vibration is done via Flutter's built-in HapticFeedback (no extra native
/// plugin/Gradle dependency) driven by a repeating timer to get an
/// alarm-style on/off pulse.
class StillnessAlarmController {
  static final AudioPlayer _player = AudioPlayer();
  static bool _playing = false;
  static Timer? _vibrateTimer;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;

    // Pulse repeatedly (roughly every 800ms) — separate from the sound, so
    // the alert is felt even if audio fails or the device is muted in a way
    // that also silences media/alarm streams.
    HapticFeedback.heavyImpact();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      HapticFeedback.heavyImpact();
    });

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      // Route through the ALARM audio stream on Android so it plays even
      // when the ringer/notification volume is silenced.
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ));
      await _player.play(AssetSource('sounds/alarm.mp3'));
    } catch (_) {
      // Missing/invalid asset shouldn't crash the alert — vibration and
      // the full-screen dialog still get the point across.
    }
  }

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      await _player.stop();
    } catch (_) {}
  }
}

/// Full-screen, non-dismissible "Are you okay?" check shown when
/// [StillnessDetectionService] detects no meaningful movement for too long.
class StillnessCheckDialog extends StatefulWidget {
  final GpsPoint triggerPoint;
  const StillnessCheckDialog({super.key, required this.triggerPoint});

  @override
  State<StillnessCheckDialog> createState() => _StillnessCheckDialogState();
}

enum _StillnessDialogState { counting, sending, sent }

class _StillnessCheckDialogState extends State<StillnessCheckDialog> {
  final _stillnessService = StillnessDetectionService.instance;
  final _smsService = SmsAlertService.instance;
  final _sessionService = HikingSessionService.instance;
  final _gps = GpsTrackingService.instance;

  late int _secondsLeft;
  Timer? _timer;
  StreamSubscription<void>? _movementSub;
  _StillnessDialogState _state = _StillnessDialogState.counting;

  @override
  void initState() {
    super.initState();
    _secondsLeft = AppConstants.stillnessCountdownSeconds;
    StillnessAlarmController.start();
    AlertService.instance.showStillnessAlertNotification();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _movementSub = _stillnessService.movementResumedStream.listen((_) {
      if (mounted) _dismiss(sendAlert: false);
    });
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) {
      _timer?.cancel();
      _sendAlert();
    }
  }

  Future<void> _sendAlert() async {
    setState(() => _state = _StillnessDialogState.sending);
    final pos = _gps.lastPoint ?? widget.triggerPoint;
    await _sessionService.logEmergency(
      'Stillness alert auto-activated: no movement for '
      '${AppConstants.stillnessAlertThresholdSeconds} seconds',
    );
    try {
      await _smsService.sendEmergencyAlert(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      // Emergency log already saved regardless of SMS delivery outcome.
    }
    if (!mounted) return;
    setState(() => _state = _StillnessDialogState.sent);
    await StillnessAlarmController.stop();
    await AlertService.instance.cancelStillnessAlertNotification();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) _closeRoute();
  }

  Future<void> _dismiss({required bool sendAlert}) async {
    _timer?.cancel();
    await StillnessAlarmController.stop();
    await AlertService.instance.cancelStillnessAlertNotification();
    _stillnessService.resetAfterAlert(_gps.lastPoint ?? widget.triggerPoint);
    if (mounted) _closeRoute();
  }

  void _closeRoute() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _movementSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Not dismissible via back button — must respond via the button.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF3D0000),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
                const SizedBox(height: 20),
                const Text(
                  'Are you okay?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No movement detected for ${AppConstants.stillnessAlertThresholdSeconds} seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 40),
                if (_state == _StillnessDialogState.counting) ...[
                  Text(
                    '$_secondsLeft',
                    style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'seconds until an emergency SMS is sent',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _dismiss(sendAlert: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF3D0000),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("I'm okay",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ] else if (_state == _StillnessDialogState.sending) ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text('Sending emergency alert...',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ] else ...[
                  const Icon(Icons.check_circle, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  const Text('Emergency alert sent to your contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
